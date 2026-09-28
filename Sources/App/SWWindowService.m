#import <dispatch/dispatch.h>
#import "SWWindowService.h"
#import "SWDisplayBridge.h"
#import "SWAX.h"
#import "SWPreferences.h"
#import "SWLocalization.h"
#import <stdatomic.h>

static NSString * const ChromeID=@"com.google.Chrome";
static const double layoutTolerance=3.0;
static const int transientAXAttempts=3;

static BOOL activateChrome(NSRunningApplication *chrome) {
    if(!chrome) return NO;
    /* macOS 14+ ignores NSApplicationActivateIgnoringOtherApps. Yield, then
       ask Chrome to take activation from this agent. */
    NSRunningApplication *ourselves=NSRunningApplication.currentApplication;
    [NSApp yieldActivationToApplication:chrome];
    return [chrome activateFromApplication:ourselves options:0];
}

static NSString *AXFailureText(AXError error) {
    NSString *key=@"ax.generic";
    switch(error) {
        case kAXErrorAPIDisabled: key=@"ax.disabled"; break;
        case kAXErrorCannotComplete: key=@"ax.timeout"; break;
        case kAXErrorInvalidUIElement: key=@"ax.invalid"; break;
        case kAXErrorAttributeUnsupported: key=@"ax.unsupported"; break;
        case kAXErrorNoValue: key=@"ax.noValue"; break;
        default: break;
    }
    return SWFormat(@"ax.format",SWText(key),(int)error);
}
static NSRunningApplication *chromeApplication(NSRunningApplication *frontmost) {
    NSArray<NSRunningApplication *> *apps=[NSRunningApplication runningApplicationsWithBundleIdentifier:ChromeID];
    pid_t wanted=frontmost.processIdentifier;
    for(NSRunningApplication *app in apps)
        if(app.processIdentifier==wanted) return app;
    return apps.firstObject;
}

@interface SWWindowJob : NSObject {
@public
    AXUIElementRef window;
    SWLayoutPlan plan;
    atomic_bool cancelled;
}
@property(nonatomic,strong) SWDisplaySnapshot *snapshot;
@property(nonatomic) unsigned applications;
@property(nonatomic) BOOL verifiedAfterMove;
@end
@implementation SWWindowJob
- (instancetype)init {
    if((self=[super init])) atomic_init(&cancelled,false);
    return self;
}
- (void)dealloc { if(window) CFRelease(window); }
@end
static bool jobShouldStop(void *context) {
    SWWindowJob *job=(__bridge SWWindowJob *)context;
    return job && atomic_load(&job->cancelled);
}

@interface SWWindowService ()
@property(nonatomic,readwrite) BOOL busy;
@property(nonatomic,strong) SWWindowJob *activeJob;
@property(nonatomic,copy) NSString *lastExternalUUID;
@end
@implementation SWWindowService {
    dispatch_queue_t _axQueue;
    atomic_uint_fast64_t _generation;
}
- (instancetype)init {
    if((self=[super init])) {
        _leftMargin=50;
        _dockDisplayUUID=CFBridgingRelease(SWCopyDockDisplayUUID());
        atomic_init(&_generation,0);
        _axQueue=dispatch_queue_create("com.jimmyliang.SideSpace.ax",DISPATCH_QUEUE_SERIAL);
        _lastExternalUUID=CFBridgingRelease(SWCopyExternalUUID());
    }
    return self;
}
- (uint64_t)advanceGeneration { return atomic_fetch_add(&_generation,1)+1; }
- (BOOL)generationIsCurrent:(uint64_t)generation { return atomic_load(&_generation)==generation; }
- (AXError)copyWindowForPID:(pid_t)pid generation:(uint64_t)generation window:(AXUIElementRef *)window {
    if(!window) return kAXErrorIllegalArgument;
    AXError error=kAXErrorCannotComplete;
    for(int attempt=0; attempt<transientAXAttempts; attempt++) {
        if(![self generationIsCurrent:generation]) return kAXErrorCannotComplete;
        if(*window) { CFRelease(*window); *window=NULL; }
        error=SWAXCopyWindow(pid,window);
        if(error!=kAXErrorCannotComplete) return error;
    }
    return error;
}
- (void)report:(NSString *)text error:(BOOL)error {
    NSAssert(NSThread.isMainThread,@"UI callback requires main thread");
    if(self.statusHandler) self.statusHandler(text,error);
}
- (void)finish:(NSString *)text error:(BOOL)error {
    self.busy=NO; self.activeJob=nil;
    [self report:text error:error];
}
- (void)cancelPendingAction {
    NSAssert(NSThread.isMainThread,@"main thread only");
    [self advanceGeneration];
    if(self.activeJob) atomic_store(&self.activeJob->cancelled,true);
    self.activeJob=nil;
    self.busy=NO;
}
- (void)openChrome {
    NSURL *url=[NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:ChromeID];
    if(!url) { [self report:SWText(@"svc.noChrome") error:YES]; return; }
    self.busy=YES;
    uint64_t generation=[self advanceGeneration];
    NSWorkspaceOpenConfiguration *config=[NSWorkspaceOpenConfiguration configuration];
    config.activates=YES;
    config.createsNewApplicationInstance=NO;
    [NSWorkspace.sharedWorkspace openApplicationAtURL:url configuration:config
        completionHandler:^(NSRunningApplication *app,NSError *error) {
        (void)app;
        dispatch_async(dispatch_get_main_queue(),^{
            if(![self generationIsCurrent:generation]) return;
            [self finish:error?SWFormat(@"svc.openFail",error.localizedDescription?:@""):
                SWText(@"svc.opened") error:error!=nil];
        });
    }];
}
- (void)revealChrome:(NSRunningApplication *)chrome {
    /* Never call the layout state machine on this path. Restoring minimization
       is allowed, but no position/size attributes are written. */
    [chrome unhide];
    if(!activateChrome(chrome)) { [self openChrome]; return; }
    if(!AXIsProcessTrusted()) {
        [self report:SWText(@"svc.revealNeedsAccess") error:NO]; return;
    }
    self.busy=YES;
    uint64_t generation=[self advanceGeneration];
    pid_t pid=chrome.processIdentifier;
    dispatch_async(_axQueue,^{ @autoreleasepool {
        AXUIElementRef window=NULL;
        AXError e=[self copyWindowForPID:pid generation:generation window:&window];
        if(e==kAXErrorSuccess && [self generationIsCurrent:generation])
            e=SWAXRestoreAndRaise(window);
        if(window) CFRelease(window);
        dispatch_async(dispatch_get_main_queue(),^{
            if(![self generationIsCurrent:generation]) return;
            if(e==kAXErrorNoValue) {
                [self finish:SWText(@"svc.noPlainWindow") error:NO];
            } else if(e!=kAXErrorSuccess) {
                [self finish:SWFormat(@"svc.raiseUnconfirmed",(int)e) error:YES];
            } else {
                [self finish:SWText(@"svc.revealed") error:NO];
            }
        });
    }});
}
- (void)rememberExternal:(NSString *)uuid {
    if(!uuid.length || [uuid isEqualToString:self.lastExternalUUID]) return;
    self.lastExternalUUID=uuid;
    SWSaveExternalUUID((__bridge CFStringRef)uuid);
}
- (void)performActionWithFrontmost:(NSRunningApplication *)frontmost {
    NSAssert(NSThread.isMainThread,@"hotkey handler must run on main thread");
    if(self.busy) return; // Ignore rapid repeats until the current transaction ends.
    NSRunningApplication *chrome=chromeApplication(frontmost);
    if(!chrome) { [self openChrome]; return; }
    if(frontmost.processIdentifier!=chrome.processIdentifier || chrome.hidden) {
        [self revealChrome:chrome]; return;
    }
    if(!AXIsProcessTrusted()) {
        [self report:SWText(@"svc.needAccess") error:YES]; return;
    }
    SWDisplaySnapshot *snapshot=[SWDisplaySnapshot capture];
    if(!snapshot) { [self report:SWText(@"svc.noDisplay") error:YES]; return; }
    /* Clicking our menu can temporarily activate this agent. Use the original
       foreground-app snapshot for the decision, then give Chrome focus back. */
    if(NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier!=chrome.processIdentifier)
        activateChrome(chrome);
    self.busy=YES;
    uint64_t generation=[self advanceGeneration];
    pid_t pid=chrome.processIdentifier;
    double margin=self.leftMargin;
    uint32_t preferred=[snapshot identifierForUUID:self.lastExternalUUID];
    uint32_t dockID=self.dockDisplayUUID.length?[snapshot identifierForUUID:self.dockDisplayUUID]:0;
    if(self.dockDisplayUUID.length && !dockID) dockID=UINT32_MAX;
    dispatch_async(_axQueue,^{ @autoreleasepool {
        SWWindowJob *job=[SWWindowJob new];
        AXError e=[self copyWindowForPID:pid generation:generation window:&job->window];
        SWRect frame={0};
        BOOL minimized=NO,fullScreen=NO,hasSheet=NO;
        if(e==kAXErrorSuccess && [self generationIsCurrent:generation]) {
            minimized=SWAXIsMinimized(job->window);
            fullScreen=SWAXIsFullScreen(job->window);
            hasSheet=SWAXHasSheet(job->window);
            if(minimized) e=SWAXRestoreAndRaise(job->window);
            else if(!fullScreen && !hasSheet) e=SWAXReadFrame(job->window,&frame);
        }
        if(e==kAXErrorSuccess && !minimized && !fullScreen && !hasSheet)
            job->plan=SWMakePlan(frame,snapshot->displays,snapshot->count,preferred,dockID,margin,layoutTolerance);
        job.snapshot=snapshot;
        dispatch_async(dispatch_get_main_queue(),^{
            if(![self generationIsCurrent:generation]) return;
            if(e!=kAXErrorSuccess) {
                [self finish:AXFailureText(e) error:YES]; return;
            }
            if(minimized) { activateChrome(chrome); [self finish:SWText(@"svc.unminimized") error:NO]; return; }
            if(fullScreen) { [self finish:SWText(@"svc.fullscreen") error:YES]; return; }
            if(hasSheet) { [self finish:SWText(@"svc.sheet") error:YES]; return; }
            if(job->plan.action==SWLayoutInvalid) {
                [self finish:SWText(@"svc.invalidPlan") error:YES]; return;
            }
            if(job->plan.action==SWLayoutKeep) {
                [self finish:SWText(@"svc.alreadyThere") error:NO]; return;
            }
            size_t current=job->plan.currentIndex;
            if(!snapshot->displays[current].builtIn)
                [self rememberExternal:snapshot.uuids[current]];
            self.activeJob=job;
            [self executeJob:job apply:YES];
        });
    }});
}
- (void)executeJob:(SWWindowJob *)job apply:(BOOL)apply {
    if(self.activeJob!=job || atomic_load(&job->cancelled)) return;
    NSRunningApplication *front=NSWorkspace.sharedWorkspace.frontmostApplication;
    NSString *frontID=front.bundleIdentifier;
    BOOL chromeFront=[frontID isEqualToString:ChromeID];
    /* The status item can activate this agent after Chrome was already chosen.
       Continuing is required; switching to some other app still cancels. */
    if(!chromeFront && ![frontID isEqualToString:NSBundle.mainBundle.bundleIdentifier]) {
        [self cancelPendingAction];
        [self report:SWText(@"svc.cancelled") error:NO]; return;
    }
    if(!chromeFront) {
        pid_t pid=0;
        if(job->window) AXUIElementGetPid(job->window,&pid);
        activateChrome([NSRunningApplication runningApplicationWithProcessIdentifier:pid]);
    }
    if(apply) job.applications++;
    uint32_t displayID=job.snapshot->displays[job->plan.targetIndex].identifier;
    dispatch_async(_axQueue,^{ @autoreleasepool {
        if(atomic_load(&job->cancelled)) return;
        AXError error=kAXErrorSuccess;
        BOOL disappeared=!CGDisplayIsActive(displayID);
        SWRect actual={0};
        if(!disappeared) {
            if(SWAXIsFullScreen(job->window) || SWAXIsMinimized(job->window) || SWAXHasSheet(job->window))
                error=kAXErrorAttributeUnsupported;
            else {
                if(apply && !atomic_load(&job->cancelled))
                    error=SWAXApplyFrame(job->window,job->plan.target,jobShouldStop,(__bridge void *)job);
                if(error==kAXErrorSuccess) error=SWAXReadFrame(job->window,&actual);
            }
        }
        dispatch_async(dispatch_get_main_queue(),^{
            if(self.activeJob!=job || atomic_load(&job->cancelled)) return;
            if(disappeared) { [self finish:SWText(@"svc.displayGone") error:YES]; return; }
            BOOL matches=error==kAXErrorSuccess && SWRectNear(actual,job->plan.target,layoutTolerance);
            if(matches) {
                /* One deferred verification on a cross-display move catches
                   asynchronous WindowServer clamping without delaying every action. */
                if(job->plan.crossesDisplay && !job.verifiedAfterMove) {
                    job.verifiedAfterMove=YES;
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,60*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
                        [self executeJob:job apply:NO];
                    });
                    return;
                }
                size_t target=job->plan.targetIndex;
                if(!job.snapshot->displays[target].builtIn)
                    [self rememberExternal:job.snapshot.uuids[target]];
                double effective=job->plan.target.x-job.snapshot->displays[target].frame.x;
                NSString *text=SWFormat(@"svc.layoutDone",effective);
                [self finish:text error:NO]; return;
            }
            BOOL retryable=error==kAXErrorSuccess || error==kAXErrorCannotComplete;
            if(retryable && job.applications<3) {
                int64_t delay=(int64_t)(60*job.applications)*NSEC_PER_MSEC;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,delay),dispatch_get_main_queue(),^{
                    [self executeJob:job apply:YES];
                });
                return;
            }
            NSString *text=error==kAXErrorSuccess?
                SWText(@"svc.sizeRejected"):
                AXFailureText(error);
            [self finish:text error:YES];
        });
    }});
}
@end
