#ifndef SW_HOTKEY_H
#define SW_HOTKEY_H
#include <Carbon/Carbon.h>
#include <stdbool.h>
typedef void (*SWHotKeyCallback)(void *context);
typedef struct {
    EventHandlerRef handler;
    EventHotKeyRef hotKey;
    EventHandlerUPP handlerUPP;
    SWHotKeyCallback callback;
    void *context;
    UInt32 identifier;
    UInt32 keyCode;
    UInt32 modifiers;
    bool down;
    bool suspended;
} SWHotKey;
OSStatus SWHotKeyInit(SWHotKey *hotKey,SWHotKeyCallback callback,void *context);
/* Register the candidate before removing the old key. Failure preserves old key. */
OSStatus SWHotKeyReplace(SWHotKey *hotKey,UInt32 keyCode,UInt32 modifiers);
void SWHotKeySuspend(SWHotKey *hotKey);
OSStatus SWHotKeyResume(SWHotKey *hotKey);
void SWHotKeyDestroy(SWHotKey *hotKey);
#endif
