#import "MemScanBridge.h"

#import <mach/mach.h>
#import <mach/vm_map.h>
#import <mach/vm_region.h>
#import <mach/vm_statistics.h>
#import <sys/sysctl.h>
#import <sys/proc.h>
#import <unistd.h>
#import <vector>
#import <cmath>
#import <cstring>

static task_t g_task = MACH_PORT_NULL;
static std::vector<MSScanMatch> g_results;
static MSDataType g_currentDataType = MSDataTypeInt32;

static NSError *MSError(NSString *message, NSInteger code) {
    return [NSError errorWithDomain:@"MemScan" code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

static int DataTypeSize(MSDataType type) {
    switch (type) {
        case MSDataTypeInt8:
        case MSDataTypeUInt8: return 1;
        case MSDataTypeInt16:
        case MSDataTypeUInt16: return 2;
        case MSDataTypeInt32:
        case MSDataTypeUInt32:
        case MSDataTypeFloat: return 4;
        case MSDataTypeInt64:
        case MSDataTypeUInt64:
        case MSDataTypeDouble: return 8;
    }
    return 4;
}

static bool IsFloating(MSDataType type) {
    return type == MSDataTypeFloat || type == MSDataTypeDouble;
}

static double ReadTypedValue(const uint8_t *bytes, MSDataType type) {
    switch (type) {
        case MSDataTypeInt8: return (double)*(const int8_t *)bytes;
        case MSDataTypeInt16: return (double)*(const int16_t *)bytes;
        case MSDataTypeInt32: return (double)*(const int32_t *)bytes;
        case MSDataTypeInt64: return (double)*(const int64_t *)bytes;
        case MSDataTypeUInt8: return (double)*(const uint8_t *)bytes;
        case MSDataTypeUInt16: return (double)*(const uint16_t *)bytes;
        case MSDataTypeUInt32: return (double)*(const uint32_t *)bytes;
        case MSDataTypeUInt64: return (double)*(const uint64_t *)bytes;
        case MSDataTypeFloat: return (double)*(const float *)bytes;
        case MSDataTypeDouble: return *(const double *)bytes;
    }
    return 0;
}

static bool WriteTypedValue(uint8_t *bytes, MSDataType type, double value) {
    switch (type) {
        case MSDataTypeInt8: *(int8_t *)bytes = (int8_t)llround(value); return true;
        case MSDataTypeInt16: *(int16_t *)bytes = (int16_t)llround(value); return true;
        case MSDataTypeInt32: *(int32_t *)bytes = (int32_t)llround(value); return true;
        case MSDataTypeInt64: *(int64_t *)bytes = (int64_t)llround(value); return true;
        case MSDataTypeUInt8: *(uint8_t *)bytes = (uint8_t)llround(fmax(0, value)); return true;
        case MSDataTypeUInt16: *(uint16_t *)bytes = (uint16_t)llround(fmax(0, value)); return true;
        case MSDataTypeUInt32: *(uint32_t *)bytes = (uint32_t)llround(fmax(0, value)); return true;
        case MSDataTypeUInt64: *(uint64_t *)bytes = (uint64_t)llround(fmax(0, value)); return true;
        case MSDataTypeFloat: *(float *)bytes = (float)value; return true;
        case MSDataTypeDouble: *(double *)bytes = value; return true;
    }
    return false;
}

static bool ValuesEqual(double a, double b, MSDataType type) {
    if (IsFloating(type)) {
        const double epsilon = (type == MSDataTypeFloat) ? 1e-5 : 1e-9;
        return fabs(a - b) <= epsilon;
    }
    return llround(a) == llround(b);
}

static bool RegionMatchesFilter(unsigned int userTag, vm_prot_t protection, MSRegionFilter filter) {
    const bool readable = (protection & VM_PROT_READ) != 0;
    if (!readable) return false;

    switch (filter) {
        case MSRegionFilterAll:
            return (protection & VM_PROT_WRITE) != 0;
        case MSRegionFilterHeap:
            return userTag == VM_MEMORY_MALLOC ||
                   userTag == VM_MEMORY_MALLOC_SMALL ||
                   userTag == VM_MEMORY_MALLOC_LARGE ||
                   userTag == VM_MEMORY_MALLOC_HUGE;
        case MSRegionFilterStack:
            return userTag == VM_MEMORY_STACK;
        case MSRegionFilterAnonymous:
            return userTag == 0;
        case MSRegionFilterShared:
            return userTag == VM_MEMORY_SHARED_PMAP;
        case MSRegionFilterExecutable:
            return (protection & VM_PROT_EXECUTE) != 0;
    }
    return true;
}

@implementation MemScanBridge

+ (BOOL)isMemoryAccessAvailable {
    task_t selfTask = MACH_PORT_NULL;
    kern_return_t kr = task_for_pid(mach_task_self(), getpid(), &selfTask);
    if (kr != KERN_SUCCESS || selfTask == MACH_PORT_NULL) {
        return NO;
    }
    mach_port_deallocate(mach_task_self(), selfTask);
    return YES;
}

+ (NSString *)memoryAccessErrorMessage {
    return @"无法访问进程内存。请确保设备已越狱，并授予 task_for_pid 权限。";
}

+ (NSInteger)listProcesses:(MSProcessInfo *)buffer capacity:(NSInteger)capacity {
    if (!buffer || capacity <= 0) return 0;

    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t length = 0;
    if (sysctl(mib, 4, nullptr, &length, nullptr, 0) != 0 || length == 0) {
        return 0;
    }

    std::vector<uint8_t> procBuffer(length);
    if (sysctl(mib, 4, procBuffer.data(), &length, nullptr, 0) != 0) {
        return 0;
    }

    const struct kinfo_proc *procs = reinterpret_cast<const struct kinfo_proc *>(procBuffer.data());
    const size_t count = length / sizeof(struct kinfo_proc);
    NSInteger written = 0;

    for (size_t i = 0; i < count && written < capacity; i++) {
        const struct kinfo_proc &proc = procs[i];
        const pid_t pid = proc.kp_proc.p_pid;
        if (pid <= 0) continue;

        const char *name = proc.kp_proc.p_comm;
        if (!name || name[0] == '\0') continue;

        MSProcessInfo info = {};
        info.pid = pid;
        strncpy(info.name, name, sizeof(info.name) - 1);
        strncpy(info.bundle_id, "", sizeof(info.bundle_id) - 1);
        buffer[written++] = info;
    }

    return written;
}

+ (BOOL)attachToPID:(int32_t)pid error:(NSError **)error {
    [self detach];

    kern_return_t kr = task_for_pid(mach_task_self(), pid, &g_task);
    if (kr != KERN_SUCCESS || g_task == MACH_PORT_NULL) {
        if (error) {
            *error = MSError([NSString stringWithFormat:@"task_for_pid 失败 (pid=%d, kr=%d)", pid, kr], kr);
        }
        return NO;
    }

    g_results.clear();
    return YES;
}

+ (void)detach {
    if (g_task != MACH_PORT_NULL) {
        mach_port_deallocate(mach_task_self(), g_task);
        g_task = MACH_PORT_NULL;
    }
    g_results.clear();
}

+ (NSInteger)firstScanWithValue:(double)value
                      dataType:(MSDataType)dataType
                  regionFilter:(MSRegionFilter)regionFilter
                         matches:(MSScanMatch *)buffer
                        capacity:(NSInteger)capacity
                            error:(NSError **)error {
    if (g_task == MACH_PORT_NULL) {
        if (error) *error = MSError(@"未附加到目标进程", 1);
        return 0;
    }

    g_currentDataType = dataType;
    g_results.clear();

    const int typeSize = DataTypeSize(dataType);
    mach_vm_address_t address = 0;
    mach_vm_size_t regionSize = 0;
    natural_t depth = 0;

    while (true) {
        struct mach_vm_range range = {};
        struct vm_region_submap_info_64 info = {};
        mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;
        kern_return_t kr = mach_vm_region_recurse(g_task, &address, &regionSize, &depth,
                                                  (vm_region_recurse_info_t)&info, &count);

        if (kr == KERN_INVALID_ADDRESS) break;
        if (kr != KERN_SUCCESS) break;

        const bool isSubmap = info.is_submap;
        if (isSubmap) {
            depth++;
            continue;
        }

        if (!RegionMatchesFilter(info.user_tag, info.protection, regionFilter)) {
            address += regionSize;
            continue;
        }

        if (regionSize < (mach_vm_size_t)typeSize) {
            address += regionSize;
            continue;
        }

        std::vector<uint8_t> chunk(regionSize);
        mach_vm_size_t bytesRead = 0;
        kr = mach_vm_read_overwrite(g_task, address, regionSize, (mach_vm_address_t)chunk.data(), &bytesRead);
        if (kr != KERN_SUCCESS || bytesRead < (mach_vm_size_t)typeSize) {
            address += regionSize;
            continue;
        }

        const size_t limit = bytesRead - typeSize;
        for (size_t offset = 0; offset <= limit; offset += typeSize) {
            const double current = ReadTypedValue(chunk.data() + offset, dataType);
            if (ValuesEqual(current, value, dataType)) {
                MSScanMatch match = {};
                match.address = address + offset;
                match.value = current;
                g_results.push_back(match);
            }
        }

        address += regionSize;
    }

    return [self copyResultsTo:buffer capacity:capacity];
}

+ (NSInteger)refineScanWithValue:(double)value
                            mode:(MSRefineMode)mode
                        dataType:(MSDataType)dataType
                         matches:(MSScanMatch *)buffer
                        capacity:(NSInteger)capacity
                            error:(NSError **)error {
    if (g_task == MACH_PORT_NULL) {
        if (error) *error = MSError(@"未附加到目标进程", 1);
        return 0;
    }
    if (g_results.empty()) {
        if (error) *error = MSError(@"没有可精搜的结果，请先进行首次搜索", 2);
        return 0;
    }

    const int typeSize = DataTypeSize(dataType);
    std::vector<MSScanMatch> refined;
    refined.reserve(g_results.size());

    for (const MSScanMatch &old : g_results) {
        uint8_t bytes[8] = {0};
        mach_vm_size_t bytesRead = 0;
        kern_return_t kr = mach_vm_read_overwrite(g_task, old.address, typeSize,
                                                  (mach_vm_address_t)bytes, &bytesRead);
        if (kr != KERN_SUCCESS || bytesRead < (mach_vm_size_t)typeSize) {
            continue;
        }

        const double current = ReadTypedValue(bytes, dataType);
        bool keep = false;

        switch (mode) {
            case MSRefineModeExact:
                keep = ValuesEqual(current, value, dataType);
                break;
            case MSRefineModeIncreased:
                keep = current > old.value + (IsFloating(dataType) ? 1e-9 : 0.5);
                break;
            case MSRefineModeDecreased:
                keep = current < old.value - (IsFloating(dataType) ? 1e-9 : 0.5);
                break;
            case MSRefineModeUnchanged:
                keep = ValuesEqual(current, old.value, dataType);
                break;
            case MSRefineModeChanged:
                keep = !ValuesEqual(current, old.value, dataType);
                break;
        }

        if (keep) {
            MSScanMatch match = {};
            match.address = old.address;
            match.value = current;
            refined.push_back(match);
        }
    }

    g_results = std::move(refined);
    g_currentDataType = dataType;
    return [self copyResultsTo:buffer capacity:capacity];
}

+ (BOOL)writeValue:(double)value
          dataType:(MSDataType)dataType
           address:(uint64_t)address
             error:(NSError **)error {
    if (g_task == MACH_PORT_NULL) {
        if (error) *error = MSError(@"未附加到目标进程", 1);
        return NO;
    }

    const int typeSize = DataTypeSize(dataType);
    uint8_t bytes[8] = {0};
    if (!WriteTypedValue(bytes, dataType, value)) {
        if (error) *error = MSError(@"无效的数据类型", 3);
        return NO;
    }

    kern_return_t kr = mach_vm_write(g_task, address, (vm_offset_t)bytes, (mach_msg_type_number_t)typeSize);
    if (kr != KERN_SUCCESS) {
        if (error) {
            *error = MSError([NSString stringWithFormat:@"写入内存失败 (kr=%d)", kr], kr);
        }
        return NO;
    }

    for (auto &item : g_results) {
        if (item.address == address) {
            item.value = value;
            break;
        }
    }
    return YES;
}

+ (BOOL)readValue:(double *)outValue
         dataType:(MSDataType)dataType
          address:(uint64_t)address
            error:(NSError **)error {
    if (g_task == MACH_PORT_NULL) {
        if (error) *error = MSError(@"未附加到目标进程", 1);
        return NO;
    }
    if (!outValue) return NO;

    const int typeSize = DataTypeSize(dataType);
    uint8_t bytes[8] = {0};
    mach_vm_size_t bytesRead = 0;
    kern_return_t kr = mach_vm_read_overwrite(g_task, address, typeSize,
                                              (mach_vm_address_t)bytes, &bytesRead);
    if (kr != KERN_SUCCESS || bytesRead < (mach_vm_size_t)typeSize) {
        if (error) *error = MSError(@"读取内存失败", 4);
        return NO;
    }

    *outValue = ReadTypedValue(bytes, dataType);
    return YES;
}

+ (NSInteger)storedResultCount {
    return (NSInteger)g_results.size();
}

+ (void)clearResults {
    g_results.clear();
}

+ (NSInteger)copyResultsTo:(MSScanMatch *)buffer capacity:(NSInteger)capacity {
    if (!buffer || capacity <= 0) return (NSInteger)g_results.size();

    const NSInteger count = MIN((NSInteger)g_results.size(), capacity);
    for (NSInteger i = 0; i < count; i++) {
        buffer[i] = g_results[(size_t)i];
    }
    return count;
}

@end
