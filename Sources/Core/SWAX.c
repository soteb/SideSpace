#include "SWAX.h"
#include <math.h>
static const float messagingTimeout=0.20f;
static bool boolValue(AXUIElementRef element,CFStringRef attribute) {
    CFTypeRef value=NULL;
    AXError e=AXUIElementCopyAttributeValue(element,attribute,&value);
    bool result=e==kAXErrorSuccess && value &&
        CFGetTypeID(value)==CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)value);
    if (value) CFRelease(value);
    return result;
}
static bool standardWindow(AXUIElementRef window) {
    if (!window || CFGetTypeID(window)!=AXUIElementGetTypeID()) return false;
    CFTypeRef role=NULL;
    AXError e=AXUIElementCopyAttributeValue(window,kAXSubroleAttribute,&role);
    bool result=e==kAXErrorSuccess && role &&
        CFGetTypeID(role)==CFStringGetTypeID() && CFEqual(role,kAXStandardWindowSubrole);
    if (role) CFRelease(role);
    return result;
}
AXError SWAXCopyWindow(pid_t pid,AXUIElementRef *out) {
    if (!out || pid<=0) return kAXErrorIllegalArgument;
    *out=NULL;
    AXUIElementRef app=AXUIElementCreateApplication(pid);
    if (!app) return kAXErrorFailure;
    AXUIElementSetMessagingTimeout(app,messagingTimeout);
    /* Permission failure stops immediately. A timeout on the focused window does
       not: the main window or the window list may still answer. */
    AXError fallback=kAXErrorNoValue;
    CFStringRef attrs[]={kAXFocusedWindowAttribute,kAXMainWindowAttribute};
    for (size_t i=0;i<2;i++) {
        CFTypeRef value=NULL;
        AXError e=AXUIElementCopyAttributeValue(app,attrs[i],&value);
        if (e==kAXErrorAPIDisabled) {
            if (value) CFRelease(value);
            CFRelease(app); return e;
        }
        if (e==kAXErrorSuccess && value && CFGetTypeID(value)==AXUIElementGetTypeID()) {
            AXUIElementRef candidate=(AXUIElementRef)value;
            AXUIElementSetMessagingTimeout(candidate,messagingTimeout);
            if (standardWindow(candidate)) {
                *out=candidate; CFRelease(app); return kAXErrorSuccess;
            }
            fallback=kAXErrorNoValue;
        } else if (e==kAXErrorCannotComplete) fallback=e;
        if (value) CFRelease(value);
    }
    CFTypeRef value=NULL;
    AXError e=AXUIElementCopyAttributeValue(app,kAXWindowsAttribute,&value);
    CFRelease(app);
    if (e==kAXErrorAPIDisabled) { if(value) CFRelease(value); return e; }
    if (e!=kAXErrorSuccess || !value) {
        if(value) CFRelease(value);
        return e==kAXErrorSuccess?fallback:e;
    }
    if (CFGetTypeID(value)!=CFArrayGetTypeID()) { CFRelease(value); return fallback; }
    CFArrayRef windows=(CFArrayRef)value;
    AXUIElementRef minimized=NULL;
    for (CFIndex i=0;i<CFArrayGetCount(windows);i++) {
        AXUIElementRef candidate=(AXUIElementRef)CFArrayGetValueAtIndex(windows,i);
        if (!candidate || CFGetTypeID(candidate)!=AXUIElementGetTypeID()) continue;
        AXUIElementSetMessagingTimeout(candidate,messagingTimeout);
        if (!standardWindow(candidate)) continue;
        if (!SWAXIsMinimized(candidate)) { *out=(AXUIElementRef)CFRetain(candidate); break; }
        if (!minimized) minimized=candidate;
    }
    if (!*out && minimized) *out=(AXUIElementRef)CFRetain(minimized);
    CFRelease(windows);
    return *out?kAXErrorSuccess:kAXErrorNoValue;
}
AXError SWAXReadFrame(AXUIElementRef window,SWRect *out) {
    if (!window || !out) return kAXErrorIllegalArgument;
    CFTypeRef position=NULL,size=NULL;
    AXError e=AXUIElementCopyAttributeValue(window,kAXPositionAttribute,&position);
    if (e!=kAXErrorSuccess) { if(position) CFRelease(position); return e; }
    e=AXUIElementCopyAttributeValue(window,kAXSizeAttribute,&size);
    if (e!=kAXErrorSuccess) { if(position) CFRelease(position); if(size) CFRelease(size); return e; }
    CGPoint p=CGPointZero; CGSize s=CGSizeZero;
    bool ok=position && size && CFGetTypeID(position)==AXValueGetTypeID() &&
        CFGetTypeID(size)==AXValueGetTypeID() &&
        AXValueGetType((AXValueRef)position)==kAXValueCGPointType &&
        AXValueGetType((AXValueRef)size)==kAXValueCGSizeType &&
        AXValueGetValue((AXValueRef)position,kAXValueCGPointType,&p) &&
        AXValueGetValue((AXValueRef)size,kAXValueCGSizeType,&s);
    if(position) CFRelease(position); if(size) CFRelease(size);
    if (!ok) return kAXErrorFailure;
    *out=(SWRect){p.x,p.y,s.width,s.height};
    return SWRectValid(*out)?kAXErrorSuccess:kAXErrorFailure;
}
bool SWAXIsMinimized(AXUIElementRef w) { return boolValue(w,kAXMinimizedAttribute); }
bool SWAXIsFullScreen(AXUIElementRef w) {
    /* Public Accessibility attribute name, not a private framework call. */
    return boolValue(w,CFSTR("AXFullScreen"));
}
bool SWAXHasSheet(AXUIElementRef w) {
    CFTypeRef value=NULL;
    /* Public attribute name. The kAXSheetsAttribute constant is absent from the macOS 27 SDK. */
    AXError e=AXUIElementCopyAttributeValue(w,CFSTR("AXSheets"),&value);
    bool result=e==kAXErrorSuccess && value && CFGetTypeID(value)==CFArrayGetTypeID() &&
        CFArrayGetCount((CFArrayRef)value)>0;
    if(value) CFRelease(value);
    return result;
}
AXError SWAXRestoreAndRaise(AXUIElementRef w) {
    if (SWAXIsMinimized(w)) {
        AXError e=AXUIElementSetAttributeValue(w,kAXMinimizedAttribute,kCFBooleanFalse);
        if (e!=kAXErrorSuccess) return e;
    }
    return AXUIElementPerformAction(w,kAXRaiseAction);
}
static bool stopped(SWAXShouldStop stop,void *context) {
    return stop && stop(context);
}
static AXError setPosition(AXUIElementRef w,SWRect r) {
    CGPoint point=CGPointMake(r.x,r.y);
    AXValueRef value=AXValueCreate(kAXValueCGPointType,&point);
    if (!value) return kAXErrorFailure;
    AXError e=AXUIElementSetAttributeValue(w,kAXPositionAttribute,value);
    CFRelease(value); return e;
}
static AXError setSize(AXUIElementRef w,double width,double height) {
    CGSize size=CGSizeMake(width,height);
    AXValueRef value=AXValueCreate(kAXValueCGSizeType,&size);
    if (!value) return kAXErrorFailure;
    AXError e=AXUIElementSetAttributeValue(w,kAXSizeAttribute,value);
    CFRelease(value); return e;
}
AXError SWAXApplyFrame(AXUIElementRef w,SWRect target,SWAXShouldStop stop,void *context) {
    if (!w || !SWRectValid(target)) return kAXErrorIllegalArgument;
    if (stopped(stop,context)) return kAXErrorCannotComplete;
    Boolean positionSettable=false,sizeSettable=false;
    AXError e=AXUIElementIsAttributeSettable(w,kAXPositionAttribute,&positionSettable);
    if(e!=kAXErrorSuccess) return e;
    e=AXUIElementIsAttributeSettable(w,kAXSizeAttribute,&sizeSettable);
    if(e!=kAXErrorSuccess) return e;
    if(!positionSettable || !sizeSettable) return kAXErrorAttributeUnsupported;
    if (stopped(stop,context)) return kAXErrorCannotComplete;
    SWRect current;
    e=SWAXReadFrame(w,&current); if(e!=kAXErrorSuccess) return e;
    /* Shrink before moving from a large external display to the laptop. This
       avoids macOS clamping a still-oversized window to the source display. */
    if(current.width>target.width+3 || current.height>target.height+3) {
        if (stopped(stop,context)) return kAXErrorCannotComplete;
        e=setSize(w,fmin(current.width,target.width),fmin(current.height,target.height));
        if(e!=kAXErrorSuccess) return e;
    }
    if (stopped(stop,context)) return kAXErrorCannotComplete;
    e=setPosition(w,target); if(e!=kAXErrorSuccess) return e;
    if (stopped(stop,context)) return kAXErrorCannotComplete;
    e=setSize(w,target.width,target.height); if(e!=kAXErrorSuccess) return e;
    if (stopped(stop,context)) return kAXErrorCannotComplete;
    return setPosition(w,target);
}
const char *SWAXErrorMessage(AXError e) {
    switch(e) {
        case kAXErrorSuccess:return "成功";
        case kAXErrorAPIDisabled:return "辅助功能权限未开启或已被撤销";
        case kAXErrorCannotComplete:return "Chrome 未及时响应辅助功能请求，请稍后重试";
        case kAXErrorInvalidUIElement:return "窗口已关闭或改变，请再次按快捷键";
        case kAXErrorAttributeUnsupported:return "当前窗口不支持移动或调整尺寸";
        case kAXErrorNoValue:return "没有可操作的 Chrome 普通窗口，请先打开一个窗口";
        default:return "窗口操作失败，请查看菜单中的最近状态";
    }
}
