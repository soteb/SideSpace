#import <dispatch/dispatch.h>
#import "SWAppDelegate.h"
#import "SWWindowService.h"
#import "SWDisplayBridge.h"
#import "SWShortcutRecorder.h"
#import "SWHotKey.h"
#import "SWPreferences.h"
#import "SWLocalization.h"
#import <ApplicationServices/ApplicationServices.h>
#import <ServiceManagement/ServiceManagement.h>
#import <mach/mach.h>

static uint64_t SWPhysicalFootprint(BOOL *ok) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count=TASK_VM_INFO_COUNT;
    kern_return_t result=task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&info,&count);
    BOOL valid=result==KERN_SUCCESS && count>=TASK_VM_INFO_REV1_COUNT;
    if(ok) *ok=valid;
    return valid?info.phys_footprint:0;
}
static NSString *SWMegabytes(uint64_t bytes) {
    return [NSString stringWithFormat:@"%.1f MB",(double)bytes/(1024.0*1024.0)];
}

static void hotKeyCallback(void *context) {
    @autoreleasepool { [(__bridge SWAppDelegate *)context handleHotKey]; }
}

@implementation SWAppDelegate {
    NSStatusItem *_statusItem;
    NSMenuItem *_dockDisplayItem;
    NSMenu *_menu;
    NSMenuItem *_actionItem,*_marginItem,*_shortcutItem,*_permissionItem,*_loginItem,*_statusLine;
    NSMenuItem *_memoryCurrent,*_memoryAverage,*_memoryStartupItem;
    NSMenuItem *_brandItem,*_customMarginItem,*_customShortcutItem,*_recheckItem,*_diagnosticsItem,*_aboutItem,*_quitItem,*_languageItem;
    NSTimer *_memoryTimer;
    uint64_t _memorySum,_memoryLast,_startupBytes;
    uint32_t _memoryCount;
    BOOL _startupKnown;
    NSRunningApplication *_frontmostBeforeMenu;
    SWWindowService *_service;
    SWHotKey _hotKey;
    SWSettings _settings;
    NSString *_lastStatus;
    BOOL _lastStatusIsError;
    BOOL _editing;
    NSWindow *_permissionAlert;
}
- (NSMenuItem *)item:(NSString *)title action:(SEL)selector menu:(NSMenu *)menu {
    NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:title action:selector keyEquivalent:@""];
    item.target=self;
    [menu addItem:item];
    return item;
}
- (BOOL)resolveOtherInstances {
    NSString *identifier=NSBundle.mainBundle.bundleIdentifier;
    pid_t me=NSProcessInfo.processInfo.processIdentifier;
    NSMutableArray<NSRunningApplication *> *others=[NSMutableArray array];
    for(NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:identifier])
        if(app.processIdentifier!=me && !app.terminated) [others addObject:app];
    if(!others.count) return YES;
    [NSApp activate];
    NSAlert *alert=[NSAlert new];
    alert.messageText=SWText(@"alert.runningTitle");
    alert.informativeText=SWText(@"alert.runningBody");
    [alert addButtonWithTitle:SWText(@"alert.runningReplace")];
    [alert addButtonWithTitle:SWText(@"alert.cancel")];
    if([alert runModal]!=NSAlertFirstButtonReturn) return NO;
    for(NSRunningApplication *app in others) [app terminate];
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:3];
    for(NSRunningApplication *app in others)
        while(!app.terminated && deadline.timeIntervalSinceNow>0)
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    return YES;
}
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    (void)note;
    SWLoadLocalization();
    if(![self resolveOtherInstances]) { [NSApp terminate:nil]; return; }
    _settings=SWSettingsLoad();
    _service=[SWWindowService new];
    _service.leftMargin=_settings.leftMargin;
    __weak SWAppDelegate *weakSelf=self;
    _service.statusHandler=^(NSString *message,BOOL error) { [weakSelf setStatus:message error:error]; };
    [self createMenu];
    OSStatus error=SWHotKeyInit(&_hotKey,hotKeyCallback,(__bridge void *)self);
    _hotKey.keyCode=_settings.keyCode; _hotKey.modifiers=_settings.modifiers;
    if(error==noErr) error=SWHotKeyReplace(&_hotKey,_settings.keyCode,_settings.modifiers);
    if(error!=noErr) [self setStatus:SWFormat(@"status.hotkeyFail",(int)error) error:YES];
    else [self setStatus:AXIsProcessTrusted()?SWText(@"status.ready"):SWText(@"status.needPermission") error:!AXIsProcessTrusted()];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(screenConfigurationChanged:)
        name:NSApplicationDidChangeScreenParametersNotification object:nil];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(screenConfigurationChanged:)
        name:NSWorkspaceWillSleepNotification object:nil];
    [self captureStartupMemory];
    dispatch_async(dispatch_get_main_queue(),^{ [self offerAccessibilityIfNeeded]; });
}
- (void)createMenu {
    _menu=[[NSMenu alloc] initWithTitle:@"SideSpace"];
    _menu.autoenablesItems=NO;
    _menu.delegate=self;
    _brandItem=[self item:@"SideSpace" action:NULL menu:_menu]; _brandItem.enabled=NO;
    [_menu addItem:NSMenuItem.separatorItem];
    _actionItem=[self item:@"SideSpace" action:@selector(executeFromMenu:) menu:_menu];
    _dockDisplayItem=[self item:SWText(@"menu.dockDisplay") action:NULL menu:_menu];
    _dockDisplayItem.submenu=[NSMenu new];
    _dockDisplayItem.submenu.autoenablesItems=NO;
    _marginItem=[self item:@"SideSpace" action:NULL menu:_menu];
    NSMenu *margins=[[NSMenu alloc] initWithTitle:@"SideSpace"];
    margins.autoenablesItems=NO;
    for(NSNumber *number in @[@0,@30,@40,@50,@60,@80,@100,@120]) {
        NSMenuItem *item=[self item:[NSString stringWithFormat:@"%@ pt",number] action:@selector(selectMargin:) menu:margins];
        item.tag=number.integerValue;
    }
    [margins addItem:NSMenuItem.separatorItem];
    _customMarginItem=[self item:@"SideSpace" action:@selector(customMargin:) menu:margins];
    _marginItem.submenu=margins;
    _shortcutItem=[self item:@"SideSpace" action:NULL menu:_menu];
    NSMenu *shortcuts=[[NSMenu alloc] initWithTitle:@"SideSpace"];
    shortcuts.autoenablesItems=NO;
    for(int index=0; index<3; index++) {
        NSMenuItem *item=[self item:@"SideSpace" action:@selector(selectShortcut:) menu:shortcuts];
        item.tag=index;
    }
    [shortcuts addItem:NSMenuItem.separatorItem];
    _customShortcutItem=[self item:@"SideSpace" action:@selector(editShortcut:) menu:shortcuts];
    _shortcutItem.submenu=shortcuts;
    [_menu addItem:NSMenuItem.separatorItem];
    _loginItem=[self item:@"SideSpace" action:@selector(toggleLogin:) menu:_menu];
    _permissionItem=[self item:@"SideSpace" action:@selector(requestPermission:) menu:_menu];
    _recheckItem=[self item:@"SideSpace" action:@selector(recheck:) menu:_menu];
    [_menu addItem:NSMenuItem.separatorItem];
    _memoryCurrent=[self item:@"SideSpace" action:NULL menu:_menu]; _memoryCurrent.enabled=NO;
    _memoryAverage=[self item:@"SideSpace" action:NULL menu:_menu]; _memoryAverage.enabled=NO;
    _memoryStartupItem=[self item:@"SideSpace" action:NULL menu:_menu]; _memoryStartupItem.enabled=NO;
    _statusLine=[self item:@"SideSpace" action:NULL menu:_menu]; _statusLine.enabled=NO;
    _diagnosticsItem=[self item:@"SideSpace" action:@selector(showDiagnostics:) menu:_menu];
    _aboutItem=[self item:@"SideSpace" action:@selector(showAbout:) menu:_menu];
    _languageItem=[self item:@"SideSpace" action:NULL menu:_menu];
    NSMenu *languages=[[NSMenu alloc] initWithTitle:@"SideSpace"];
    languages.autoenablesItems=NO;
    NSMenuItem *follow=[self item:@"SideSpace" action:@selector(selectLanguage:) menu:languages];
    follow.representedObject=@"auto";
    for(NSString *code in SWLanguageCodes()) {
        NSMenuItem *item=[self item:SWLanguageEndonym(code) action:@selector(selectLanguage:) menu:languages];
        item.representedObject=code;
    }
    _languageItem.submenu=languages;
    [_menu addItem:NSMenuItem.separatorItem];
    _quitItem=[self item:@"SideSpace" action:@selector(quit:) menu:_menu];
    _statusItem=[NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    /* A shared default name is currently hidden in Control Center, which removes the icon. */
    _statusItem.autosaveName=@"SideSpace";
    _statusItem.visible=YES;
    NSString *iconPath=[NSBundle.mainBundle pathForResource:@"MenuBarIcon" ofType:@"pdf"];
    NSImage *image=iconPath?[[NSImage alloc] initWithContentsOfFile:iconPath]:nil;
    if(!image) image=[NSImage imageWithSystemSymbolName:@"rectangle.on.rectangle" accessibilityDescription:@"SideSpace"];
    if(image) {
        image.template=YES;
        image.size=NSMakeSize(18,16);
        _statusItem.button.image=image;
    } else _statusItem.button.title=@"↔";
    _statusItem.menu=_menu;
    [self applyInterfaceLanguage];
}
- (void)applyInterfaceLanguage {
    _menu.title=@"SideSpace";
    _brandItem.title=SWText(@"menu.brand");
    _marginItem.submenu.title=SWText(@"menu.margin");
    _customMarginItem.title=SWText(@"menu.custom");
    _shortcutItem.submenu.title=SWText(@"menu.shortcut");
    _customShortcutItem.title=SWText(@"menu.custom");
    _recheckItem.title=SWText(@"menu.recheck");
    _diagnosticsItem.title=SWText(@"menu.diagnostics");
    _aboutItem.title=SWText(@"menu.about");
    _quitItem.title=SWText(@"menu.quit");
    _languageItem.title=SWText(@"menu.language");
    _languageItem.submenu.title=SWText(@"menu.language");
    for(NSMenuItem *item in _languageItem.submenu.itemArray)
        if([item.representedObject isEqual:@"auto"]) item.title=SWText(@"menu.languageFollow");
    if(!_memoryTimer) {
        _memoryCurrent.title=SWText(@"menu.memoryCurrent");
        _memoryAverage.title=SWText(@"menu.memoryAverage");
    } else if(_memoryCount>0) {
        _memoryCurrent.title=SWFormat(@"menu.memoryCurrentFormat",SWMegabytes(_memoryLast));
        _memoryAverage.title=SWFormat(@"menu.memoryAverageFormat",SWMegabytes(_memorySum/_memoryCount));
    }
    [self refreshStartupMemoryTitle];
    [self refreshMenu];
    if(_lastStatus.length) _statusItem.button.toolTip=SWFormat(@"menu.tooltip",_lastStatus);
}
- (void)setStatus:(NSString *)text error:(BOOL)error {
    _lastStatus=[text copy]; _lastStatusIsError=error;
    _statusLine.title=text.length>120?[[text substringToIndex:120] stringByAppendingString:@"…"]:text;
    _statusItem.button.toolTip=SWFormat(@"menu.tooltip",text?:@"");
    _permissionItem.title=AXIsProcessTrusted()?SWText(@"menu.permissionOn"):SWText(@"menu.permissionOff");
}
- (void)refreshDockDisplays {
    NSMenu *menu=_dockDisplayItem.submenu;
    [menu removeAllItems];
    _dockDisplayItem.title=SWText(@"menu.dockDisplay");
    NSMenuItem *internal=[self item:SWText(@"menu.dockBuiltIn") action:@selector(selectDockDisplay:) menu:menu];
    internal.representedObject=@"";
    internal.state=_service.dockDisplayUUID.length?NSControlStateValueOff:NSControlStateValueOn;
    SWDisplaySnapshot *snapshot=[SWDisplaySnapshot capture];
    BOOL found=NO;
    if(snapshot) for(size_t i=0;i<snapshot->count;i++) {
        if(snapshot->displays[i].builtIn) continue;
        SWRect f=snapshot->displays[i].frame;
        NSString *uuid=snapshot.uuids[i];
        NSString *title=[NSString stringWithFormat:@"%@ · %.0f×%.0f pt · (%.0f, %.0f)",snapshot.names[i],f.width,f.height,f.x,f.y];
        NSMenuItem *item=[self item:title action:@selector(selectDockDisplay:) menu:menu];
        item.representedObject=uuid;
        item.enabled=uuid.length>0;
        BOOL selected=[uuid isEqualToString:_service.dockDisplayUUID];
        item.state=selected?NSControlStateValueOn:NSControlStateValueOff;
        found|=selected;
    }
    if(_service.dockDisplayUUID.length && !found) {
        NSMenuItem *missing=[self item:SWText(@"menu.dockDisconnected") action:NULL menu:menu];
        missing.enabled=NO;
        missing.state=NSControlStateValueOn;
    }
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *hint=[self item:SWText(@"menu.dockSingleHint") action:NULL menu:menu];
    hint.enabled=NO;
}
- (void)selectDockDisplay:(NSMenuItem *)sender {
    NSString *uuid=sender.representedObject;
    if(![uuid isKindOfClass:NSString.class]) return;
    _service.dockDisplayUUID=uuid.length?uuid:nil;
    BOOL saved=SWSaveDockDisplayUUID(uuid.length?(__bridge CFStringRef)uuid:NULL);
    [self setStatus:SWText(saved?@"status.dockSaved":@"status.dockUnsaved") error:!saved];
    [self refreshMenu];
}
- (void)refreshMenu {
    [self refreshDockDisplays];
    NSString *shortcut=SWShortcutDescription(_settings.keyCode,_settings.modifiers);
    _actionItem.title=SWFormat(@"menu.arrangeFormat",SWText(@"menu.arrange"),shortcut);
    _actionItem.enabled=!_service.busy && !_editing;
    _shortcutItem.title=SWFormat(@"menu.shortcutFormat",SWText(@"menu.shortcut"),shortcut);
    BOOL shortcutMatchesPreset=NO;
    for(NSMenuItem *item in _shortcutItem.submenu.itemArray) {
        if(item.action!=@selector(selectShortcut:)) continue;
        uint32_t key=0,mods=0;
        if(!SWSettingsShortcutPreset((int)item.tag,&key,&mods)) continue;
        NSString *role=item.tag==0?@"menu.roleDefault":item.tag==1?@"menu.roleSecond":@"menu.roleThird";
        item.title=[SWShortcutDescription(key,mods) stringByAppendingString:SWText(role)];
        BOOL selected=key==_settings.keyCode && mods==_settings.modifiers;
        item.state=selected?NSControlStateValueOn:NSControlStateValueOff;
        if(selected) shortcutMatchesPreset=YES;
    }
    for(NSMenuItem *item in _shortcutItem.submenu.itemArray)
        if(item.action==@selector(editShortcut:))
            item.state=shortcutMatchesPreset?NSControlStateValueOff:NSControlStateValueOn;
    _marginItem.title=SWFormat(@"menu.marginFormat",SWText(@"menu.margin"),_settings.leftMargin);
    for(NSMenuItem *item in _marginItem.submenu.itemArray)
        if(item.action==@selector(selectMargin:)) item.state=item.tag==_settings.leftMargin?NSControlStateValueOn:NSControlStateValueOff;
    _permissionItem.title=AXIsProcessTrusted()?SWText(@"menu.permissionOn"):SWText(@"menu.permissionOff");
    SMAppServiceStatus status=SMAppService.mainAppService.status;
    _loginItem.state=status==SMAppServiceStatusEnabled?NSControlStateValueOn:NSControlStateValueOff;
    _loginItem.title=status==SMAppServiceStatusRequiresApproval?SWText(@"menu.loginPending"):SWText(@"menu.login");
    NSString *selected=SWSelectedLanguage();
    for(NSMenuItem *item in _languageItem.submenu.itemArray)
        item.state=[item.representedObject isEqual:selected]?NSControlStateValueOn:NSControlStateValueOff;
}
- (void)stopMemoryTimer {
    [_memoryTimer invalidate];
    _memoryTimer=nil;
}
- (void)refreshStartupMemoryTitle {
    if(!_startupKnown) { _memoryStartupItem.title=SWText(@"menu.memoryStartup"); return; }
    _memoryStartupItem.title=_startupBytes?SWFormat(@"menu.memoryStartupFormat",SWMegabytes(_startupBytes)):SWText(@"menu.memoryStartupFail");
}
- (void)captureStartupMemory {
    BOOL ok=NO;
    _startupBytes=SWPhysicalFootprint(&ok);
    _startupKnown=YES;
    if(!ok) _startupBytes=0;
    [self refreshStartupMemoryTitle];
}
- (void)recordMenuSample {
    BOOL ok=NO;
    uint64_t bytes=SWPhysicalFootprint(&ok);
    if(!ok) { _memoryCurrent.title=SWText(@"menu.memoryCurrentFail"); return; }
    _memoryLast=bytes;
    _memorySum+=bytes;
    _memoryCount+=1;
    _memoryCurrent.title=SWFormat(@"menu.memoryCurrentFormat",SWMegabytes(bytes));
    _memoryAverage.title=SWFormat(@"menu.memoryAverageFormat",SWMegabytes(_memorySum/_memoryCount));
}
- (void)menuWillOpen:(NSMenu *)menu {
    if(menu!=_menu) return;
    _frontmostBeforeMenu=NSWorkspace.sharedWorkspace.frontmostApplication;
    [self refreshMenu];
    [self stopMemoryTimer];
    _memorySum=0;
    _memoryCount=0;
    [self recordMenuSample];
    _memoryTimer=[NSTimer timerWithTimeInterval:1 target:self selector:@selector(recordMenuSample) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:_memoryTimer forMode:NSRunLoopCommonModes];
}
- (void)menuDidClose:(NSMenu *)menu {
    if(menu!=_menu) return;
    [self stopMemoryTimer];
    _memorySum=0;
    _memoryCount=0;
}
- (void)handleHotKey {
    if(_editing) return;
    [_service performActionWithFrontmost:NSWorkspace.sharedWorkspace.frontmostApplication];
}
- (void)executeFromMenu:(id)sender {
    (void)sender;
    NSRunningApplication *front=_frontmostBeforeMenu?:NSWorkspace.sharedWorkspace.frontmostApplication;
    /* Let menu tracking unwind before moving another app's windows. */
    dispatch_async(dispatch_get_main_queue(),^{ [self->_service performActionWithFrontmost:front]; });
}
- (void)screenConfigurationChanged:(NSNotification *)notification {
    (void)notification;
    if(_service.busy) {
        [_service cancelPendingAction];
        [self setStatus:SWText(@"status.displayChanged") error:NO];
    }
}
- (void)alertTitle:(NSString *)title message:(NSString *)message {
    [NSApp activate];
    NSAlert *alert=[NSAlert new];
    alert.messageText=title; alert.informativeText=message;
    [alert addButtonWithTitle:SWText(@"alert.ok")];
    [alert runModal];
}
- (void)saveMargin:(NSInteger)margin {
    if(margin<0 || margin>500) return;
    [_service cancelPendingAction];
    _settings.leftMargin=(int)margin;
    _service.leftMargin=margin;
    BOOL saved=SWSettingsSave(_settings);
    [self refreshMenu];
    [self setStatus:saved?SWText(@"status.marginSaved"):SWText(@"status.marginUnsaved") error:!saved];
}
- (void)selectMargin:(NSMenuItem *)sender { [self saveMargin:sender.tag]; }
- (void)applyShortcutKey:(uint32_t)key modifiers:(uint32_t)mods {
    if(key==_settings.keyCode && mods==_settings.modifiers && _hotKey.hotKey) return;
    [_service cancelPendingAction];
    OSStatus result=SWHotKeyReplace(&_hotKey,key,mods);
    if(result!=noErr) {
        [self alertTitle:SWText(@"alert.hotkeyTitle") message:SWFormat(@"alert.hotkeyBody",(int)result)];
        return;
    }
    _settings.keyCode=key; _settings.modifiers=mods;
    BOOL saved=SWSettingsSave(_settings);
    [self refreshMenu];
    [self setStatus:saved?SWText(@"status.shortcutSaved"):SWText(@"status.shortcutUnsaved") error:!saved];
}
- (void)selectShortcut:(NSMenuItem *)sender {
    uint32_t key=0,mods=0;
    if(!SWSettingsShortcutPreset((int)sender.tag,&key,&mods)) return;
    dispatch_async(dispatch_get_main_queue(),^{ [self applyShortcutKey:key modifiers:mods]; });
}
- (void)customMargin:(id)sender {
    (void)sender;
    _editing=YES;
    [NSApp activate];
    NSAlert *alert=[NSAlert new];
    alert.messageText=SWText(@"alert.marginTitle");
    alert.informativeText=SWText(@"alert.marginBody");
    [alert addButtonWithTitle:SWText(@"alert.save")]; [alert addButtonWithTitle:SWText(@"alert.cancel")];
    NSTextField *field=[[NSTextField alloc] initWithFrame:NSMakeRect(0,0,260,24)];
    field.stringValue=[NSString stringWithFormat:@"%d",_settings.leftMargin];
    alert.accessoryView=field;
    alert.window.initialFirstResponder=field;
    while([alert runModal]==NSAlertFirstButtonReturn) {
        NSString *text=[field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSCharacterSet *notDigits=[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
        BOOL valid=text.length>0 && text.length<=3 && [text rangeOfCharacterFromSet:notDigits].location==NSNotFound && text.integerValue<=500;
        if(valid) { [self saveMargin:text.integerValue]; break; }
        [self alertTitle:SWText(@"alert.marginBadTitle") message:SWText(@"alert.marginBadBody")];
    }
    _editing=NO;
}
- (void)editShortcut:(id)sender {
    (void)sender;
    if(_editing) return;
    _editing=YES;
    [_service cancelPendingAction];
    SWHotKeySuspend(&_hotKey);
    [NSApp activate];
    NSAlert *alert=[NSAlert new];
    alert.messageText=SWText(@"alert.recordTitle");
    alert.informativeText=SWText(@"alert.recordBody");
    [alert addButtonWithTitle:SWText(@"alert.save")]; [alert addButtonWithTitle:SWText(@"alert.cancel")];
    [alert addButtonWithTitle:SWText(@"alert.restore")];
    SWShortcutRecorder *recorder=[[SWShortcutRecorder alloc] initWithFrame:NSMakeRect(0,0,350,90)];
    recorder.keyCode=_settings.keyCode; recorder.modifiers=_settings.modifiers;
    alert.accessoryView=recorder;
    alert.window.initialFirstResponder=recorder;
    BOOL registered=NO;
    for(;;) {
        [alert.window makeFirstResponder:recorder];
        NSModalResponse response=[alert runModal];
        if(response==NSAlertSecondButtonReturn) break;
        if(response==NSAlertThirdButtonReturn) {
            SWSettings defaults=SWSettingsDefaults();
            recorder.keyCode=defaults.keyCode; recorder.modifiers=defaults.modifiers;
            continue;
        }
        if(response!=NSAlertFirstButtonReturn) break;
        if(!recorder.hasValidShortcut) {
            [self alertTitle:SWText(@"alert.recordBadTitle") message:SWText(@"alert.recordBadBody")];
            continue;
        }
        OSStatus result=SWHotKeyReplace(&_hotKey,recorder.keyCode,recorder.modifiers);
        if(result!=noErr) {
            [self alertTitle:SWText(@"alert.hotkeyTitle") message:SWFormat(@"alert.hotkeyBody",(int)result)];
            continue;
        }
        registered=YES;
        _settings.keyCode=recorder.keyCode; _settings.modifiers=recorder.modifiers;
        BOOL saved=SWSettingsSave(_settings);
        [self setStatus:saved?SWText(@"status.shortcutNew"):SWText(@"status.shortcutNewUnsaved") error:!saved];
        break;
    }
    if(!registered) {
        OSStatus result=SWHotKeyResume(&_hotKey);
        if(result!=noErr) [self setStatus:SWText(@"status.shortcutRestoreFail") error:YES];
    }
    _editing=NO;
    [self refreshMenu];
}
- (BOOL)accessibilityTrusted {
    NSDictionary *options=@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@NO};
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}
- (void)noteAccessibilityGranted {
    if(!_permissionAlert || ![self accessibilityTrusted]) return;
    [NSApp stopModalWithCode:NSModalResponseOK];
}
- (void)openAccessibilitySettingsFromWelcome:(id)sender {
    (void)sender;
    [self openAccessibilitySettings];
}
- (void)dismissWelcome:(id)sender {
    (void)sender;
    [NSApp stopModalWithCode:NSModalResponseCancel];
}
- (void)windowWillClose:(NSNotification *)note {
    if(note.object==_permissionAlert) [NSApp stopModalWithCode:NSModalResponseCancel];
}
- (void)offerAccessibilityIfNeeded {
    if([self accessibilityTrusted]) return;
    _editing=YES;
    [NSApp activate];
    NSString *iconPath=[NSBundle.mainBundle pathForResource:@"AppIcon" ofType:@"icns"];
    NSImage *icon=iconPath?[[NSImage alloc] initWithContentsOfFile:iconPath]:nil;
    if(icon) icon.size=NSMakeSize(64,64);
    NSPanel *panel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,560,220) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    panel.title=@"";
    panel.delegate=(id<NSWindowDelegate>)self;
    panel.level=NSModalPanelWindowLevel;
    panel.animationBehavior=NSWindowAnimationBehaviorAlertPanel;
    NSView *content=panel.contentView;
    NSImageView *iconView=[NSImageView imageViewWithImage:icon];
    iconView.imageScaling=NSImageScaleProportionallyUpOrDown;
    NSTextField *title=[NSTextField labelWithString:SWText(@"alert.welcomeTitle")];
    title.font=[NSFont boldSystemFontOfSize:15];
    NSTextField *body=[NSTextField wrappingLabelWithString:SWText(@"alert.welcomeBody")];
    body.font=[NSFont systemFontOfSize:13];
    body.textColor=NSColor.secondaryLabelColor;
    body.preferredMaxLayoutWidth=430;
    NSButton *allow=[NSButton buttonWithTitle:SWText(@"alert.allow") target:self action:@selector(openAccessibilitySettingsFromWelcome:)];
    NSButton *finished=[NSButton buttonWithTitle:SWText(@"alert.authorizedDone") target:self action:@selector(dismissWelcome:)];
    NSButton *later=[NSButton buttonWithTitle:SWText(@"alert.later") target:self action:@selector(dismissWelcome:)];
    for(NSButton *button in @[allow,finished,later]) button.bezelStyle=NSBezelStyleRounded;
    finished.keyEquivalent=@"\r";
    NSStackView *buttons=[NSStackView stackViewWithViews:@[allow,finished,later]];
    buttons.orientation=NSUserInterfaceLayoutOrientationHorizontal;
    buttons.spacing=8;
    NSArray<NSView *> *views=icon?@[iconView,title,body,buttons]:@[title,body,buttons];
    for(NSView *view in views) { view.translatesAutoresizingMaskIntoConstraints=NO; [content addSubview:view]; }
    CGFloat pad=20;
    NSLayoutAnchor *textLeading=icon?iconView.trailingAnchor:content.leadingAnchor;
    CGFloat textGap=icon?16:pad;
    NSMutableArray<NSLayoutConstraint *> *constraints=[NSMutableArray arrayWithObjects:
        [title.topAnchor constraintEqualToAnchor:content.topAnchor constant:pad],
        [title.leadingAnchor constraintEqualToAnchor:textLeading constant:textGap],
        [title.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-pad],
        [body.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
        [body.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [body.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [buttons.topAnchor constraintEqualToAnchor:body.bottomAnchor constant:18],
        [buttons.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-pad],
        [buttons.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-pad],
        [content.widthAnchor constraintEqualToConstant:560],
    nil];
    if(icon) {
        [constraints addObjectsFromArray:@[
            [iconView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:pad],
            [iconView.topAnchor constraintEqualToAnchor:title.topAnchor],
            [iconView.widthAnchor constraintEqualToConstant:64],
            [iconView.heightAnchor constraintEqualToConstant:64],
        ]];
    }
    [NSLayoutConstraint activateConstraints:constraints];
    [content layoutSubtreeIfNeeded];
    [panel setContentSize:content.fittingSize];
    [panel center];
    _permissionAlert=panel;
    __weak SWAppDelegate *weakSelf=self;
    NSTimer *timer=[NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *clock) {
        SWAppDelegate *strongSelf=weakSelf;
        if(!strongSelf || ![strongSelf accessibilityTrusted]) return;
        [clock invalidate];
        [strongSelf noteAccessibilityGranted];
    }];
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    id activeObserver=[NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidBecomeActiveNotification object:NSApp queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        (void)note;
        [weakSelf noteAccessibilityGranted];
    }];
    NSModalResponse response=[NSApp runModalForWindow:panel];
    [timer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:activeObserver];
    _permissionAlert=nil;
    [panel orderOut:nil];
    if(response==NSModalResponseOK && [self accessibilityTrusted]) {
        if(_hotKey.hotKey) [self setStatus:SWText(@"status.ready") error:NO];
        NSAlert *done=[NSAlert new];
        if(icon) done.icon=icon;
        done.messageText=SWText(@"alert.welcomeGrantedTitle");
        done.informativeText=SWText(@"alert.welcomeGrantedBody");
        [done addButtonWithTitle:SWText(@"alert.ok")];
        [NSApp activate];
        [done runModal];
    }
    _editing=NO;
    [self refreshMenu];
}
- (void)selectLanguage:(NSMenuItem *)sender {
    NSString *code=sender.representedObject;
    if(![code isKindOfClass:NSString.class]) return;
    BOOL saved=SWSaveUILanguage([code isEqualToString:@"auto"]?(CFStringRef)NULL:(__bridge CFStringRef)code);
    SWLoadLocalization();
    [self applyInterfaceLanguage];
    [self setStatus:saved?SWText(@"status.languageSaved"):SWText(@"status.languageUnsaved") error:!saved];
}
- (void)requestPermission:(id)sender {
    (void)sender;
    [NSApp activate];
    NSDictionary *options=@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES};
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    [self openAccessibilitySettings];
}
- (void)openAccessibilitySettings {
    /* System Settings still registers x-apple.systempreferences. The Privacy &
       Security extension opens Accessibility; the legacy pane is only a fallback. */
    NSURL *primary=[NSURL URLWithString:@"x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"];
    NSURL *legacy=[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    NSWorkspaceOpenConfiguration *config=[NSWorkspaceOpenConfiguration configuration];
    [NSWorkspace.sharedWorkspace openURL:primary configuration:config completionHandler:^(NSRunningApplication *app,NSError *error) {
        (void)app;
        if(!error || !legacy) return;
        dispatch_async(dispatch_get_main_queue(),^{
            [NSWorkspace.sharedWorkspace openURL:legacy configuration:[NSWorkspaceOpenConfiguration configuration] completionHandler:nil];
        });
    }];
    if(!_permissionAlert) [self setStatus:SWText(@"status.permissionOpened") error:NO];
}
- (void)recheck:(id)sender {
    (void)sender;
    OSStatus result=_hotKey.hotKey?noErr:SWHotKeyReplace(&_hotKey,_settings.keyCode,_settings.modifiers);
    BOOL trusted=AXIsProcessTrusted();
    [self refreshMenu];
    [self setStatus:result!=noErr?SWText(@"status.recheckConflict"):
        (trusted?SWText(@"status.recheckReady"):SWText(@"status.recheckDenied"))
        error:result!=noErr || !trusted];
}
- (void)toggleLogin:(id)sender {
    (void)sender;
    SMAppService *service=SMAppService.mainAppService;
    NSError *error=nil;
    if(service.status==SMAppServiceStatusRequiresApproval) {
        [SMAppService openSystemSettingsLoginItems]; return;
    }
    BOOL success=service.status==SMAppServiceStatusEnabled?
        [service unregisterAndReturnError:&error]:[service registerAndReturnError:&error];
    [self refreshMenu];
    if(!success) [self alertTitle:SWText(@"alert.loginTitle") message:SWFormat(@"alert.loginBody",error.localizedDescription?:SWText(@"alert.loginDenied"))];
    else [self setStatus:service.status==SMAppServiceStatusRequiresApproval?
        SWText(@"status.loginNeedsApproval"):SWText(@"status.loginUpdated") error:NO];
}
- (void)showDiagnostics:(id)sender {
    (void)sender;
    _editing=YES;
    NSString *text=SWFormat(@"alert.diagnosticsBody",
        NSProcessInfo.processInfo.operatingSystemVersionString,NSBundle.mainBundle.bundlePath,
        AXIsProcessTrusted()?SWText(@"diag.allowed"):SWText(@"diag.denied"),SWShortcutDescription(_settings.keyCode,_settings.modifiers),
        _hotKey.hotKey?SWText(@"diag.registered"):SWText(@"diag.failed"),_settings.leftMargin,_service.busy?SWText(@"diag.yes"):SWText(@"diag.no"),
        _lastStatusIsError?SWText(@"diag.errorMark"):@"",_lastStatus?:@"");
    [self alertTitle:SWText(@"alert.diagnosticsTitle") message:text];
    _editing=NO;
}
- (void)showAbout:(id)sender {
    (void)sender; _editing=YES;
    [self alertTitle:SWText(@"alert.aboutTitle") message:SWText(@"alert.aboutBody")];
    _editing=NO;
}
- (void)quit:(id)sender { (void)sender; [NSApp terminate:nil]; }
- (void)applicationWillTerminate:(NSNotification *)note {
    (void)note;
    [_service cancelPendingAction];
    [self stopMemoryTimer];
    SWHotKeyDestroy(&_hotKey);
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    if(_statusItem) [NSStatusBar.systemStatusBar removeStatusItem:_statusItem];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { (void)sender; return NO; }
@end
