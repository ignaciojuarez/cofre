#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
@class PLProfiles;
#import "CofreAirBridging.h"
NS_ASSUME_NONNULL_BEGIN
@interface CofreAirBridgeAdapter : NSObject <CofreAirBridging>
@property(nonatomic, readonly) PLProfiles *profiles;
/// Returns the profiles currently known to Air.
- (NSArray<NSDictionary *> *)instances;
- (nullable NSURL *)gameDirectoryForProfile:(NSString *)profile;
// Instance catalogs and profile operations. Air owns paths, mirrors and
// persistence.
- (NSArray<NSURL *> *)instanceMetadataURLs:(NSURL *)url
                                  resource:(NSInteger)resource;
- (NSArray<NSURL *> *)loaderProfileURLs:(NSString *)loader
                                   game:(NSString *)game
                                version:(NSString *)version;
- (void)neoForgeVersions:(NSString *)game
              completion:(void (^)(NSArray<NSString *> *,
                                   NSError *_Nullable))completion;
- (nullable NSDictionary *)createProfile:(NSString *)name
                                 version:(NSString *)version
                                  loader:(NSString *)loader
                               ownFolder:(BOOL)ownFolder
                               fabricAPI:(BOOL)fabricAPI
                                   error:(NSError **)error;
- (BOOL)saveLoaderProfile:(NSDictionary *)json
               forProfile:(NSString *)profile
                   loader:(NSString *)loader
                  version:(NSString *)version
                    error:(NSError **)error;
- (void)installForgeLoader:(NSString *)loader
                forProfile:(NSString *)name
                   version:(NSString *)version
                  progress:(void (^)(double, NSString *))progress
                completion:(void (^)(NSError *_Nullable))completion;
- (void)installInstanceMod:(NSDictionary *)file
                forProfile:(NSString *)profile
                completion:(void (^)(NSError *_Nullable))completion;
- (void)duplicateProfile:(NSString *)profile
              completion:(void (^)(NSDictionary *_Nullable,
                                   NSError *_Nullable))completion;
- (BOOL)deleteProfile:(NSString *)profile error:(NSError **)error;
/// Saves the user's icon pick (a CofreUI glyph name) as the profile's
/// cofreIcon; nil removes it.
- (void)setCofreIcon:(nullable NSString *)icon forProfile:(NSString *)profile;
- (void)exportProfile:(NSString *)profile
               format:(NSString *)format
           completion:
               (void (^)(NSURL *_Nullable, NSError *_Nullable))completion;

/// Returns the selected Air profile name.
- (NSString *)selectedProfileName;
/// Adds a server to a profile and reports an optional error.
/// Scans installed mods for a profile.
- (void)modsForProfile:(NSString *)profile
            completion:(void (^)(NSArray *))completion;
/// Toggles a mod's enabled state.
- (BOOL)toggleMod:(id)mod error:(NSError **)error;
/// Returns configured accounts: id, name, active.
- (void)removeAccountToken:(NSString *)accountID;
/// Signs in with Microsoft through Air's login (web page, then Xbox and
/// Minecraft tokens). The account comes back as id, name, demo (true when it
/// doesn't own Java Edition). Air saves and selects it.
- (void)signInMicrosoftWithProgress:(void (^)(NSString *))progress
                         completion:
                             (void (^)(NSDictionary *_Nullable account,
                                       NSError *_Nullable error))completion;
/// Reads an Air preference value.
- (id)preferenceObject:(NSString *)key profile:(nullable NSString *)profile;
/// Writes an Air preference value, isolating fields that PLProfiles isolates.
- (void)setPreferenceObject:(NSString *)key
                      value:(id)value
                    profile:(nullable NSString *)profile;
/// Applies Cofre's automatic memory default when needed.
- (void)ensureAutomaticMemoryDefault;
/// Starts a profile launch and reports progress labels.
- (void)launchProfile:(NSString *)profile
            accountID:(nullable NSString *)accountID
        gameArguments:(NSArray<NSString *> *)gameArguments
             progress:(void (^)(CofreLaunchEvent, double, NSString *_Nullable))progress;
- (void)hideCofreLaunchOverlay;
/// Searches projects from the selected catalog.
- (void)searchProjects:(NSDictionary *)filters
                source:(NSInteger)source
            completion:(void (^)(NSArray *, NSError *_Nullable))completion;
/// Lists versions for a project.
- (void)projectVersions:(NSString *)projectID
                 source:(NSInteger)source
             completion:(void (^)(NSArray *, NSError *_Nullable))completion;
/// Minecraft version and loader for mod compatibility.
- (NSDictionary *)modContextForProfile:(NSString *)profile;
/// Searches multiplayer servers.
/// Imports a modpack into a profile.
- (void)importPack:(NSURL *)url
           profile:(NSString *_Nullable)profile
          progress:(void (^)(double, NSString *))progress
        completion:(void (^)(NSError *_Nullable))completion;
/// Returns Air's controls editor.
@end
NS_ASSUME_NONNULL_END
