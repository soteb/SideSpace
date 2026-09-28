#import <AppKit/AppKit.h>
#import "SWAppDelegate.h"
int main(int argc,const char *argv[]) {
    (void)argc; (void)argv;
    @autoreleasepool {
        NSApplication *app=NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        __attribute__((objc_precise_lifetime)) SWAppDelegate *delegate=[SWAppDelegate new];
        app.delegate=delegate;
        [app run];
        (void)delegate; // Keep the delegate alive for the entire run loop.
    }
    return 0;
}
