#import "MemScanBridge.h"

@import Darwin;

static task_t g_task = MACH_PORT_NULL;
static MSScanMatch *g_results = NULL;
static size_t g_resultCount = 0;
static size_t g_resultCapacity = 0;

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

static BOOL IsFloating(MSDataType type) {
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

static BOOL WriteTypedValue(uint8_t *bytes, MSDataType type, double value) {
    switch (type) {
        case MSDataTypeInt8: *(int8_t *)bytes = (int8_t)llround(value); return YES;
        case MSDataTypeInt16: *(int16_t *)bytes = (int16_t)llround(value); return YES;
        case MSDataTypeInt32: *(int32_t *)bytes = (int32_t)llround(value); return YES;
        case MSDataTypeInt64: *(int64_t *)bytes = (int64_t)llround(value); return YES;
        case MSDataTypeUInt8: *(uint8_t *)bytes = (uint8_t)llround(fmax(0, value)); return YES;
        case MSDataTypeUInt16: *(uint16_t *)bytes = (uint16_t)llround(fmax(0, value)); return YES;
        case MSDataTypeUInt32: *(uint32_t *)bytes = (uint32_t)llround(fmax(0, value)); return YES;
        case MSDataTypeUInt64: *(uint64_t *)bytes = (uint64_t)llround(fmax(0, value)); return YES;
        case MSDataTypeFloat: *(float *)bytes = (float)value; return YES;
        case MSDataTypeDouble: *(double *)bytes = value; return YES;
    }
    return NO;
}

static BOOL ValuesEqual(double a, double b, MSDataType type) {
    if (IsFloating(type)) {
        double epsilon = (type == MSDataTypeFloat) ? 1e-5 : 1e-9;
        return fabs(a - b) <= epsilon;
    }
    return llround(a) == llround(b);
}

static BOOL RegionMatchesFilter(unsigned int userTag, vm_prot_t protection, MSRegionFilter filter) {
    BOOL readable = (protection & VM_PROT_READ) != 0;
    if (!readable) return NO;

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
    return YES;
}

static void ResultsClear(void) {
    free(g_results);
    g_results = NULL;
    g_resultCount = 0;
    g_resultCapacity = 0;
}

static void ResultsAppend(MSScanMatch match) {
    if (g_resultCount >= g_resultCapacity) {
        size_t newCapacity = g_resultCapacity == 0 ? 256 : g_resultCapacity * 2;
        MSScanMatch *newBuffer = (MSScanMatch *)realloc(g_results, newCapacity * sizeof(MSScanMatch));
        if (!newBuffer) return;
        g_results = newBuffer;
        g_resultCapacity = newCapacity;
    }
    g_results[g_resultCount++] = match;
}

static void ResultsReplace(MSScanMatch *items, size_t count) {
    free(g_results);
    g_results = items;
    g_resultCount = count;
    g_resultCapacity = count;
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
    if (sysctl(mib, 4, NULL, &length, NULL, 0) != 0 || length == 0) {
        return 0;
    }

    uint8_t *procBuffer = (uint8_t *)malloc(length);
    if (!procBuffer) return 0;

    if (sysctl(mib, 4, procBuffer, &length, NULL, 0) != 0) {
        free(procBuffer);
        return 0;
    }

    const struct kinfo_proc *procs = (const struct kinfo_proc *)procBuffer;
    size_t count = length / sizeof(struct kinfo_proc);
    NSInteger written = 0;

    for (size_t i = 0; i < count && written < capacity; i++) {
        const struct kinfo_proc *proc = &procs[i];
        pid_t pid = proc->kp_proc.p_pid;
        if (pid <= 0) continue;

        const char *name = proc->kp_proc.p_comm;
        if (!name || name[0] == '\0') continue;

        MSProcessInfo info;
        memset(&info, 0, sizeof(info));
        info.pid = pid;
        strncpy(info.name, name, sizeof(info.name) - 1);
        strncpy(info.bundle_id, "", sizeof(info.bundle_id) - 1);
        buffer[written++] = info;
    }

    free(procBuffer);
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

    ResultsClear();
    return YES;
}

+ (void)detach {
    if (g_task != MACH_PORT_NULL) {
        mach_port_deallocate(mach_task_self(), g_task);
        g_task = MACH_PORT_NULL;
    }
    ResultsClear();
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

    ResultsClear();

    int typeSize = DataTypeSize(dataType);
    mach_vm_address_t address = 0;
    mach_vm_size_t regionSize = 0;
    natural_t depth = 0;

    while (1) {
        struct vm_region_submap_info_64 info;
        memset(&info, 0, sizeof(info));
        mach_msg_type_number_t infoCount = VM_REGION_SUBMAP_INFO_COUNT_64;
        kern_return_t kr = mach_vm_region_recurse(g_task, &address, &regionSize, &depth,
                                                  (vm_region_recurse_info_t)&info, &infoCount);

        if (kr == KERN_INVALID_ADDRESS) break;
        if (kr != KERN_SUCCESS) break;

        if (info.is_submap) {
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

        uint8_t *chunk = (uint8_t *)malloc((size_t)regionSize);
        if (!chunk) {
            address += regionSize;
            continue;
        }

        mach_vm_size_t bytesRead = 0;
        kr = mach_vm_read_overwrite(g_task, address, regionSize, (mach_vm_address_t)chunk, &bytesRead);
        if (kr != KERN_SUCCESS || bytesRead < (mach_vm_size_t)typeSize) {
            free(chunk);
            address += regionSize;
            continue;
        }

        size_t limit = (size_t)bytesRead - (size_t)typeSize;
        for (size_t offset = 0; offset <= limit; offset += (size_t)typeSize) {
            double current = ReadTypedValue(chunk + offset, dataType);
            if (ValuesEqual(current, value, dataType)) {
                MSScanMatch match;
                match.address = address + offset;
                match.value = current;
                ResultsAppend(match);
            }
        }

        free(chunk);
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
    if (g_resultCount == 0) {
        if (error) *error = MSError(@"没有可精搜的结果，请先进行首次搜索", 2);
        return 0;
    }

    int typeSize = DataTypeSize(dataType);
    size_t refinedCapacity = g_resultCount;
    MSScanMatch *refined = (MSScanMatch *)malloc(refinedCapacity * sizeof(MSScanMatch));
    if (!refined) {
        if (error) *error = MSError(@"内存不足", 5);
        return 0;
    }

    size_t refinedCount = 0;
    for (size_t i = 0; i < g_resultCount; i++) {
        MSScanMatch old = g_results[i];
        uint8_t bytes[8];
        memset(bytes, 0, sizeof(bytes));
        mach_vm_size_t bytesRead = 0;
        kern_return_t kr = mach_vm_read_overwrite(g_task, old.address, (mach_vm_size_t)typeSize,
                                                  (mach_vm_address_t)bytes, &bytesRead);
        if (kr != KERN_SUCCESS || bytesRead < (mach_vm_size_t)typeSize) {
            continue;
        }

        double current = ReadTypedValue(bytes, dataType);
        BOOL keep = NO;

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
            refined[refinedCount].address = old.address;
            refined[refinedCount].value = current;
            refinedCount++;
        }
    }

    ResultsReplace(refined, refinedCount);
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

    int typeSize = DataTypeSize(dataType);
    uint8_t bytes[8];
    memset(bytes, 0, sizeof(bytes));
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

    for (size_t i = 0; i < g_resultCount; i++) {
        if (g_results[i].address == address) {
            g_results[i].value = value;
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

    int typeSize = DataTypeSize(dataType);
    uint8_t bytes[8];
    memset(bytes, 0, sizeof(bytes));
    mach_vm_size_t bytesRead = 0;
    kern_return_t kr = mach_vm_read_overwrite(g_task, address, (mach_vm_size_t)typeSize,
                                              (mach_vm_address_t)bytes, &bytesRead);
    if (kr != KERN_SUCCESS || bytesRead < (mach_vm_size_t)typeSize) {
        if (error) *error = MSError(@"读取内存失败", 4);
        return NO;
    }

    *outValue = ReadTypedValue(bytes, dataType);
    return YES;
}

+ (NSInteger)storedResultCount {
    return (NSInteger)g_resultCount;
}

+ (void)clearResults {
    ResultsClear();
}

+ (NSInteger)copyResultsTo:(MSScanMatch *)buffer capacity:(NSInteger)capacity {
    if (!buffer || capacity <= 0) return (NSInteger)g_resultCount;

    NSInteger count = MIN((NSInteger)g_resultCount, capacity);
    for (NSInteger i = 0; i < count; i++) {
        buffer[i] = g_results[(size_t)i];
    }
    return count;
}

+ (NSArray *)fetchProcessList {
    NSInteger capacity = 2048;
    MSProcessInfo *buffer = (MSProcessInfo *)calloc((size_t)capacity, sizeof(MSProcessInfo));
    if (!buffer) return @[];

    NSInteger count = [self listProcesses:buffer capacity:capacity];
    if (count <= 0) {
        free(buffer);
        return @[];
    }

    NSMutableArray *results = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
    for (NSInteger i = 0; i < count; i++) {
        MSProcessInfo info = buffer[i];
        NSString *name = [NSString stringWithUTF8String:info.name] ?: @"";
        NSString *bundleID = [NSString stringWithUTF8String:info.bundle_id] ?: @"";
        [results addObject:@{
            @"pid": @(info.pid),
            @"name": name,
            @"bundleID": bundleID
        }];
    }

    free(buffer);
    return results;
}

+ (NSInteger)runFirstScanWithValue:(double)value
                          dataType:(MSDataType)dataType
                      regionFilter:(MSRegionFilter)regionFilter
                             error:(NSError **)error {
    return [self firstScanWithValue:value
                           dataType:dataType
                       regionFilter:regionFilter
                            matches:NULL
                           capacity:0
                               error:error];
}

+ (NSInteger)runRefineScanWithValue:(double)value
                               mode:(MSRefineMode)mode
                           dataType:(MSDataType)dataType
                              error:(NSError **)error {
    return [self refineScanWithValue:value
                                mode:mode
                            dataType:dataType
                             matches:NULL
                            capacity:0
                                error:error];
}

+ (NSArray *)fetchResultsWithLimit:(NSInteger)limit {
    if (limit <= 0 || g_resultCount == 0) return @[];

    NSInteger count = MIN((NSInteger)g_resultCount, limit);
    NSMutableArray *results = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
    for (NSInteger i = 0; i < count; i++) {
        MSScanMatch match = g_results[(size_t)i];
        [results addObject:@{
            @"address": @(match.address),
            @"value": @(match.value)
        }];
    }
    return results;
}

@end
