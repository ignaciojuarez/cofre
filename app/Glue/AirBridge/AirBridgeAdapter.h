#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
@class PLProfiles;
NS_ASSUME_NONNULL_BEGIN
@interface CofreAirBridgeAdapter : NSObject
@property(nonatomic, readonly) PLProfiles *profiles;
- (NSArray<NSDictionary *> *)instances;
- (void)worldsForProfile:(NSString *)profile completion:(void (^)(NSArray *))completion;
- (BOOL)deleteWorld:(NSString *)worldID forProfile:(NSString *)profile error:(NSError **)error;
- (BOOL)addServer:(NSString *)address name:(NSString *)name forProfile:(NSString *)profile error:(NSError **)error;
- (void)modsForProfile:(NSString *)profile completion:(void (^)(NSArray *))completion;
- (BOOL)toggleMod:(id)mod error:(NSError **)error;
- (NSArray<NSDictionary *> *)accounts;
- (id)preferenceObject:(NSString *)key;
- (void)setPreferenceObject:(NSString *)key value:(id)value;
- (NSDictionary *)preferencesForProfile:(NSString *)profile;
- (void)ensureAutomaticMemoryDefault;
- (void)launchProfile:(NSString *)profile accountID:(nullable NSString *)accountID progress:(void (^)(NSString *stage))progress;
- (void)searchProjects:(NSDictionary *)filters source:(NSInteger)source completion:(void (^)(NSArray *, NSError * _Nullable))completion;
- (void)projectVersions:(NSString *)projectID source:(NSInteger)source completion:(void (^)(NSArray *, NSError * _Nullable))completion;
- (void)searchServers:(NSDictionary *)filters source:(NSInteger)source completion:(void (^)(NSArray *, NSError * _Nullable))completion;
- (void)installProject:(NSDictionary *)data profile:(NSString *)profile progress:(void (^)(double, NSString *))progress completion:(void (^)(NSError * _Nullable))completion;
- (void)importPack:(NSURL *)url profile:(NSString * _Nullable)profile progress:(void (^)(double, NSString *))progress completion:(void (^)(NSError * _Nullable))completion;
- (UIViewController *)controlsEditor;
- (UIViewController *)forgeInstaller:(NSString *)instanceID;
@end
NS_ASSUME_NONNULL_END
