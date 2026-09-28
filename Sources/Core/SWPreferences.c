#include "SWPreferences.h"
#include <Carbon/Carbon.h>
static const CFStringRef domain=CFSTR("com.jimmyliang.SideSpace");
static int64_t loadNumber(CFStringRef key,int64_t fallback) {
    CFPropertyListRef value=CFPreferencesCopyAppValue(key,domain);
    int64_t result=fallback;
    if (value && CFGetTypeID(value)==CFNumberGetTypeID())
        CFNumberGetValue((CFNumberRef)value,kCFNumberSInt64Type,&result);
    if (value) CFRelease(value);
    return result;
}
static void saveNumber(CFStringRef key,int64_t value) {
    CFNumberRef number=CFNumberCreate(NULL,kCFNumberSInt64Type,&value);
    if (number) { CFPreferencesSetAppValue(key,number,domain); CFRelease(number); }
}
bool SWSettingsShortcutPreset(int index, uint32_t *keyCode, uint32_t *modifiers) {
    static const uint32_t keys[]={kVK_ANSI_A,kVK_ANSI_A,kVK_RightArrow};
    static const uint32_t mods[]={optionKey|cmdKey,optionKey,controlKey|optionKey|cmdKey};
    if (!keyCode || !modifiers || index<0 || index>2) return false;
    *keyCode=keys[index]; *modifiers=mods[index];
    return true;
}
SWSettings SWSettingsDefaults(void) {
    uint32_t key=0,mods=0;
    SWSettingsShortcutPreset(0,&key,&mods);
    return (SWSettings){50,key,mods};
}
SWSettings SWSettingsLoad(void) {
    SWSettings s=SWSettingsDefaults();
    int64_t margin=loadNumber(CFSTR("leftMargin"),s.leftMargin);
    int64_t key=loadNumber(CFSTR("keyCode"),s.keyCode);
    int64_t mods=loadNumber(CFSTR("modifiers"),s.modifiers);
    uint32_t allowed=controlKey|optionKey|cmdKey|shiftKey;
    if (margin>=0 && margin<=500) s.leftMargin=(int)margin;
    if (key>=0 && key<=127 && mods>=0 && !(mods&~(int64_t)allowed) &&
        (mods&(cmdKey|controlKey|optionKey))) { s.keyCode=(uint32_t)key; s.modifiers=(uint32_t)mods; }
    return s;
}
bool SWSettingsSave(SWSettings s) {
    saveNumber(CFSTR("schemaVersion"),1);
    saveNumber(CFSTR("leftMargin"),s.leftMargin);
    saveNumber(CFSTR("keyCode"),s.keyCode);
    saveNumber(CFSTR("modifiers"),s.modifiers);
    return CFPreferencesAppSynchronize(domain);
}
CFStringRef SWCopyExternalUUID(void) {
    CFPropertyListRef value=CFPreferencesCopyAppValue(CFSTR("lastExternalUUID"),domain);
    if (value && CFGetTypeID(value)==CFStringGetTypeID()) return (CFStringRef)value;
    if (value) CFRelease(value);
    return NULL;
}
bool SWSaveExternalUUID(CFStringRef uuid) {
    CFPreferencesSetAppValue(CFSTR("lastExternalUUID"),uuid,domain);
    return CFPreferencesAppSynchronize(domain);
}
CFStringRef SWCopyUILanguage(void) {
    CFPropertyListRef value=CFPreferencesCopyAppValue(CFSTR("uiLanguage"),domain);
    if (value && CFGetTypeID(value)==CFStringGetTypeID()) {
        CFIndex length=CFStringGetLength((CFStringRef)value);
        if (length>0 && length<=32) return (CFStringRef)value;
    }
    if (value) CFRelease(value);
    return NULL;
}
bool SWSaveUILanguage(CFStringRef code) {
    if (!code || CFStringGetLength(code)==0 || CFStringCompare(code,CFSTR("auto"),0)==kCFCompareEqualTo)
        CFPreferencesSetAppValue(CFSTR("uiLanguage"),NULL,domain);
    else CFPreferencesSetAppValue(CFSTR("uiLanguage"),code,domain);
    return CFPreferencesAppSynchronize(domain);
}

CFStringRef SWCopyDockDisplayUUID(void) {
    CFPropertyListRef value=CFPreferencesCopyAppValue(CFSTR("dockDisplayUUID"),domain);
    if(value && CFGetTypeID(value)==CFStringGetTypeID() && CFStringGetLength((CFStringRef)value)>0)
        return (CFStringRef)value;
    if(value) CFRelease(value);
    return NULL;
}
bool SWSaveDockDisplayUUID(CFStringRef uuid) {
    CFPreferencesSetAppValue(CFSTR("dockDisplayUUID"),uuid,domain);
    return CFPreferencesAppSynchronize(domain);
}
