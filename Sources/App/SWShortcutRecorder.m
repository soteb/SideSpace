#import "SWShortcutRecorder.h"
#import "SWPreferences.h"
#import "SWLocalization.h"
static NSString *keyName(UInt32 code) {
    switch(code) {
        case kVK_RightArrow:return @"→"; case kVK_LeftArrow:return @"←";
        case kVK_UpArrow:return @"↑"; case kVK_DownArrow:return @"↓";
        case kVK_Return:return @"↩"; case kVK_ANSI_KeypadEnter:return @"⌤";
        case kVK_Space:return SWText(@"key.space"); case kVK_Tab:return @"⇥";
        case kVK_Delete:return @"⌫"; case kVK_ForwardDelete:return @"⌦";
        case kVK_Escape:return @"⎋"; case kVK_Home:return @"↖";
        case kVK_End:return @"↘"; case kVK_PageUp:return @"⇞";
        case kVK_PageDown:return @"⇟";
        case kVK_F1:return @"F1"; case kVK_F2:return @"F2";
        case kVK_F3:return @"F3"; case kVK_F4:return @"F4";
        case kVK_F5:return @"F5"; case kVK_F6:return @"F6";
        case kVK_F7:return @"F7"; case kVK_F8:return @"F8";
        case kVK_F9:return @"F9"; case kVK_F10:return @"F10";
        case kVK_F11:return @"F11"; case kVK_F12:return @"F12";
        default:break;
    }
    TISInputSourceRef source=TISCopyCurrentASCIICapableKeyboardLayoutInputSource();
    NSString *result=nil;
    if(source) {
        CFDataRef data=TISGetInputSourceProperty(source,kTISPropertyUnicodeKeyLayoutData);
        if(data) {
            const UCKeyboardLayout *layout=(const UCKeyboardLayout *)CFDataGetBytePtr(data);
            UInt32 dead=0; UniChar text[8]={0}; UniCharCount length=0;
            if(UCKeyTranslate(layout,(UInt16)code,kUCKeyActionDisplay,0,LMGetKbdType(),
                kUCKeyTranslateNoDeadKeysMask,&dead,8,&length,text)==noErr && length)
                result=[[NSString stringWithCharacters:text length:length] uppercaseString];
        }
        CFRelease(source);
    }
    return result.length?result:SWFormat(@"key.unknown",(unsigned)code);
}
NSString *SWShortcutDescription(UInt32 key,UInt32 modifiers) {
    NSMutableString *text=[NSMutableString string];
    if(modifiers&controlKey) [text appendString:@"⌃"];
    if(modifiers&optionKey) [text appendString:@"⌥"];
    if(modifiers&shiftKey) [text appendString:@"⇧"];
    if(modifiers&cmdKey) [text appendString:@"⌘"];
    [text appendString:keyName(key)];
    return text;
}
@implementation SWShortcutRecorder {
    NSTextField *_value;
    NSTextField *_hint;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if((self=[super initWithFrame:frame])) {
        _value=[NSTextField labelWithString:@""];
        _value.frame=NSMakeRect(0,46,frame.size.width,32);
        _value.font=[NSFont systemFontOfSize:24 weight:NSFontWeightMedium];
        _value.alignment=NSTextAlignmentCenter;
        [self addSubview:_value];
        _hint=[NSTextField wrappingLabelWithString:SWText(@"recorder.hint")];
        _hint.frame=NSMakeRect(0,0,frame.size.width,40);
        _hint.alignment=NSTextAlignmentCenter;
        _hint.font=[NSFont systemFontOfSize:12];
        _hint.textColor=NSColor.secondaryLabelColor;
        [self addSubview:_hint];
        SWSettings defaults=SWSettingsDefaults();
        self.keyCode=defaults.keyCode;
        self.modifiers=defaults.modifiers;
        self.accessibilityLabel=SWText(@"recorder.access");
    }
    return self;
}
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)becomeFirstResponder { [self refresh]; return YES; }
- (void)mouseDown:(NSEvent *)event { (void)event; [self.window makeFirstResponder:self]; }
- (BOOL)hasValidShortcut { return (self.modifiers&(cmdKey|controlKey|optionKey))!=0 && self.keyCode<=127; }
- (void)setKeyCode:(UInt32)keyCode { _keyCode=keyCode; [self refresh]; }
- (void)setModifiers:(UInt32)modifiers { _modifiers=modifiers; [self refresh]; }
- (void)refresh { _value.stringValue=SWShortcutDescription(self.keyCode,self.modifiers); }
- (BOOL)recordEvent:(NSEvent *)event {
    if(event.isARepeat) return YES;
    NSEventModifierFlags flags=event.modifierFlags&NSEventModifierFlagDeviceIndependentFlagsMask;
    UInt32 mods=0;
    if(flags&NSEventModifierFlagControl) mods|=controlKey;
    if(flags&NSEventModifierFlagOption) mods|=optionKey;
    if(flags&NSEventModifierFlagCommand) mods|=cmdKey;
    if(flags&NSEventModifierFlagShift) mods|=shiftKey;
    if(!mods && (event.keyCode==kVK_Escape || event.keyCode==kVK_Return || event.keyCode==kVK_Tab))
        return NO;
    if(!(mods&(cmdKey|controlKey|optionKey))) {
        _hint.stringValue=SWText(@"recorder.needMods");
        return YES;
    }
    BOOL commonSystemKey=mods==cmdKey &&
        (event.keyCode==kVK_ANSI_Q || event.keyCode==kVK_ANSI_W || event.keyCode==kVK_ANSI_M ||
         event.keyCode==kVK_Tab || event.keyCode==kVK_Space);
    if(commonSystemKey) {
        _hint.stringValue=SWText(@"recorder.reserved"); return YES;
    }
    self.keyCode=event.keyCode;
    self.modifiers=mods;
    _hint.stringValue=SWText(@"recorder.captured");
    return YES;
}
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if(self.window.firstResponder==self && [self recordEvent:event]) return YES;
    return [super performKeyEquivalent:event];
}
- (void)keyDown:(NSEvent *)event {
    if(![self recordEvent:event]) [super keyDown:event];
}
@end
