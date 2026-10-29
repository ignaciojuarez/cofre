#import "AirBridgeAdapter.h"
#import "CustomControlsViewController.h"
#import "DownloadTaskManager.h"
#import "JavaLauncher.h"
#import "LauncherPreferences.h"
#import "MinecraftResourceDownloadTask.h"
#import "ModItem.h"
#import "ModService.h"
#import "ModpackExportService.h"
#import "ModpackImportService.h"
#import "PLMirrorCenter.h"
#import "PLProfiles.h"
#import "ServerItem.h"
#import "ServerService.h"
#import "AmeLaunchProgress.h"
#import "SurfaceViewController.h"
#import "UIKit+hook.h"
#import "WorldItem.h"
#import "WorldService.h"
#import "authenticator/BaseAuthenticator.h"
#import "installer/FabricUtils.h"
#import "installer/ForgeDirectInstaller.h"
#import "installer/NeoForgeDirectInstaller.h"
#import "installer/NeoForgeVersionFetcher.h"
#import "installer/modpack/CurseForgeAPI.h"
#import "installer/modpack/ModrinthAPI.h"
#import "ios_uikit_bridge.h"
#import "utils.h"
#import <AuthenticationServices/AuthenticationServices.h>

static NSError *CofreAirError(NSString *message) {
  return [NSError errorWithDomain:@"CofreAir"
                             code:1
                         userInfo:@{NSLocalizedDescriptionKey : message}];
}

@interface CofreAirBridgeAdapter () <
    ASWebAuthenticationPresentationContextProviding>
@property(nonatomic, strong, nullable) ASWebAuthenticationSession *authSession;
@end

extern NSMutableArray<NSDictionary *> *remoteVersionList;

static UIWindow *cofreLaunchOverlayWindow;

static void CofreHideAirOverlay(SurfaceViewController *surface) {
  UIView *airOverlay = [surface valueForKey:@"launchOverlayView"];
  airOverlay.hidden = YES;
  airOverlay.alpha = 0;
  UIButton *cancel = [surface valueForKey:@"launchCancelButton"];
  cancel.hidden = YES;
  cancel.enabled = NO;
}

static void CofrePresentSurface(UIWindow *window, NSDictionary *metadata) {
  // As UIKit_launchMinecraftSurfaceVC does: remember who played last.
  BaseAuthenticator *account = BaseAuthenticator.current;
  setPrefObject(@"internal.selected_account", account.authData[@"accountId"]);
  dispatch_async(dispatch_get_main_queue(), ^{
    UIViewController *launcher = window.rootViewController;
    UIWindow *overlay = [[UIWindow alloc] initWithWindowScene:window.windowScene];
    overlay.frame = window.bounds;
    overlay.windowLevel = window.windowLevel + 1;
    overlay.rootViewController = launcher;
    overlay.hidden = NO;
    [overlay makeKeyAndVisible];
    cofreLaunchOverlayWindow = overlay;

    SurfaceViewController *surface = [[SurfaceViewController alloc] initWithMetadata:metadata];
    window.alpha = 0;
    window.rootViewController = surface;
    [window makeKeyAndVisible];
    [UIView animateWithDuration:0.2 animations:^{ window.alpha = 1; }];

    // SurfaceViewController creates these private views during init/viewDidLoad.
    // Repeat briefly so Air's own spinner and Cancel button never flash through.
    for (NSNumber *delay in @[@0, @0.05, @0.2, @0.5, @1.0]) {
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                     dispatch_get_main_queue(), ^{ CofreHideAirOverlay(surface); });
    }
    NSLog(@"[Cofre] launch surface presented with Cofre overlay");
  });
}

static void CofreFinishSurface(UIWindow *window) {
  dispatch_async(dispatch_get_main_queue(), ^{
    UIWindow *overlay = cofreLaunchOverlayWindow;
    cofreLaunchOverlayWindow = nil;
    if (!overlay) return;
    [UIView animateWithDuration:0.25 animations:^{ overlay.alpha = 0; } completion:^(BOOL finished) {
      overlay.hidden = YES;
      [overlay resignKeyWindow];
      overlay.rootViewController = nil;
      [window makeKeyAndVisible];
      NSLog(@"[Cofre] launch overlay dismissed after first frame");
    }];
  });
}

// Air fills remoteVersionList from its own launcher screens, which Cofre never
// shows; load it the same way once. Offline it stays empty and Air falls back
// to local files.
static void CofreLoadVersionList(void (^done)(void)) {
  if (remoteVersionList.count > 2) {
    done();
    return;
  }
  NSString *url =
      [getPrefObject(@"general.download_source") isEqual:@"bmclapi"]
          ? @"https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json"
          : @"https://piston-meta.mojang.com/mc/game/version_manifest_v2.json";
  [[NSURLSession.sharedSession
        dataTaskWithURL:[NSURL URLWithString:url]
      completionHandler:^(NSData *data, NSURLResponse *response,
                          NSError *error) {
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data
                                                                    options:0
                                                                      error:nil]
                                  : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
          remoteVersionList = [NSMutableArray arrayWithArray:@[
            @{@"id" : @"latest-release", @"type" : @"release"},
            @{@"id" : @"latest-snapshot", @"type" : @"snapshot"}
          ]];
          if ([json[@"versions"] isKindOfClass:NSArray.class]) {
            [remoteVersionList addObjectsFromArray:json[@"versions"]];
            setPrefObject(@"internal.latest_version", json[@"latest"]);
          }
          done();
        });
      }] resume];
}

@implementation CofreAirBridgeAdapter
- (instancetype)init {
  if ((self = [super init])) {
    _profiles = [PLProfiles current];
    // Cofre shows its own progress: stop Air's download tasks from popping up
    // their progress page. The notification is posted, synchronously, just
    // before Air checks autoPresentDetail.
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      [NSNotificationCenter.defaultCenter
          addObserverForName:DownloadTaskManagerDidUpdateTaskNotification
                      object:nil
                       queue:nil
                  usingBlock:^(NSNotification *note) {
                    DownloadTaskItem *item =
                        note.userInfo[DownloadTaskManagerTaskKey];
                    item.autoPresentDetail = NO;
                  }];
    });
    NSLog(@"[Cofre] AirBridge connected profiles=%lu",
          (unsigned long)_profiles.profiles.count);
  }
  return self;
}
- (NSString *)selectedProfileName {
  return _profiles.selectedProfileName ?: @"";
}

#pragma mark - Instances

- (NSDictionary *)instanceSummary:(NSString *)name {
  NSDictionary *profile = _profiles.profiles[name];
  if (!profile)
    return nil;
  NSDictionary *parsed =
      [ModpackExportService parseVersionId:profile[@"lastVersionId"] ?: @""];
  return @{@"id": name, @"name": profile[@"name"] ?: name,
           @"version": profile[@"cofreGameVersion"] ?: parsed[@"minecraft"] ?: profile[@"lastVersionId"] ?: @"",
           @"loader": profile[@"cofreRequestedLoader"] ?: parsed[@"loader"] ?: @"vanilla",
           @"loaderVersion": profile[@"loaderVersion"] ?: parsed[@"loaderVersion"] ?: @"",
           @"fabricAPI": profile[@"cofreInstallFabricAPI"] ?: @NO,
           @"ownFolder": @(![amePCLVersionGameDirSubpath(profile, nil) isEqualToString:@"."])};
}

static NSData *CofreDownloadInstaller(NSString *urlString, NSError **error) {
  NSURL *url = [NSURL URLWithString:urlString];
  if (!url) {
    if (error)
      *error = CofreAirError(@"The loader installer URL is invalid.");
    return nil;
  }
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  request.timeoutInterval = 60.0;
  request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
  [request setValue:@"Cofre/1.0" forHTTPHeaderField:@"User-Agent"];
  [request setValue:@"application/java-archive,*/*;q=0.9"
      forHTTPHeaderField:@"Accept"];
  __block NSData *data = nil;
  __block NSError *requestError = nil;
  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
  NSURLSessionDataTask *task = [[NSURLSession sharedSession]
      dataTaskWithRequest:request
        completionHandler:^(NSData *responseData, NSURLResponse *response,
                            NSError *error) {
          if (error) {
            requestError = error;
          } else if (![response isKindOfClass:NSHTTPURLResponse.class] ||
                     [(NSHTTPURLResponse *)response statusCode] < 200 ||
                     [(NSHTTPURLResponse *)response statusCode] >= 300) {
            NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class]
                                   ? [(NSHTTPURLResponse *)response statusCode]
                                   : 0;
            requestError = CofreAirError(
                [NSString stringWithFormat:
                              @"Loader installer download failed (HTTP %ld).",
                              (long)status]);
          } else {
            data = responseData;
          }
          dispatch_semaphore_signal(semaphore);
        }];
  [task resume];
  if (dispatch_semaphore_wait(
          semaphore, dispatch_time(DISPATCH_TIME_NOW, 70 * NSEC_PER_SEC))) {
    [task cancel];
    if (error)
      *error = CofreAirError(@"The loader installer download timed out.");
    return nil;
  }
  if (!data.length) {
    if (error)
      *error =
          requestError
              ?: CofreAirError(@"The loader installer download was empty.");
    return nil;
  }
  return data;
}

- (NSArray<NSDictionary *> *)instances {
  NSMutableArray *out = [NSMutableArray array];
  for (NSString *name in [_profiles.profiles.allKeys
           sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
    [out addObject:[self instanceSummary:name]];
  }
  return out;
}

- (NSArray<NSURL *> *)instanceMetadataURLs:(NSURL *)url
                                  resource:(NSInteger)resource {
  return [PLMirrorCenter
      candidateURLsForOriginalURL:url
                     resourceType:(PLMirrorResourceType)resource];
}

- (NSArray<NSURL *> *)loaderProfileURLs:(NSString *)loader
                                   game:(NSString *)game
                                version:(NSString *)version {
  return [FabricUtils
      candidateURLsForVendor:[loader isEqualToString:@"quilt"] ? @"Quilt"
                                                               : @"Fabric"
            minecraftVersion:game
               loaderVersion:version];
}

- (void)neoForgeVersions:(NSString *)game
              completion:
                  (void (^)(NSArray<NSString *> *, NSError *))completion {
  [NeoForgeVersionFetcher fetchVersionsForGameVersion:game
                                           completion:completion];
}

// Write a proposed snapshot before changing the in-memory profiles;
// PLProfiles.save does not return disk errors. Use Air's JSON writer and its
// selection notification.
- (BOOL)persistInstanceProfiles:(NSMutableDictionary *)profiles
                       selected:(NSString *)selected
                          error:(NSError **)error {
  NSMutableDictionary *snapshot = [_profiles.profileDict mutableCopy];
  snapshot[@"profiles"] = profiles;
  snapshot[@"selectedProfile"] = selected ?: @"";
  NSError *writeError = saveJSONToFile(snapshot, _profiles.profilePath);
  if (writeError) {
    if (error)
      *error = writeError;
    return NO;
  }
  _profiles.profileDict = snapshot;
  [[NSNotificationCenter defaultCenter]
      postNotificationName:@"SelectedProfileChanged"
                    object:selected];
  return YES;
}

- (NSDictionary *)createProfile:(NSString *)name
                        version:(NSString *)version
                         loader:(NSString *)loader
                      ownFolder:(BOOL)ownFolder
                      fabricAPI:(BOOL)fabricAPI
                          error:(NSError **)error {
  name = [name
      stringByTrimmingCharactersInSet:NSCharacterSet
                                          .whitespaceAndNewlineCharacterSet];
  if (!name.length || !version.length || _profiles.profiles[name]) {
    if (error)
      *error = CofreAirError(!name.length ? @"Enter an instance name."
                             : _profiles.profiles[name]
                                 ? @"An instance with this name already exists."
                                 : @"Choose a Minecraft version.");
    return nil;
  }
  if (!getenv("POJAV_GAME_DIR")) {
    if (error)
      *error = CofreAirError(@"Air's game directory is not ready.");
    return nil;
  }
  NSMutableDictionary *profile = [@{
    @"name" : name,
    @"lastVersionId" : version,
    @"cofreGameVersion" : version,
    @"cofreRequestedLoader" : loader,
    @"cofreInstallFabricAPI" : @(fabricAPI),
    @"type" : @"custom",
    @"versionIsolation" : @"0",
    @"gameDir" : ownFolder
        ? [@"cofre-instances/" stringByAppendingString:[NSUUID UUID].UUIDString]
        : @"."
  } mutableCopy];
  NSString *directory = amePCLVersionGameDirAbsolute(profile, nil);
  if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:error])
    return nil;
  NSMutableDictionary *profiles = [_profiles.profiles mutableCopy];
  profiles[name] = profile;
  if (![self persistInstanceProfiles:profiles selected:name error:error]) {
    if (ownFolder)
      [[NSFileManager defaultManager] removeItemAtPath:directory error:nil];
    return nil;
  }
  NSLog(@"[Cofre] instance created %@ Minecraft %@", name, version);
  return [self instanceSummary:name];
}

- (BOOL)saveLoaderProfile:(NSDictionary *)json
               forProfile:(NSString *)name
                   loader:(NSString *)loader
                  version:(NSString *)version
                    error:(NSError **)error {
  NSMutableDictionary *profile = [_profiles.profiles[name] mutableCopy];
  NSString *versionID =
      [json[@"id"] isKindOfClass:NSString.class] ? json[@"id"] : nil;
  NSCharacterSet *invalid = [[NSCharacterSet
      characterSetWithCharactersInString:
          @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-+"]
      invertedSet];
  if (!profile || !versionID.length ||
      [versionID rangeOfCharacterFromSet:invalid].location != NSNotFound ||
      [versionID isEqualToString:@"."] || [versionID isEqualToString:@".."]) {
    if (error)
      *error = CofreAirError(@"The instance or loader profile is invalid.");
    return NO;
  }
  NSString *path = [NSString stringWithFormat:@"%s/versions/%@/%@.json",
                                              getenv("POJAV_GAME_DIR"),
                                              versionID, versionID];
  if (![NSFileManager.defaultManager
                createDirectoryAtPath:path.stringByDeletingLastPathComponent
          withIntermediateDirectories:YES
                           attributes:nil
                                error:error])
    return NO;
  NSError *writeError = saveJSONToFile(json, path);
  if (writeError) {
    if (error)
      *error = writeError;
    return NO;
  }
  profile[@"lastVersionId"] = versionID;
  profile[@"loader"] = loader;
  profile[@"loaderVersion"] = version;
  NSMutableDictionary *profiles = [_profiles.profiles mutableCopy];
  profiles[name] = profile;
  return [self persistInstanceProfiles:profiles
                              selected:_profiles.selectedProfileName
                                 error:error];
}

- (void)installInstanceMod:(NSDictionary *)file
                forProfile:(NSString *)profile
                completion:(void (^)(NSError *))completion {
  NSString *filename = file[@"filename"];
  if (![filename isKindOfClass:NSString.class] || !filename.length ||
      ![filename.lastPathComponent isEqualToString:filename] ||
      ![filename.pathExtension isEqualToString:@"jar"] ||
      !_profiles.profiles[profile]) {
    completion(CofreAirError(@"Invalid Fabric API download."));
    return;
  }
  ModItem *item = [[ModItem alloc]
      initWithOnlineData:@{@"id" : @"fabric-api", @"title" : @"Fabric API"}];
  item.fileName = filename;
  item.selectedVersionDownloadURL = file[@"url"];
  [[ModService sharedService] downloadMod:item
                                toProfile:profile
                             expectedSHA1:file[@"hashes"][@"sha1"]
                                 progress:nil
                               completion:completion];
}

- (void)duplicateProfile:(NSString *)name
              completion:(void (^)(NSDictionary *, NSError *))completion {
  NSDictionary *original = [_profiles.profiles[name] copy];
  if (!original) {
    completion(nil, CofreAirError(@"Instance not found."));
    return;
  }
  NSString *source = amePCLVersionGameDirAbsolute(original, nil);
  NSMutableDictionary *copy = [original mutableCopy];
  copy[@"gameDir"] =
      [@"cofre-instances/" stringByAppendingString:[NSUUID UUID].UUIDString];
  NSString *destination = amePCLVersionGameDirAbsolute(copy, nil);
  // Copy gameplay data only: copying a shared root would recursively copy the
  // destination, other instances, assets and account/launcher configuration.
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSError *error = nil;
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL ok = [fm createDirectoryAtPath:destination
            withIntermediateDirectories:YES
                             attributes:nil
                                  error:&error];
    NSArray *paths = [[ModpackExportService
        overrideDirectoriesForOptions:ModpackExportFileAll]
        arrayByAddingObjectsFromArray:
            [ModpackExportService
                overrideFilesForOptions:ModpackExportFileAll]];
    for (NSString *path in paths) {
      if (!ok)
        break;
      if ([path isEqualToString:@"launcher_profiles.json"])
        continue;
      NSString *from = [source stringByAppendingPathComponent:path];
      if ([fm fileExistsAtPath:from]) {
        NSString *to = [destination stringByAppendingPathComponent:path];
        [fm createDirectoryAtPath:to.stringByDeletingLastPathComponent
            withIntermediateDirectories:YES
                             attributes:nil
                                  error:&error];
        if (!error)
          ok = [fm copyItemAtPath:from toPath:to error:&error];
      }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      if (ok) {
        NSString *newName = [name stringByAppendingString:@" copy"];
        for (NSUInteger i = 2; self.profiles.profiles[newName]; i++)
          newName = [NSString
              stringWithFormat:@"%@ copy %lu", name, (unsigned long)i];
        copy[@"name"] = newName;
        NSMutableDictionary *profiles = [self.profiles.profiles mutableCopy];
        profiles[newName] = copy;
        NSError *saveError = nil;
        if ([self persistInstanceProfiles:profiles
                                 selected:self.profiles.selectedProfileName
                                    error:&saveError]) {
          completion([self instanceSummary:newName], nil);
          return;
        }
        [fm removeItemAtPath:destination error:nil];
        completion(nil, saveError);
      } else {
        [fm removeItemAtPath:destination error:nil];
        completion(nil,
                   error ?: CofreAirError(@"Could not copy the instance."));
      }
    });
  });
}

- (BOOL)deleteProfile:(NSString *)name error:(NSError **)error {
  if (!_profiles.profiles[name]) {
    if (error)
      *error = CofreAirError(@"Instance not found.");
    return NO;
  }
  // Match Air's profile deletion: keep shared versions, worlds and game
  // folders.
  NSMutableDictionary *profiles = [_profiles.profiles mutableCopy];
  [profiles removeObjectForKey:name];
  NSString *selected = _profiles.selectedProfileName;
  if ([selected isEqualToString:name])
    selected = [profiles.allKeys sortedArrayUsingSelector:@selector(compare:)]
                       .firstObject
                   ?: @"";
  return [self persistInstanceProfiles:profiles selected:selected error:error];
}

- (void)exportProfile:(NSString *)name
               format:(NSString *)format
           completion:(void (^)(NSURL *, NSError *))completion {
  if (!_profiles.profiles[name] ||
      ![@[ @"zip", @"mrpack" ] containsObject:format]) {
    completion(nil, CofreAirError(@"Invalid instance or export format."));
    return;
  }
  NSString *path = [NSTemporaryDirectory()
      stringByAppendingPathComponent:
          [[NSUUID UUID].UUIDString stringByAppendingPathExtension:format]];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSError *error = nil;
    ModpackExportService *service = [ModpackExportService new];
    BOOL ok =
        [service exportModpackForProfile:name
                                  toPath:path
                                    name:name
                                 version:@"1.0.0"
                                  author:@""
                                  format:[format isEqualToString:@"mrpack"]
                                             ? ModpackExportFormatModrinth
                                             : ModpackExportFormatPlainZip
                             fileOptions:ModpackExportFileDefault |
                                         ModpackExportFileSaves
                                progress:nil
                                   error:&error];
    if (!ok)
      [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    completion(ok ? [NSURL fileURLWithPath:path] : nil, ok ? nil : error ?: CofreAirError(@"Air could not export this instance."));
  });
}

// Installs the Forge/NeoForge version picked in Cofre: downloads its official
// installer and runs Air's direct installer (no Java, no second screen).
- (void)installForgeLoader:(NSString *)loader
                forProfile:(NSString *)name
                   version:(NSString *)version
                  progress:(void (^)(double, NSString *))progress
                completion:(void (^)(NSError *_Nullable))completion {
  void (^done)(NSError *) = ^(NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(error);
    });
  };
  NSDictionary *profile = _profiles.profiles[name];
  NSString *game = profile[@"cofreGameVersion"] ?: profile[@"lastVersionId"];
  BOOL neo = [loader isEqualToString:@"neoforge"];
  if (!profile || !game.length || !version.length) {
    done(CofreAirError(@"The instance or loader version is invalid."));
    return;
  }
  // Same Maven paths as Air's ForgeInstallViewController: Forge uses
  // "<mc>-<forge>", NeoForge the bare version (1.20.1 builds under forge/).
  NSString *full =
      !neo && ![version hasPrefix:[game stringByAppendingString:@"-"]]
          ? [NSString stringWithFormat:@"%@-%@", game, version]
          : version;
  NSString *vendor = neo ? @"NeoForge" : @"Forge";
  NSString *versionID = [NSString stringWithFormat:@"%@-%@", vendor, full];
  BOOL mirror = [getPrefObject(@"general.download_source") isEqual:@"bmclapi"];
  NSString *host = mirror ? @"https://bmclapi2.bangbang93.com/maven"
                   : neo  ? @"https://maven.neoforged.net/releases"
                          : @"https://maven.minecraftforge.net";
  NSString *artifact =
      !neo ? @"net/minecraftforge/forge/%1$@/forge-%1$@-installer.jar"
      : ([full hasPrefix:@"47."] || [full containsString:@"1.20.1"])
          ? @"net/neoforged/forge/%1$@/forge-%1$@-installer.jar"
          : @"net/neoforged/neoforge/%1$@/neoforge-%1$@-installer.jar";
  NSURL *url = [NSURL
      URLWithString:[NSString
                        stringWithFormat:@"%@/%@", host,
                                         [NSString
                                             stringWithFormat:artifact, full]]];
  NSString *jar = [NSTemporaryDirectory()
      stringByAppendingPathComponent:
          [NSString stringWithFormat:@"%@-installer-%@.jar", vendor,
                                     NSUUID.UUID.UUIDString]];
  if (progress)
    progress(
        0, [NSString stringWithFormat:@"Downloading the %@ installer", vendor]);
  NSLog(@"[Cofre] loader download %@", url.absoluteString);
  [[NSURLSession.sharedSession
      downloadTaskWithURL:url
        completionHandler:^(NSURL *location, NSURLResponse *response,
                            NSError *error) {
          NSInteger status = [(NSHTTPURLResponse *)response statusCode];
          if (error || status != 200 ||
              ![NSFileManager.defaultManager moveItemAtPath:location.path
                                                     toPath:jar
                                                      error:&error]) {
            done(error && status == 200
                     ? error
                     : CofreAirError([NSString
                           stringWithFormat:@"Couldn't download the %@ %@ "
                                            @"installer (HTTP %ld).",
                                            vendor, version, (long)status]));
            return;
          }
          NSString *instanceDir = amePCLVersionGameDirAbsolute(profile, nil);
          void (^step)(double, NSString *) = ^(double p, NSString *message) {
            if (progress)
              dispatch_async(dispatch_get_main_queue(), ^{
                progress(p, message ?: @"");
              });
          };
          NSError *installError = nil;
          BOOL ok = neo ? [NeoForgeDirectInstaller
                              installNeoForgeFromInstaller:jar
                                                 versionId:versionID
                                             customGameDir:instanceDir
                                       skipRegisterVersion:YES
                                                  progress:step
                                                     error:&installError]
                        : [ForgeDirectInstaller
                              installForgeFromInstaller:jar
                                              versionId:versionID
                                          customGameDir:instanceDir
                                    skipRegisterVersion:YES
                                               progress:step
                                                  error:&installError];
          [NSFileManager.defaultManager removeItemAtPath:jar error:nil];
          dispatch_async(dispatch_get_main_queue(), ^{
            if (!ok) {
              completion(
                  installError
                      ?: CofreAirError(@"Air could not install this loader."));
              return;
            }
            NSMutableDictionary *updated =
                [self.profiles.profiles[name] mutableCopy];
            if (!updated) {
              completion(CofreAirError(
                  @"The instance was deleted during installation."));
              return;
            }
            updated[@"lastVersionId"] = versionID;
            updated[@"loader"] = loader;
            updated[@"loaderVersion"] = version;
            NSMutableDictionary *profiles =
                [self.profiles.profiles mutableCopy];
            profiles[name] = updated;
            NSError *saveError = nil;
            [self persistInstanceProfiles:profiles
                                 selected:name
                                    error:&saveError];
            NSLog(@"[Cofre] loader installed %@ ok=%d", versionID,
                  saveError == nil);
            completion(saveError);
          });
        }] resume];
}

#pragma mark - End instances

- (void)worldsForProfile:(NSString *)profile
              completion:(void (^)(NSArray *))completion {
  [[WorldService sharedService]
      scanWorldsForProfile:profile
                completion:^(NSArray *items) {
                  NSLog(@"[Cofre] worlds profile=%@ count=%lu", profile,
                        (unsigned long)items.count);
                  if (completion)
                    completion(items);
                }];
}
- (void)deleteWorld:(NSString *)worldID
         forProfile:(NSString *)profile
         completion:(void (^)(NSError *_Nullable))completion {
  [[WorldService sharedService]
      scanWorldsForProfile:profile
                completion:^(NSArray *items) {
                  WorldItem *found = nil;
                  for (WorldItem *item in items)
                    if ([item.worldName isEqualToString:worldID] ||
                        [item.displayName isEqualToString:worldID]) {
                      found = item;
                      break;
                    }
                  if (!found) {
                    if (completion)
                      completion([NSError errorWithDomain:@"CofreAir"
                                                     code:404
                                                 userInfo:@{
                                                   NSLocalizedDescriptionKey :
                                                       @"World not found"
                                                 }]);
                    return;
                  }
                  NSError *error = nil;
                  [[WorldService sharedService] deleteWorld:found error:&error];
                  if (completion)
                    completion(error);
                }];
}
- (void)addServer:(NSString *)address
             name:(NSString *)name
       forProfile:(NSString *)profile
       completion:(void (^)(NSError *_Nullable))completion {
  NSError *error = nil;
  [[ServerService sharedService] joinServer:address
                                 forProfile:profile
                                      error:&error];
  if (completion)
    completion(error);
}
- (void)modsForProfile:(NSString *)profile
            completion:(void (^)(NSArray *))completion {
  [[ModService sharedService]
      scanModsForProfile:profile
              completion:^(NSArray *mods) {
                NSLog(@"[Cofre] mods profile=%@ count=%lu", profile,
                      (unsigned long)mods.count);
                NSMutableArray *rows = [NSMutableArray array];
                for (ModItem *mod in mods) {
                  [rows addObject:@{@"id": mod.onlineID ?: mod.fileName ?: @"", @"name": mod.displayName ?: mod.fileName ?: @"",
                                    @"version": mod.version ?: @"", @"enabled": @(!mod.disabled)}];
                }
                if (completion)
                  completion(rows);
              }];
}
- (BOOL)toggleMod:(ModItem *)mod error:(NSError **)error {
  BOOL ok = [[ModService sharedService] toggleEnableForMod:mod error:error];
  NSLog(@"[Cofre] mod toggle=%d", ok);
  return ok;
}
- (NSArray<NSDictionary *> *)accounts {
  NSString *dir =
      [NSString stringWithFormat:@"%s/accounts", getenv("POJAV_HOME") ?: ""];
  NSArray *files =
      [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
  NSString *selected = getPrefObject(@"internal.selected_account");
  NSMutableArray *out = [NSMutableArray array];
  for (NSString *f in files) {
    if (![f.pathExtension isEqualToString:@"json"])
      continue;
    NSString *accountID = f.stringByDeletingPathExtension;
    NSData *data =
        [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:f]];
    id json = data ? [NSJSONSerialization JSONObjectWithData:data
                                                     options:0
                                                       error:nil]
                   : nil;
    NSString *name =
        [json isKindOfClass:NSDictionary.class] ? json[@"username"] : nil;
    [out addObject:@{
      @"id" : accountID,
      @"name" : [name isKindOfClass:NSString.class] ? name : accountID,
      @"active" : @([accountID isEqualToString:selected])
    }];
  }
  NSLog(@"[Cofre] accounts=%lu", (unsigned long)out.count);
  return out;
}
- (void)signInMicrosoftWithProgress:(void (^)(NSString *))progress
                         completion:(void (^)(NSDictionary *_Nullable,
                                              NSError *_Nullable))completion {
  // Same request as Air's account screen (AccountListViewController).
  NSURL *url = [NSURL
      URLWithString:
          @"https://login.live.com/"
          @"oauth20_authorize.srf?client_id=00000000402b5328&response_type="
          @"code&scope=service%3A%3Auser.auth.xboxlive.com%3A%3AMBI_SSL&"
          @"redirect_url=https%3A%2F%2Flogin.live.com%2Foauth20_desktop.srf"];
  __weak typeof(self) weakSelf = self;
  self.authSession = [[ASWebAuthenticationSession alloc]
            initWithURL:url
      callbackURLScheme:@"ms-xal-00000000402b5328"
      completionHandler:^(NSURL *callbackURL, NSError *error) {
        weakSelf.authSession = nil;
        NSString *code = nil;
        for (NSURLQueryItem *item in
             [NSURLComponents componentsWithURL:callbackURL
                        resolvingAgainstBaseURL:NO]
                 .queryItems)
          if ([item.name isEqualToString:@"code"])
            code = item.value;
        if (code.length == 0) {
          NSLog(@"[Cofre] sign-in cancelled or refused");
          completion(nil, CofreAirError(@"Sign-in didn't finish"));
          return;
        }
        [[[MicrosoftAuthenticator alloc] initWithInput:code]
            loginWithCallback:^(id status, BOOL success) {
              dispatch_async(dispatch_get_main_queue(), ^{
                BOOL demo = [status isKindOfClass:NSString.class] &&
                            [status isEqualToString:@"DEMO"];
                if (success && status && !demo) {
                  progress([status description]);
                  return;
                }
                if (!success) {
                  NSLog(@"[Cofre] sign-in failed");
                  completion(nil, [status isKindOfClass:NSError.class]
                                      ? status
                                      : CofreAirError(@"Sign-in failed"));
                  return;
                }
                NSDictionary *d = [[BaseAuthenticator current] authData];
                NSLog(@"[Cofre] signed in demo=%d", demo);
                completion(
                    @{
                      @"id" : d[@"accountId"] ?: @"",
                      @"name" : d[@"username"] ?: @"",
                      @"demo" : @(demo)
                    },
                    nil);
              });
            }];
      }];
  self.authSession.prefersEphemeralWebBrowserSession = YES;
  self.authSession.presentationContextProvider = self;
  if (![self.authSession start]) {
    self.authSession = nil;
    completion(nil, CofreAirError(@"Couldn't open the sign-in page"));
  }
}
- (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:
    (ASWebAuthenticationSession *)session {
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
    if ([scene isKindOfClass:UIWindowScene.class])
      for (UIWindow *window in ((UIWindowScene *)scene).windows)
        if (window.isKeyWindow)
          return window;
  return [UIWindow new];
}
- (void)ensureAutomaticMemoryDefault {
  // The sentinel distinguishes first launch from a user who explicitly chose a
  // fixed heap.
  if (getPrefObject(@"cofre.memory_default_applied") == nil) {
    setPrefBool(@"java.auto_ram", YES);
    setPrefBool(@"cofre.memory_default_applied", YES);
    NSLog(@"[Cofre] memory auto default enabled");
  }
  NSLog(@"[Cofre] memory auto ceiling=%dMB", ame141_currentLaunchAllocMem());
}
- (id)preferenceObject:(NSString *)key {
  return getPrefObject(key);
}
- (void)setPreferenceObject:(NSString *)key value:(id)value {
  setPrefObject(key, value);
}
- (NSDictionary *)preferencesForProfile:(NSString *)profile {
  return @{
    @"ramMB" : @(ame141_currentLaunchAllocMem()),
    @"renderer" : getPrefObject(@"renderer") ?: @"Auto",
    @"resolution" : @(getPrefFloat(@"resolution")),
    @"fsr" : @(getPrefBool(@"fsr1.enable")),
    @"java" : getPrefObject(@"javaVersion") ?: @"auto",
    @"jvmArgs" : getPrefObject(@"javaArgs") ?: @""
  };
}
// Air's Play flow (LauncherNavigationController launchMinecraft:): download the
// version's files, then hand the window to SurfaceViewController, which starts
// the JVM on a background queue. Cofre has already turned on JIT. Progress is
// download plus the real AmeLaunchProgress stages; completion waits for a frame.
- (void)launchProfile:(NSString *)profile
            accountID:(NSString *)accountID
             progress:(void (^)(NSString *))progress {
  [_profiles setSelectedProfileName:profile];
  if (accountID.length &&
      ![[BaseAuthenticator.current authData][@"accountId"] isEqual:accountID]) {
    BaseAuthenticator *saved = [BaseAuthenticator loadSavedName:accountID];
    if (saved)
      BaseAuthenticator.current = saved;
  }
  if (!BaseAuthenticator.current) {
    progress(@"failed:Sign in to your Minecraft account first.");
    return;
  }
  NSString *versionID = _profiles.selectedProfile[@"lastVersionId"];
  NSLog(@"[Cofre] launch profile=%@ version=%@", profile, versionID);
  CofreLoadVersionList(^{
    NSDictionary *version =
        [remoteVersionList
            filteredArrayUsingPredicate:[NSPredicate
                                            predicateWithFormat:@"(id == %@)",
                                                                versionID]]
                .firstObject
            ?: @{@"id" : versionID ?: @"", @"type" : @"custom"};
    MinecraftResourceDownloadTask *task = [MinecraftResourceDownloadTask new];
    __block BOOL failed = NO;
    __block id stageObserver = nil;
    __block id exitObserver = nil;
    void (^emitFailure)(NSString *) = ^(NSString *message) {
      if (stageObserver) {
        [NSNotificationCenter.defaultCenter removeObserver:stageObserver];
        stageObserver = nil;
      }
      if (exitObserver) {
        [NSNotificationCenter.defaultCenter removeObserver:exitObserver];
        exitObserver = nil;
      }
      NSLog(@"[Cofre] launch failed=%@", message);
      progress([NSString stringWithFormat:@"failed:%@", message]);
    };
    task.handleError = ^{
      dispatch_async(dispatch_get_main_queue(), ^{
        failed = YES;
      });
    };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      [task downloadVersion:version];
    });
    // Same completion test as Air's progress observer, polled.
    [NSTimer
        scheduledTimerWithTimeInterval:0.25
                               repeats:YES
                                 block:^(NSTimer *timer) {
                                   if (failed) {
                                     [timer invalidate];
                                     NSLog(@"[Cofre] launch download failed");
                                     emitFailure(@"Couldn't download the game files. Check your connection and the launcher log.");
                                     return;
                                   }
                                   NSProgress *total = task.progress;
                                   task.textProgress.completedUnitCount =
                                       total.totalUnitCount *
                                       total.fractionCompleted;
                                   if (!task.textProgress.finished) {
                                     progress([NSString
                                         stringWithFormat:
                                             @"downloading:%.3f",
                                             total.fractionCompleted]);
                                     return;
                                   }
                                   [timer invalidate];
                                   if (!task.metadata) {
                                     emitFailure(@"Air couldn't read this version's files.");
                                     return;
                                   }
                                   NSLog(@"[Cofre] launch files ready; starting the game");
                                   UIWindow *window = UIWindow.mainWindow;
                                   stageObserver = [NSNotificationCenter.defaultCenter
                                       addObserverForName:AmeLaunchProgressChangedNotification
                                                   object:nil
                                                    queue:NSOperationQueue.mainQueue
                                               usingBlock:^(NSNotification *note) {
                                                 AmeLaunchStage stage = AmeLaunchProgressCurrentStage();
                                                 double fraction = AmeLaunchProgressCurrentFraction();
                                                 NSString *key = AmeLaunchProgressCurrentKey() ?: @"";
                                                 progress([NSString stringWithFormat:@"air:%ld:%.4f:%@", (long)stage, fraction, key]);
                                                 if (stage == AmeLaunchStageCompleted) {
                                                   if (stageObserver) {
                                                     [NSNotificationCenter.defaultCenter removeObserver:stageObserver];
                                                     stageObserver = nil;
                                                   }
                                                   if (exitObserver) {
                                                     [NSNotificationCenter.defaultCenter removeObserver:exitObserver];
                                                     exitObserver = nil;
                                                   }
                                                   CofreFinishSurface(window);
                                                   progress(@"completed");
                                                 }
                                               }];
                                   exitObserver = [NSNotificationCenter.defaultCenter
                                       addObserverForName:@"CofreAirJVMExitNotification"
                                                   object:nil
                                                    queue:NSOperationQueue.mainQueue
                                               usingBlock:^(NSNotification *note) {
                                                 NSInteger code = [note.userInfo[@"code"] integerValue];
                                                 emitFailure([NSString stringWithFormat:@"Minecraft exited before the first frame (exit code %ld). Check the launch log.", (long)code]);
                                               }];
                                   CofrePresentSurface(window, task.metadata);
                                 }];
  });
}
- (void)hideCofreLaunchOverlay {
  NSLog(@"[Cofre] launch overlay hidden; Java may continue");
  CofreFinishSurface(UIWindow.mainWindow);
}
- (void)searchProjects:(NSDictionary *)filters
                source:(NSInteger)source
            completion:(void (^)(NSArray *, NSError *))completion {
  if (source == 2 && ![CurseForgeAPI isAPIKeyConfigured]) {
    if (completion)
      completion(@[], [NSError errorWithDomain:@"CofreAir"
                                          code:401
                                      userInfo:@{
                                        NSLocalizedDescriptionKey :
                                            @"CurseForge requires an API key"
                                      }]);
    return;
  }
  id api = source == 2 ? [CurseForgeAPI sharedInstance]
                       : [ModrinthAPI sharedInstance];
  [api searchModWithFilters:filters completion:completion];
}
- (NSDictionary *)modContextForProfile:(NSString *)profile {
  NSDictionary *data = _profiles.profiles[profile];
  return [ModpackExportService parseVersionId:data[@"lastVersionId"] ?: @""];
}
- (void)projectVersions:(NSString *)projectID
                 source:(NSInteger)source
             completion:(void (^)(NSArray *, NSError *))completion {
  if (source == 2 && ![CurseForgeAPI isAPIKeyConfigured]) {
    completion(@[], CofreAirError(@"CurseForge requires an API key"));
    return;
  }
  id api = source == 2 ? [CurseForgeAPI sharedInstance]
                       : [ModrinthAPI sharedInstance];
  [api getVersionsForModWithID:projectID
                    completion:^(NSArray<ModVersion *> *versions,
                                 NSError *error) {
                      NSMutableArray *rows = [NSMutableArray array];
                      for (ModVersion *version in versions) {
                        NSDictionary *raw = version.rawDictionary ?: @{};
                        NSDictionary *file = version.primaryFile ?: @{};
                        // Air's model takes files[0]; Modrinth explicitly marks
                        // the primary file.
                        for (NSDictionary *candidate in raw[@"files"]) {
                          if ([candidate[@"primary"] boolValue]) {
                            file = candidate;
                            break;
                          }
                        }
                        NSString *versionID =
                            [raw[@"id"] description] ?: version.fileId;
                        if (!versionID.length)
                          continue;
                        [rows addObject:@{
                          @"id" : versionID,
                          @"projectID" : projectID,
                          @"apiSource" : @(source),
                          @"name" : version.name ?: @"",
                          @"version" : version.versionNumber ?: @"",
                          @"gameVersions" : version.gameVersions ?: @[],
                          @"loaders" : version.loaders ?: @[],
                          @"channel" : version.versionType ?: @"release",
                          @"file" : file,
                          @"dependencies" : [raw[@"dependencies"]
                              isKindOfClass:NSArray.class]
                              ? raw[@"dependencies"]
                              : @[]
                        }];
                      }
                      completion(rows, error);
                    }];
}
- (void)searchServers:(NSDictionary *)filters
               source:(NSInteger)source
           completion:(void (^)(NSArray *, NSError *))completion {
  [[ServerService sharedService]
      searchServersWithAPI:(source == 2 ? ServerDownloadAPICurseForge
                                        : ServerDownloadAPIModrinth)
                   filters:filters
                completion:^(NSArray<ServerItem *> *items, NSError *error) {
                  NSMutableArray *out = [NSMutableArray array];
                  for (ServerItem *s in items)
                    [out addObject:@{
                      @"id" : s.serverID ?: @"",
                      @"title" : s.title ?: @"",
                      @"description" : s.serverDescription ?: @"",
                      @"address" : s.serverAddress ?: @"",
                      @"downloads" : s.downloads ?: @0,
                      @"author" : s.author ?: @"",
                      @"source" : @(s.apiSource)
                    }];
                  if (completion)
                    completion(error ? nil : out, error);
                }];
}
- (void)installProject:(NSDictionary *)data
               profile:(NSString *)profile
              progress:(void (^)(double, NSString *))progress
            completion:(void (^)(NSError *))completion {
  if ([data[@"apiSource"] integerValue] == 2 &&
      ![CurseForgeAPI isAPIKeyConfigured]) {
    completion(CofreAirError(@"CurseForge requires an API key"));
    return;
  }
  NSString *filename = [data[@"filename"] isKindOfClass:NSString.class]
                           ? data[@"filename"]
                           : nil;
  NSString *downloadURL = [data[@"downloadURL"] isKindOfClass:NSString.class]
                              ? data[@"downloadURL"]
                              : nil;
  NSURL *url = downloadURL.length ? [NSURL URLWithString:downloadURL] : nil;
  if (!filename.length ||
      ![filename isEqualToString:filename.lastPathComponent] ||
      ![filename.pathExtension.lowercaseString isEqualToString:@"jar"] ||
      ![url.scheme.lowercaseString isEqualToString:@"https"] ||
      !url.host.length) {
    completion(CofreAirError(@"This mod version has no valid download file"));
    return;
  }
  if (!_profiles.profiles[profile]) {
    completion(CofreAirError(@"The selected instance no longer exists"));
    return;
  }
  NSError *error = nil;
  if (![[ModService sharedService] ensureModsFolderForProfile:profile
                                                        error:&error]) {
    completion(
        error
            ?: CofreAirError(@"Could not create this instance's mods folder"));
    return;
  }
  ModItem *item = [[ModItem alloc] initWithOnlineData:data];
  item.selectedVersionDownloadURL = downloadURL;
  item.fileName = filename;
  item.version = data[@"version"];
  NSString *sha1 =
      [data[@"sha1"] isKindOfClass:NSString.class] ? data[@"sha1"] : nil;
  [[ModService sharedService] downloadMod:item
      toProfile:profile
      expectedSHA1:sha1.length ? sha1 : nil
      progress:^(NSProgress *p) {
        if (progress)
          progress(p.fractionCompleted, @"Downloading");
      }
      completion:^(NSError *error) {
        NSLog(@"[Cofre] mod install profile=%@ file=%@ success=%d", profile,
              filename, error == nil);
        completion(error);
      }];
}
- (void)importPack:(NSURL *)url
           profile:(NSString *)profile
          progress:(void (^)(double, NSString *))progress
        completion:(void (^)(NSError *))completion {
  ModpackImportService *service = [ModpackImportService new];
  NSError *error = nil;
  NSDictionary *info = [service parseModpackAtURL:url error:&error];
  BOOL ok = info && [service importModpack:info progress:progress error:&error];
  if (completion) {
    if (!ok && !error)
      error = [NSError
          errorWithDomain:@"CofreAir"
                     code:1
                 userInfo:@{NSLocalizedDescriptionKey : @"Air import failed"}];
    completion(ok ? nil : error);
  }
}
// Configured like Air's own launcher. Present it directly: inside a navigation
// controller its exit menu and Done button act on the wrong controller.
- (UIViewController *)controlsEditor {
  CustomControlsViewController *vc = [CustomControlsViewController new];
  vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
  vc.modalInPresentation = YES;
  vc.setDefaultCtrl = ^(NSString *name) {
    setPrefObject(@"control.default_ctrl", name);
  };
  vc.getDefaultCtrl = ^{
    return getPrefObject(@"control.default_ctrl");
  };
  return vc;
}
@end

UIViewController *CofreMakeControlsEditor(void) {
  return [[CofreAirBridgeAdapter new] controlsEditor];
}
