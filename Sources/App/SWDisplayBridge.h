#import <AppKit/AppKit.h>
#import "SWLayout.h"
#define SW_MAX_DISPLAYS 32
@interface SWDisplaySnapshot : NSObject {
@public
    SWDisplay displays[SW_MAX_DISPLAYS];
    size_t count;
}
@property(copy) NSArray<NSString *> *uuids;
@property(copy) NSArray<NSString *> *names;
+ (instancetype)capture;
- (uint32_t)identifierForUUID:(NSString *)uuid;
@end
