#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
@protocol CofreAirBridging <NSObject>
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
/// The instance's mods folder (made if missing). Cofre lists, toggles and
/// installs content there and in its sibling shaderpacks/resourcepacks.
- (nullable NSString *)modsFolderForProfile:(NSString *)profile;
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

- (NSString *)selectedProfileName;
- (void)worldsForProfile:(NSString *)profile
              completion:(void (^)(NSArray *))completion;
- (void)deleteWorld:(NSString *)worldID
         forProfile:(NSString *)profile
         completion:(void (^)(NSError *_Nullable))completion;
- (void)addServer:(NSString *)address
             name:(NSString *)name
       forProfile:(NSString *)profile
       completion:(void (^)(NSError *_Nullable))completion;
- (void)modsForProfile:(NSString *)profile
            completion:(void (^)(NSArray *))completion;
- (NSArray<NSDictionary *> *)accounts;
- (void)signInMicrosoftWithProgress:(void (^)(NSString *))progress
                         completion:
                             (void (^)(NSDictionary *_Nullable account,
                                       NSError *_Nullable error))completion;
- (id)preferenceObject:(NSString *)key profile:(nullable NSString *)profile;
- (void)setPreferenceObject:(NSString *)key
                      value:(id)value
                    profile:(nullable NSString *)profile;
- (void)ensureAutomaticMemoryDefault;
- (void)setServerIp:(NSString *)address forProfile:(NSString *)profile;
- (void)launchProfile:(NSString *)profile
            accountID:(nullable NSString *)accountID
             progress:(void (^)(NSString *))progress;
/// Hides Cofre's launch overlay. Java may continue if it already started.
- (void)hideCofreLaunchOverlay;
- (void)searchProjects:(NSDictionary *)filters
                source:(NSInteger)source
            completion:(void (^)(NSArray *, NSError *_Nullable))completion;
- (void)projectVersions:(NSString *)projectID
                 source:(NSInteger)source
             completion:(void (^)(NSArray *, NSError *_Nullable))completion;
/// Minecraft version and loader for mod compatibility.
- (NSDictionary *)modContextForProfile:(NSString *)profile;
- (void)searchServers:(NSDictionary *)filters
               source:(NSInteger)source
           completion:(void (^)(NSArray *, NSError *_Nullable))completion;
- (void)importPack:(NSURL *)url
           profile:(nullable NSString *)profile
          progress:(void (^)(double, NSString *))progress
        completion:(void (^)(NSError *_Nullable))completion;
- (UIViewController *)controlsEditor;
// Game input for CofreGameInput.swift, sent through Air's callback bridge. Only
// meaningful while the game runs.
- (void)gameInputKey:(NSString *)name down:(BOOL)down;
- (void)gameInputMouseButton:(NSInteger)button down:(BOOL)down;
- (void)gameInputLookX:(float)deltaX y:(float)deltaY;
- (void)setGameKeyboardShown:(BOOL)shown;
- (void)gameInputScroll:(NSInteger)steps;
/// inWorld, guiScale and pixelsPerPoint (0 when unknown).
- (NSDictionary<NSString *, NSNumber *> *)gameScreenState;
@end
NS_ASSUME_NONNULL_END
