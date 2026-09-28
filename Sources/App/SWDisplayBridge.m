#import "SWDisplayBridge.h"
#import <CoreGraphics/CoreGraphics.h>
@implementation SWDisplaySnapshot
+ (instancetype)capture {
    NSAssert(NSThread.isMainThread,@"NSScreen access must be on main thread");
    NSArray<NSScreen *> *screens=NSScreen.screens;
    if (!screens.count || screens.count>SW_MAX_DISPLAYS) return nil;
    SWDisplaySnapshot *snapshot=[SWDisplaySnapshot new];
    NSMutableArray<NSString *> *uuids=[NSMutableArray arrayWithCapacity:screens.count];
    /* The first NSScreen establishes AppKit's global origin; NSScreen.mainScreen
       instead follows the key window and must NOT be used for conversion. */
    NSMutableArray<NSString *> *names=[NSMutableArray arrayWithCapacity:screens.count];
    double top=NSMaxY(screens.firstObject.frame);
    for (NSScreen *screen in screens) {
        NSNumber *number=screen.deviceDescription[@"NSScreenNumber"];
        if(!number) continue;
        CGDirectDisplayID identifier=number.unsignedIntValue;
        NSRect f=screen.frame,v=screen.visibleFrame;
        SWDisplay display={identifier,CGDisplayIsBuiltin(identifier)!=0,
            {NSMinX(f),top-NSMaxY(f),NSWidth(f),NSHeight(f)},
            {NSMinX(v),top-NSMaxY(v),NSWidth(v),NSHeight(v)}};
        if(!SWRectValid(display.frame) || !SWRectValid(display.visibleFrame)) continue;
        snapshot->displays[snapshot->count++]=display;
        CFUUIDRef uuid=CGDisplayCreateUUIDFromDisplayID(identifier);
        NSString *string=uuid?CFBridgingRelease(CFUUIDCreateString(NULL,uuid)):@"";
        if(uuid) CFRelease(uuid);
        [uuids addObject:string?:@""];
        [names addObject:screen.localizedName?:@""];
    }
    snapshot.uuids=uuids;
    snapshot.names=names;
    return snapshot->count?snapshot:nil;
}
- (uint32_t)identifierForUUID:(NSString *)uuid {
    if(!uuid.length) return 0;
    NSUInteger index=[self.uuids indexOfObject:uuid];
    return index!=NSNotFound && index<count?displays[index].identifier:0;
}
@end
