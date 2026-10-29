#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
@protocol CofreAirBridging <NSObject>
- (NSArray<NSDictionary *> *)instances;
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
- (void)installProject:(NSDictionary *)data
               profile:(NSString *)profile
              progress:(void (^)(double, NSString *))progress
            completion:(void (^)(NSError *_Nullable))completion;
- (void)importPack:(NSURL *)url
           profile:(nullable NSString *)profile
          progress:(void (^)(double, NSString *))progress
        completion:(void (^)(NSError *_Nullable))completion;
- (UIViewController *)controlsEditor;
@end
NS_ASSUME_NONNULL_END
