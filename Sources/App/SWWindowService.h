#import <AppKit/AppKit.h>
typedef void (^SWStatusHandler)(NSString *message,BOOL isError);
@interface SWWindowService : NSObject
@property(nonatomic) NSInteger leftMargin;
@property(nonatomic,copy) NSString *dockDisplayUUID;
@property(nonatomic,readonly) BOOL busy;
@property(nonatomic,copy) SWStatusHandler statusHandler;
- (void)performActionWithFrontmost:(NSRunningApplication *)frontmost;
- (void)cancelPendingAction;
@end
