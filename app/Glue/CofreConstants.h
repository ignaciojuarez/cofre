#ifndef COFRE_CONSTANTS_H
#define COFRE_CONSTANTS_H
#import <Foundation/Foundation.h>
#define COFRE_TUNNEL_BUNDLE_ID @"com.ignacio.cofre.tunnel"
#define COFRE_TUNNEL_ADDRESS @"10.7.0.1"
#define COFRE_PAIRING_RELATIVE_PATH @"StikJIT/pairingFile.plist"
#define COFRE_DOWNLOAD_SOURCE_DEFAULTED_KEY @"cofre.download_source_defaulted"

typedef NS_ENUM(NSInteger, CofreLoaderKind) {
  CofreLoaderKindVanilla,
  CofreLoaderKindFabric,
  CofreLoaderKindForge,
  CofreLoaderKindNeoForge,
  CofreLoaderKindQuilt,
  CofreLoaderKindUnknown,
};

/// Decode the profile/JSON spelling once at the ObjC Air boundary.
static inline CofreLoaderKind CofreLoaderKindFromRaw(NSString *raw) {
  NSString *value = raw.lowercaseString;
  if ([value isEqualToString:@"vanilla"]) return CofreLoaderKindVanilla;
  if ([value isEqualToString:@"fabric"]) return CofreLoaderKindFabric;
  if ([value isEqualToString:@"forge"]) return CofreLoaderKindForge;
  if ([value isEqualToString:@"neoforge"]) return CofreLoaderKindNeoForge;
  if ([value isEqualToString:@"quilt"]) return CofreLoaderKindQuilt;
  return CofreLoaderKindUnknown;
}
#endif
