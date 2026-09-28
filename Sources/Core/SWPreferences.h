#ifndef SW_PREFERENCES_H
#define SW_PREFERENCES_H
#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>
#include <stdbool.h>
typedef struct {
    int leftMargin;
    uint32_t keyCode;
    uint32_t modifiers; /* Carbon modifier mask, not NSEventModifierFlags. */
} SWSettings;
SWSettings SWSettingsDefaults(void);
/* 0: Option-Command-A. 1: Option-A. 2: Control-Option-Command-Right. */
bool SWSettingsShortcutPreset(int index, uint32_t *keyCode, uint32_t *modifiers);
SWSettings SWSettingsLoad(void);
bool SWSettingsSave(SWSettings settings);
CFStringRef SWCopyExternalUUID(void) CF_RETURNS_RETAINED;
bool SWSaveExternalUUID(CFStringRef uuid);
/* NULL means follow the system. A saved code is a short localization identifier. */
CFStringRef SWCopyUILanguage(void) CF_RETURNS_RETAINED;
bool SWSaveUILanguage(CFStringRef code);
/* NULL selects the built-in display. Independent of lastExternalUUID. */
CFStringRef SWCopyDockDisplayUUID(void) CF_RETURNS_RETAINED;
bool SWSaveDockDisplayUUID(CFStringRef uuid);
#endif
