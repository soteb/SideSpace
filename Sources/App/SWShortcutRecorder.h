#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
NSString *SWShortcutDescription(UInt32 keyCode,UInt32 modifiers);
@interface SWShortcutRecorder : NSView
@property(nonatomic) UInt32 keyCode;
@property(nonatomic) UInt32 modifiers;
@property(nonatomic,readonly) BOOL hasValidShortcut;
@end
