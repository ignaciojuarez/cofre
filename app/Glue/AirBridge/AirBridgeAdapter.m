#import "AirBridgeAdapter.h"
#import "PLProfiles.h"
#import "WorldService.h"
#import "ModService.h"
#import "ModItem.h"
#import "ServerService.h"
#import "ServerItem.h"
#import "WorldItem.h"
#import "installer/modpack/ModrinthAPI.h"
#import "installer/modpack/CurseForgeAPI.h"
#import "ModpackImportService.h"
#import "CustomControlsViewController.h"
#import "installer/ForgeInstallViewController.h"
#import "LauncherPreferences.h"
#import "JavaLauncher.h"
#import "LauncherPreferences.h"

@implementation CofreAirBridgeAdapter
- (instancetype)init { if ((self=[super init])) { _profiles=[PLProfiles current]; NSLog(@"[Cofre] AirBridge connected profiles=%lu", (unsigned long)_profiles.profiles.count); } return self; }
- (NSString *)selectedProfileName { return _profiles.selectedProfileName ?: @""; }
- (NSArray<NSDictionary *> *)instances { NSMutableArray *out=[NSMutableArray array]; [_profiles.profiles enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSDictionary *profile, BOOL *stop){ [out addObject:@{ @"id":name, @"name":name, @"loader":profile[@"loader"] ?: @"vanilla", @"version":profile[@"lastVersionId"] ?: @"" }]; }]; NSLog(@"[Cofre] instances=%lu", (unsigned long)out.count); return out; }
- (void)worldsForProfile:(NSString *)profile completion:(void (^)(NSArray *))completion { [[WorldService sharedService] scanWorldsForProfile:profile completion:^(NSArray *items){ NSLog(@"[Cofre] worlds profile=%@ count=%lu",profile,(unsigned long)items.count); if(completion) completion(items); }]; }
- (void)deleteWorld:(NSString *)worldID forProfile:(NSString *)profile completion:(void (^)(NSError * _Nullable))completion {
    [[WorldService sharedService] scanWorldsForProfile:profile completion:^(NSArray *items) {
        WorldItem *found = nil;
        for (WorldItem *item in items) if ([item.worldName isEqualToString:worldID] || [item.displayName isEqualToString:worldID]) { found = item; break; }
        if (!found) { if (completion) completion([NSError errorWithDomain:@"CofreAir" code:404 userInfo:@{NSLocalizedDescriptionKey:@"World not found"}]); return; }
        NSError *error = nil;
        [[WorldService sharedService] deleteWorld:found error:&error];
        if (completion) completion(error);
    }];
}
- (void)addServer:(NSString *)address name:(NSString *)name forProfile:(NSString *)profile completion:(void (^)(NSError * _Nullable))completion { NSError *error = nil; [[ServerService sharedService] joinServer:address forProfile:profile error:&error]; if (completion) completion(error); }
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
- (void)searchProjects:(NSDictionary *)filters source:(NSInteger)source completion:(void (^)(NSArray *, NSError *))completion { if (source == 2 && ![CurseForgeAPI isAPIKeyConfigured]) { if(completion) completion(@[], [NSError errorWithDomain:@"CofreAir" code:401 userInfo:@{NSLocalizedDescriptionKey:@"CurseForge requires an API key"}]); return; } id api=source==2?[CurseForgeAPI sharedInstance]:[ModrinthAPI sharedInstance]; [api searchModWithFilters:filters completion:completion]; }
- (void)projectVersions:(NSString *)projectID source:(NSInteger)source completion:(void (^)(NSArray *, NSError *))completion { id api=source==2?[CurseForgeAPI sharedInstance]:[ModrinthAPI sharedInstance]; [api getVersionsForModWithID:projectID completion:completion]; }
- (void)searchServers:(NSDictionary *)filters source:(NSInteger)source completion:(void (^)(NSArray *, NSError *))completion { [[ServerService sharedService] searchServersWithAPI:(source==2?ServerDownloadAPICurseForge:ServerDownloadAPIModrinth) filters:filters completion:^(NSArray<ServerItem *> *items,NSError *error){ NSMutableArray *out=[NSMutableArray array]; for(ServerItem *s in items) [out addObject:@{@"id":s.serverID?:@"",@"title":s.title?:@"",@"description":s.serverDescription?:@"",@"address":s.serverAddress?:@"",@"downloads":s.downloads?:@0,@"author":s.author?:@"",@"source":@(s.apiSource)}]; if(completion) completion(error ? nil : out,error); }]; }
- (void)installProject:(NSDictionary *)data profile:(NSString *)profile progress:(void (^)(double, NSString *))progress completion:(void (^)(NSError *))completion { ModItem *item=[[ModItem alloc] initWithOnlineData:data]; item.selectedVersionDownloadURL=data[@"downloadURL"]; item.version=data[@"version"]; [[ModService sharedService] downloadMod:item toProfile:profile progress:^(NSProgress *p){ if(progress) progress(p.fractionCompleted,@"Downloading"); } completion:completion]; }
- (void)importPack:(NSURL *)url profile:(NSString *)profile progress:(void (^)(double, NSString *))progress completion:(void (^)(NSError *))completion { ModpackImportService *service=[ModpackImportService new]; NSError *error=nil; NSDictionary *info=[service parseModpackAtURL:url error:&error]; BOOL ok=info && [service importModpack:info progress:progress error:&error]; if(completion) { if (!ok && !error) error = [NSError errorWithDomain:@"CofreAir" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Air import failed"}]; completion(ok ? nil : error); } }
- (UIViewController *)controlsEditor { return [CustomControlsViewController new]; }
- (UIViewController *)forgeInstaller:(NSString *)instanceID { return [ForgeInstallViewController new]; }
@end

UIViewController *CofreMakeControlsEditor(void) { return [[CofreAirBridgeAdapter new] controlsEditor]; }
UIViewController *CofreMakeForgeInstaller(const char *instanceID) { return [[CofreAirBridgeAdapter new] forgeInstaller:[NSString stringWithUTF8String:instanceID ?: ""]]; }
