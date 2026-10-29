#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
@protocol CofreAirBridging <NSObject>
- (NSArray<NSDictionary *> *)instances;
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
- (id)preferenceObject:(NSString *)key;
- (void)setPreferenceObject:(NSString *)key value:(id)value;
- (NSDictionary *)preferencesForProfile:(NSString *)profile;
- (void)ensureAutomaticMemoryDefault;
- (void)launchProfile:(NSString *)profile
            accountID:(nullable NSString *)accountID
             progress:(void (^)(NSString *))progress;
- (void)searchProjects:(NSDictionary *)filters
                source:(NSInteger)source
            completion:(void (^)(NSArray *, NSError *_Nullable))completion;
- (void)projectVersions:(NSString *)projectID
                 source:(NSInteger)source
             completion:(void (^)(NSArray *, NSError *_Nullable))completion;
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
- (UIViewController *)forgeInstaller:(NSString *)instanceID;
@end
NS_ASSUME_NONNULL_END
