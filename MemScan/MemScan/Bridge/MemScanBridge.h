#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    int32_t pid;
    char name[256];
    char bundle_id[256];
} MSProcessInfo;

typedef struct {
    uint64_t address;
    double value;
} MSScanMatch;

typedef NS_ENUM(NSInteger, MSDataType) {
    MSDataTypeInt8 = 0,
    MSDataTypeInt16,
    MSDataTypeInt32,
    MSDataTypeInt64,
    MSDataTypeUInt8,
    MSDataTypeUInt16,
    MSDataTypeUInt32,
    MSDataTypeUInt64,
    MSDataTypeFloat,
    MSDataTypeDouble
};

typedef NS_ENUM(NSInteger, MSRegionFilter) {
    MSRegionFilterAll = 0,
    MSRegionFilterHeap,
    MSRegionFilterStack,
    MSRegionFilterAnonymous,
    MSRegionFilterShared,
    MSRegionFilterExecutable
};

typedef NS_ENUM(NSInteger, MSRefineMode) {
    MSRefineModeExact = 0,
    MSRefineModeIncreased,
    MSRefineModeDecreased,
    MSRefineModeUnchanged,
    MSRefineModeChanged
};

@interface MemScanBridge : NSObject

+ (BOOL)isMemoryAccessAvailable;
+ (NSString *)memoryAccessErrorMessage;

+ (NSArray<NSDictionary *> *)fetchProcessList;

+ (NSInteger)runFirstScanWithValue:(double)value
                          dataType:(MSDataType)dataType
                      regionFilter:(MSRegionFilter)regionFilter
                             error:(NSError **)error;

+ (NSInteger)runRefineScanWithValue:(double)value
                               mode:(MSRefineMode)mode
                           dataType:(MSDataType)dataType
                              error:(NSError **)error;

+ (NSArray<NSDictionary *> *)fetchResultsWithLimit:(NSInteger)limit;

+ (NSInteger)listProcesses:(MSProcessInfo *)buffer capacity:(NSInteger)capacity;
+ (BOOL)attachToPID:(int32_t)pid error:(NSError **)error;
+ (void)detach;

+ (NSInteger)firstScanWithValue:(double)value
                      dataType:(MSDataType)dataType
                  regionFilter:(MSRegionFilter)regionFilter
                         matches:(MSScanMatch *)buffer
                        capacity:(NSInteger)capacity
                            error:(NSError **)error;

+ (NSInteger)refineScanWithValue:(double)value
                            mode:(MSRefineMode)mode
                        dataType:(MSDataType)dataType
                         matches:(MSScanMatch *)buffer
                        capacity:(NSInteger)capacity
                            error:(NSError **)error;

+ (BOOL)writeValue:(double)value
          dataType:(MSDataType)dataType
           address:(uint64_t)address
             error:(NSError **)error;

+ (BOOL)readValue:(double *)outValue
         dataType:(MSDataType)dataType
          address:(uint64_t)address
            error:(NSError **)error;

+ (NSInteger)storedResultCount;
+ (NSInteger)copyResultsTo:(MSScanMatch *)buffer capacity:(NSInteger)capacity;
+ (void)clearResults;

@end

NS_ASSUME_NONNULL_END
