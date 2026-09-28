#ifndef SW_LOCALIZATION_H
#define SW_LOCALIZATION_H
#import <Foundation/Foundation.h>
/* Loads one language table. A saved choice wins. Otherwise region CN uses
   Simplified Chinese, then the system preferred languages, then English. */
void SWLoadLocalization(void);
NSString *SWText(NSString *key);
NSString *SWFormat(NSString *key, ...);
NSString *SWResolvedLanguage(void);
NSString *SWSelectedLanguage(void);
NSArray<NSString *> *SWLanguageCodes(void);
NSString *SWLanguageEndonym(NSString *code);
#endif
