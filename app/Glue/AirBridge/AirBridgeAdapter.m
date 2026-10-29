#import "AirBridgeAdapter.h"
#import "PLProfiles.h"
#import "WorldService.h"
#import "ModService.h"
#import "ModItem.h"
#import "ServerService.h"
#import "ServerItem.h"
#import "WorldItem.h"
#import "LauncherPreferences.h"
#import "JavaLauncher.h"
#import "LauncherPreferences.h"

@implementation CofreAirBridgeAdapter
- (instancetype)init { if ((self=[super init])) { _profiles=[PLProfiles current]; NSLog(@"[Cofre] AirBridge connected profiles=%lu", (unsigned long)_profiles.profiles.count); } return self; }
- (NSArray<NSDictionary *> *)instances { NSMutableArray *out=[NSMutableArray array]; [_profiles.profiles enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSDictionary *profile, BOOL *stop){ [out addObject:@{ @"id":name, @"name":name, @"loader":profile[@"loader"] ?: @"vanilla", @"version":profile[@"lastVersionId"] ?: @"" }]; }]; NSLog(@"[Cofre] instances=%lu", (unsigned long)out.count); return out; }
- (void)worldsForProfile:(NSString *)profile completion:(void (^)(NSArray *))completion { [[WorldService sharedService] scanWorldsForProfile:profile completion:^(NSArray *items){ NSLog(@"[Cofre] worlds profile=%@ count=%lu",profile,(unsigned long)items.count); if(completion) completion(items); }]; }
- (BOOL)deleteWorld:(NSString *)worldID forProfile:(NSString *)profile error:(NSError **)error {
    __block WorldItem *found = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[WorldService sharedService] scanWorldsForProfile:profile completion:^(NSArray *items) {
        for (WorldItem *item in items) if ([item.worldName isEqualToString:worldID] || [item.displayName isEqualToString:worldID]) { found = item; break; }
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (!found) { if (error) *error = [NSError errorWithDomain:@"CofreAir" code:404 userInfo:@{NSLocalizedDescriptionKey:@"World not found"}]; return NO; }
    return [[WorldService sharedService] deleteWorld:found error:error];
}
- (BOOL)addServer:(NSString *)address name:(NSString *)name forProfile:(NSString *)profile error:(NSError **)error {
    return [[ServerService sharedService] joinServer:address forProfile:profile error:error];
}
- (void)modsForProfile:(NSString *)profile completion:(void (^)(NSArray *))completion { [[ModService sharedService] scanModsForProfile:profile completion:^(NSArray *mods){ NSLog(@"[Cofre] mods profile=%@ count=%lu",profile,(unsigned long)mods.count); if(completion) completion(mods); }]; }
- (BOOL)toggleMod:(ModItem *)mod error:(NSError **)error { BOOL ok=[[ModService sharedService] toggleEnableForMod:mod error:error]; NSLog(@"[Cofre] mod toggle=%d",ok); return ok; }
- (NSArray<NSDictionary *> *)accounts { NSString *dir=[NSString stringWithFormat:@"%s/accounts",getenv("POJAV_HOME") ?: ""]; NSArray *files=[[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil]; NSMutableArray *out=[NSMutableArray array]; for(NSString *f in files) if([f.pathExtension isEqualToString:@"json"]) [out addObject:@{ @"id":f.stringByDeletingPathExtension, @"name":f.stringByDeletingPathExtension }]; NSLog(@"[Cofre] accounts=%lu",(unsigned long)out.count); return out; }
- (void)ensureAutomaticMemoryDefault {
    // The sentinel distinguishes first launch from a user who explicitly chose a fixed heap.
    if (getPrefObject(@"cofre.memory_default_applied") == nil) {
        setPrefBool(@"java.auto_ram", YES);
        setPrefBool(@"cofre.memory_default_applied", YES);
        NSLog(@"[Cofre] memory auto default enabled");
    }
    NSLog(@"[Cofre] memory auto ceiling=%dMB", ame141_currentLaunchAllocMem());
}
- (id)preferenceObject:(NSString *)key { return getPrefObject(key); }
- (void)setPreferenceObject:(NSString *)key value:(id)value { setPrefObject(key, value); }
- (NSDictionary *)preferencesForProfile:(NSString *)profile { return @{ @"ramMB":@(ame141_currentLaunchAllocMem()), @"renderer":getPrefObject(@"renderer") ?: @"Auto", @"resolution":@(getPrefFloat(@"resolution")), @"fsr":@(getPrefBool(@"fsr1.enable")), @"java":getPrefObject(@"javaVersion") ?: @"auto", @"jvmArgs":getPrefObject(@"javaArgs") ?: @"" }; }
- (void)launchProfile:(NSString *)profile accountID:(NSString *)accountID progress:(void (^)(NSString *))progress { [_profiles setSelectedProfileName:profile]; if(progress) progress(@"preparing"); NSDictionary *p=[_profiles selectedProfile]; NSString *version=p[@"lastVersionId"]; NSLog(@"[Cofre] launch profile=%@ version=%@",profile,version); if(progress) progress(@"starting"); int rc=launchJVM(accountID, p, 0, 0, 8); NSLog(@"[Cofre] launch result=%d",rc); if(progress) progress(rc==0?@"running":@"failed"); }
@end
