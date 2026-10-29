#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
@class PLProfiles;
#import "CofreAirBridging.h"
NS_ASSUME_NONNULL_BEGIN
@interface CofreAirBridgeAdapter : NSObject <CofreAirBridging>
@property(nonatomic, readonly) PLProfiles *profiles;
/// Returns the profiles currently known to Air.
- (NSArray<NSDictionary *> *)instances;
/// Returns the selected Air profile name.
- (NSString *)selectedProfileName;
/// Scans worlds for a profile.
- (void)worldsForProfile:(NSString *)profile
              completion:(void (^)(NSArray *))completion;
/// Deletes a world and reports an optional error.
- (void)deleteWorld:(NSString *)worldID
         forProfile:(NSString *)profile
         completion:(void (^)(NSError *_Nullable))completion;
/// Adds a server to a profile and reports an optional error.
- (void)addServer:(NSString *)address
             name:(NSString *)name
       forProfile:(NSString *)profile
       completion:(void (^)(NSError *_Nullable))completion;
/// Scans installed mods for a profile.
- (void)modsForProfile:(NSString *)profile
            completion:(void (^)(NSArray *))completion;
/// Toggles a mod's enabled state.
- (BOOL)toggleMod:(id)mod error:(NSError **)error;
/// Returns configured accounts: id, name, active.
- (NSArray<NSDictionary *> *)accounts;
/// Signs in with Microsoft through Air's login (web page, then Xbox and
/// Minecraft tokens). The account comes back as id, name, demo (true when it
/// doesn't own Java Edition). Air saves and selects it.
- (void)signInMicrosoftWithProgress:(void (^)(NSString *))progress
                         completion:
                             (void (^)(NSDictionary *_Nullable account,
                                       NSError *_Nullable error))completion;
/// Reads an Air preference value.
- (id)preferenceObject:(NSString *)key;
/// Writes an Air preference value.
- (void)setPreferenceObject:(NSString *)key value:(id)value;
/// Returns preferences for a profile.
- (NSDictionary *)preferencesForProfile:(NSString *)profile;
/// Applies Cofre's automatic memory default when needed.
- (void)ensureAutomaticMemoryDefault;
/// Starts a profile launch and reports progress labels.
- (void)launchProfile:(NSString *)profile
            accountID:(nullable NSString *)accountID
             progress:(void (^)(NSString *stage))progress;
/// Searches projects from the selected catalog.
- (void)searchProjects:(NSDictionary *)filters
                source:(NSInteger)source
            completion:(void (^)(NSArray *, NSError *_Nullable))completion;
/// Lists versions for a project.
- (void)projectVersions:(NSString *)projectID
                 source:(NSInteger)source
             completion:(void (^)(NSArray *, NSError *_Nullable))completion;
/// Searches multiplayer servers.
- (void)searchServers:(NSDictionary *)filters
               source:(NSInteger)source
           completion:(void (^)(NSArray *, NSError *_Nullable))completion;
/// Installs a project into a profile.
- (void)installProject:(NSDictionary *)data
               profile:(NSString *)profile
              progress:(void (^)(double, NSString *))progress
            completion:(void (^)(NSError *_Nullable))completion;
/// Imports a modpack into a profile.
- (void)importPack:(NSURL *)url
           profile:(NSString *_Nullable)profile
          progress:(void (^)(double, NSString *))progress
        completion:(void (^)(NSError *_Nullable))completion;
/// Returns Air's controls editor.
- (UIViewController *)controlsEditor;
/// Returns Air's Forge installer for an instance.
- (UIViewController *)forgeInstaller:(NSString *)instanceID;
@end
NS_ASSUME_NONNULL_END
