#import <Foundation/Foundation.h>
@class PLProfiles;
NS_ASSUME_NONNULL_BEGIN
@interface CofreAirBridgeAdapter : NSObject
@property(nonatomic, readonly) PLProfiles *profiles;
- (NSArray<NSDictionary *> *)instances;
- (void)worldsForProfile:(NSString *)profile completion:(void (^)(NSArray *))completion;
- (void)modsForProfile:(NSString *)profile completion:(void (^)(NSArray *))completion;
- (BOOL)toggleMod:(id)mod error:(NSError **)error;
- (NSArray<NSDictionary *> *)accounts;
- (NSDictionary *)preferencesForProfile:(NSString *)profile;
- (void)launchProfile:(NSString *)profile accountID:(nullable NSString *)accountID progress:(void (^)(NSString *stage))progress;
@end
NS_ASSUME_NONNULL_END
