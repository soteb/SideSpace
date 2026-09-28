#include "SWHotKey.h"
#include <string.h>
#define SW_HOTKEY_SIGNATURE ((OSType)0x53574E44)
static OSStatus receive(EventHandlerCallRef call,EventRef event,void *context) {
    (void)call;
    SWHotKey *h=context;
    EventHotKeyID id={0};
    if (!h || GetEventParameter(event,kEventParamDirectObject,typeEventHotKeyID,
        NULL,sizeof(id),NULL,&id)!=noErr) return eventNotHandledErr;
    if (id.signature!=SW_HOTKEY_SIGNATURE || id.id!=h->identifier || h->suspended)
        return eventNotHandledErr;
    UInt32 kind=GetEventKind(event);
    if (kind==kEventHotKeyReleased) { h->down=false; return noErr; }
    if (kind==kEventHotKeyPressed) {
        if (!h->down) { h->down=true; if (h->callback) h->callback(h->context); }
        return noErr;
    }
    return eventNotHandledErr;
}
OSStatus SWHotKeyInit(SWHotKey *h,SWHotKeyCallback cb,void *ctx) {
    if (!h) return paramErr;
    memset(h,0,sizeof(*h)); h->callback=cb; h->context=ctx;
    EventTypeSpec types[]={{kEventClassKeyboard,kEventHotKeyPressed},
                           {kEventClassKeyboard,kEventHotKeyReleased}};
    h->handlerUPP=NewEventHandlerUPP(receive);
    return InstallEventHandler(GetApplicationEventTarget(),h->handlerUPP,2,types,h,&h->handler);
}
OSStatus SWHotKeyReplace(SWHotKey *h,UInt32 key,UInt32 mods) {
    if (!h || !h->handler) return paramErr;
    if (h->hotKey && h->keyCode==key && h->modifiers==mods) return noErr;
    UInt32 next=h->identifier+1;
    if (!next) next=1;
    EventHotKeyRef candidate=NULL;
    EventHotKeyID id={SW_HOTKEY_SIGNATURE,next};
    OSStatus result=RegisterEventHotKey(key,mods,id,GetApplicationEventTarget(),0,&candidate);
    if (result!=noErr) return result;
    if (h->hotKey) UnregisterEventHotKey(h->hotKey);
    h->hotKey=candidate; h->identifier=next; h->keyCode=key; h->modifiers=mods;
    h->down=false; h->suspended=false;
    return noErr;
}
void SWHotKeySuspend(SWHotKey *h) {
    if (!h) return;
    if (h->hotKey) UnregisterEventHotKey(h->hotKey);
    h->hotKey=NULL; h->down=false; h->suspended=true;
}
OSStatus SWHotKeyResume(SWHotKey *h) {
    if (!h) return paramErr;
    return SWHotKeyReplace(h,h->keyCode,h->modifiers);
}
void SWHotKeyDestroy(SWHotKey *h) {
    if (!h) return;
    if (h->hotKey) UnregisterEventHotKey(h->hotKey);
    if (h->handler) RemoveEventHandler(h->handler);
    if (h->handlerUPP) DisposeEventHandlerUPP(h->handlerUPP);
    memset(h,0,sizeof(*h));
}
