#import "SWLocalization.h"
#import "SWPreferences.h"
#include <stdarg.h>

static NSDictionary<NSString *, NSString *> *SWActive;
static NSDictionary<NSString *, NSString *> *SWEnglish;
static NSString *SWResolved;

static NSArray<NSString *> *SWCodes(void) {
    static NSArray<NSString *> *codes;
    static dispatch_once_t once;
    dispatch_once(&once,^{
        codes=@[@"en",@"zh-Hans",@"zh-Hant",@"ja",@"ko",@"de",@"fr",@"es",@"pt",@"it",@"ru"];
    });
    return codes;
}
static NSDictionary<NSString *, NSString *> *SWLoadTable(NSString *code) {
    NSString *path=[NSBundle.mainBundle pathForResource:@"Localizable" ofType:@"strings" inDirectory:nil forLocalization:code];
    NSData *data=path?[NSData dataWithContentsOfFile:path]:nil;
    id table=data?[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL]:nil;
    return [table isKindOfClass:NSDictionary.class]?table:@{};
}
static BOOL SWSupported(NSString *code) {
    return [SWCodes() containsObject:code];
}
static NSString *SWMatch(NSString *identifier) {
    NSString *value=identifier.lowercaseString;
    if([value hasPrefix:@"zh-hant"]||[value hasPrefix:@"zh-tw"]||[value hasPrefix:@"zh-hk"]||[value hasPrefix:@"zh-mo"]) return @"zh-Hant";
    if([value hasPrefix:@"zh"]) return @"zh-Hans";
    if([value hasPrefix:@"ja"]) return @"ja";
    if([value hasPrefix:@"ko"]) return @"ko";
    if([value hasPrefix:@"de"]) return @"de";
    if([value hasPrefix:@"fr"]) return @"fr";
    if([value hasPrefix:@"es"]) return @"es";
    if([value hasPrefix:@"pt"]) return @"pt";
    if([value hasPrefix:@"it"]) return @"it";
    if([value hasPrefix:@"ru"]) return @"ru";
    if([value hasPrefix:@"en"]) return @"en";
    return nil;
}
static NSString *SWResolve(void) {
    NSString *saved=CFBridgingRelease(SWCopyUILanguage());
    if(SWSupported(saved)) return saved;
    if([NSLocale.currentLocale.regionCode isEqualToString:@"CN"]) return @"zh-Hans";
    for(NSString *identifier in NSLocale.preferredLanguages) {
        NSString *match=SWMatch(identifier);
        if(match) return match;
    }
    return @"en";
}
void SWLoadLocalization(void) {
    SWResolved=SWResolve();
    if(!SWEnglish) SWEnglish=SWLoadTable(@"en");
    SWActive=[SWResolved isEqualToString:@"en"]?SWEnglish:SWLoadTable(SWResolved);
}
NSString *SWText(NSString *key) {
    NSString *value=SWActive[key];
    if(![value isKindOfClass:NSString.class]||!value.length) value=SWEnglish[key];
    return [value isKindOfClass:NSString.class]&&value.length?value:key;
}
NSString *SWFormat(NSString *key, ...) {
    va_list args;
    va_start(args,key);
    NSString *text=[[NSString alloc] initWithFormat:SWText(key) arguments:args];
    va_end(args);
    return text;
}
NSString *SWResolvedLanguage(void) { return SWResolved?:@"en"; }
NSString *SWSelectedLanguage(void) {
    NSString *saved=CFBridgingRelease(SWCopyUILanguage());
    return SWSupported(saved)?saved:@"auto";
}
NSArray<NSString *> *SWLanguageCodes(void) { return SWCodes(); }
NSString *SWLanguageEndonym(NSString *code) {
    NSDictionary<NSString *, NSString *> *names=@{
        @"en":@"English",@"zh-Hans":@"简体中文",@"zh-Hant":@"繁體中文",@"ja":@"日本語",
        @"ko":@"한국어",@"de":@"Deutsch",@"fr":@"Français",@"es":@"Español",
        @"pt":@"Português",@"it":@"Italiano",@"ru":@"Русский"
    };
    return names[code]?:code;
}
