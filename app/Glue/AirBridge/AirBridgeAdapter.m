#import "AirBridgeAdapter.h"
#import "CofreConstants.h"
#import "CofreGameInput.h"
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
#import "SurfaceViewController.h"
#import "UIKit+hook.h"
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
#import <QuartzCore/CAMetalLayer.h>
#include <objc/runtime.h>
#import <objc/message.h>
#include <stdatomic.h>
#include <mach/mach.h>
#include <string.h>

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
static NSString *const CofreRequestedLoaderKey = @"cofreRequestedLoader";

static NSArray<NSNumber *> *CofreBundledJavaMajors(void) {
  NSString *root = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"java_runtimes"];
  NSArray<NSString *> *entries = [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil];
  NSMutableArray<NSNumber *> *majors = [NSMutableArray array];
  NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:@"^java-([0-9]+)-openjdk$"
                                                                                options:0 error:nil];
  for (NSString *entry in entries) {
    NSTextCheckingResult *match = [pattern firstMatchInString:entry options:0 range:NSMakeRange(0, entry.length)];
    if (!match) continue;
    NSString *path = [root stringByAppendingPathComponent:entry];
    BOOL directory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory] || !directory) continue;
    NSInteger major = [[entry substringWithRange:[match rangeAtIndex:1]] integerValue];
    if (major > 0) [majors addObject:@(major)];
  }
  return [majors sortedArrayUsingSelector:@selector(compare:)];
}

static void (^cofreLaunchEventHandler)(CofreLaunchEvent, double, NSString *);
static atomic_bool cofreAwaitingFirstDrawable;
static atomic_bool cofreLaunchFailurePending;
static atomic_bool cofrePerfActive;
static atomic_bool cofrePerfMetal;
static atomic_uint_fast64_t cofrePerfMetalFrames;
static dispatch_queue_t cofrePerfQueue;
static dispatch_source_t cofrePerfTimer;
static NSString *cofrePerfRenderer;
static NSUInteger cofrePerfElapsedSeconds;
static NSUInteger cofrePerfSampleCount;
static NSUInteger cofrePerfFrameTotal;
static double cofrePerfFrameTimes[5];
static NSUInteger cofrePerfFrameCounts[5];
// Where a launch is until its first frame; an engine error in that window becomes Cofre's launch error.
typedef NS_ENUM(int, CofreLaunchPhase) { CofreLaunchPhaseIdle, CofreLaunchPhaseDownloading, CofreLaunchPhaseStarting };
static atomic_int cofreLaunchPhase;
static NSString *cofreLastEngineAlert;
static id (*cofreOriginalNextDrawable)(id, SEL);

extern BOOL CofreOwnsRootUI(void);
extern void CofreShowOwnedFailure(NSString *detail);
extern unsigned int pojavGetAndResetFps(void);
BOOL CofreOwnsLaunchUI(void) { return CofreOwnsRootUI(); }
void CofreLaunchSurfaceAttached(void) { if (cofreLaunchEventHandler) cofreLaunchEventHandler(CofreLaunchEventSurfaceShown, 0, nil); }
static void CofreFirstFrame(NSString *source) {
  atomic_store(&cofreLaunchPhase, CofreLaunchPhaseIdle);
  NSLog(@"[Cofre] first-frame source=%@", source);
  if (cofreLaunchEventHandler) cofreLaunchEventHandler(CofreLaunchEventFirstFrame, 1, source);
}
void CofreLaunchFirstFramePresented(void) { CofreFirstFrame(@"gl/air"); }
static id CofreNextDrawable(CAMetalLayer *layer, SEL cmd) {
  id drawable = cofreOriginalNextDrawable(layer, cmd);
  // Metallum owns its CAMetalLayer and bypasses Air's EGL swap counter.
  // Keep this hook installed after the first-frame probe so its drawable
  // acquisitions remain visible to the five-second logger.
  if (atomic_load(&cofrePerfActive) && atomic_load(&cofrePerfMetal)) {
    atomic_fetch_add(&cofrePerfMetalFrames, 1);
  }
  if (atomic_exchange(&cofreAwaitingFirstDrawable, false)) {
    dispatch_async(dispatch_get_main_queue(), ^{ CofreFirstFrame(@"metal"); });
  }
  return drawable;
}
static void CofreArmFirstDrawable(void) {
  Method method = class_getInstanceMethod(CAMetalLayer.class, @selector(nextDrawable));
  IMP previous = method_setImplementation(method, (IMP)CofreNextDrawable);
  if (previous != (IMP)CofreNextDrawable && previous != NULL) cofreOriginalNextDrawable = (id (*)(id, SEL))previous;
  atomic_store(&cofreAwaitingFirstDrawable, true);
}

static BOOL CofrePerfLoggingRequested(void) {
#if DEBUG
  BOOL enabled = YES;
#else
  BOOL enabled = NO;
#endif
  // `-cofrePerfLog 1|0` from a scripted launch is remembered, so a tester's own taps on Play keep logging FPS.
  // (Air compiles this file without DEBUG, so the default above is NO on device builds too.)
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
  for (NSUInteger i = 0; i < arguments.count; i++) {
    NSString *argument = arguments[i];
    BOOL on = [argument isEqualToString:@"-cofrePerfLog=1"];
    if (!on && [argument isEqualToString:@"-cofrePerfLog"] && i + 1 < arguments.count) {
      on = [arguments[i + 1] isEqualToString:@"1"];
      if (!on) { [defaults removeObjectForKey:@"cofre.perfLog"]; return NO; }
    }
    if (on) { [defaults setBool:YES forKey:@"cofre.perfLog"]; return YES; }
  }
  return enabled || [defaults boolForKey:@"cofre.perfLog"];
}

static NSString *CofrePerfDocumentsLog(void) {
  NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
  return [documents stringByAppendingPathComponent:@"latestlog.txt"];
}

static void CofrePerfAppend(NSString *line) {
  NSData *data = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
  if (!data) return;
  NSString *path = CofrePerfDocumentsLog();
  NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
  if (!handle) {
    [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
    handle = [NSFileHandle fileHandleForWritingAtPath:path];
  }
  if (!handle) return;
  @try {
    [handle seekToEndOfFile];
    [handle writeData:data];
    [handle closeFile];
  } @catch (__unused NSException *exception) {
    [handle closeFile];
  }
}

static NSString *CofrePerfThermalState(void) {
  switch (NSProcessInfo.processInfo.thermalState) {
    case NSProcessInfoThermalStateNominal: return @"nominal";
    case NSProcessInfoThermalStateFair: return @"fair";
    case NSProcessInfoThermalStateSerious: return @"serious";
    case NSProcessInfoThermalStateCritical: return @"critical";
    default: return @"unknown";
  }
}

static double CofrePerfFootprintMB(void) {
  task_vm_info_data_t info;
  mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
  if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return 0;
  return (double)info.phys_footprint / (1024.0 * 1024.0);
}

static void CofrePerfDisableAirStatsTimer(SurfaceViewController *surface) {
  @try {
    NSTimer *timer = [surface valueForKey:@"statsTimer"];
    [timer invalidate];
    [surface setValue:nil forKey:@"statsTimer"];
  } @catch (__unused NSException *exception) {
    // Air's counter is still useful if a future SurfaceViewController hides this
    // private timer; the logger remains best effort.
  }
}

static void CofrePerfTick(void) {
  if (!atomic_load(&cofrePerfActive)) return;
  NSUInteger frames = atomic_load(&cofrePerfMetal)
      ? (NSUInteger)atomic_exchange(&cofrePerfMetalFrames, 0)
      : (NSUInteger)pojavGetAndResetFps();
  NSUInteger index = cofrePerfSampleCount;
  if (index < 5) {
    cofrePerfFrameCounts[index] = frames;
    cofrePerfFrameTimes[index] = frames ? 1000.0 / (double)frames : 0;
    cofrePerfSampleCount++;
  }
  cofrePerfFrameTotal += frames;
  cofrePerfElapsedSeconds++;
  if (cofrePerfSampleCount < 5) return;

  double sorted[5];
  memcpy(sorted, cofrePerfFrameTimes, sizeof(sorted));
  for (NSUInteger i = 1; i < 5; i++) {
    double value = sorted[i];
    NSUInteger j = i;
    while (j > 0 && sorted[j - 1] > value) {
      sorted[j] = sorted[j - 1];
      j--;
    }
    sorted[j] = value;
  }
  NSUInteger minFrames = cofrePerfFrameCounts[0];
  for (NSUInteger i = 1; i < 5; i++) minFrames = MIN(minFrames, cofrePerfFrameCounts[i]);
  double fps = (double)cofrePerfFrameTotal / 5.0;
  NSString *renderer = cofrePerfRenderer.length ? cofrePerfRenderer : @"unknown";
  NSString *line = [NSString stringWithFormat:
      @"[Cofre] perf t=%lus fps=%.1f min=%lu frameMs.p95=%.1f renderer=%@ footprintMB=%.0f thermal=%@",
      (unsigned long)cofrePerfElapsedSeconds, fps, (unsigned long)minFrames, sorted[4], renderer,
      CofrePerfFootprintMB(), CofrePerfThermalState()];
  NSLog(@"%@", line);
  CofrePerfAppend(line);
  cofrePerfSampleCount = 0;
  cofrePerfFrameTotal = 0;
  memset(cofrePerfFrameCounts, 0, sizeof(cofrePerfFrameCounts));
  memset(cofrePerfFrameTimes, 0, sizeof(cofrePerfFrameTimes));
}

static void CofrePerfLogStop(void) {
  if (!cofrePerfQueue) return;
  dispatch_sync(cofrePerfQueue, ^{
    atomic_store(&cofrePerfActive, false);
    if (cofrePerfTimer) {
      dispatch_source_cancel(cofrePerfTimer);
      cofrePerfTimer = nil;
    }
    cofrePerfRenderer = nil;
    cofrePerfElapsedSeconds = 0;
    cofrePerfSampleCount = 0;
    cofrePerfFrameTotal = 0;
    memset(cofrePerfFrameCounts, 0, sizeof(cofrePerfFrameCounts));
    memset(cofrePerfFrameTimes, 0, sizeof(cofrePerfFrameTimes));
    atomic_store(&cofrePerfMetalFrames, 0);
  });
}

static void CofrePerfLogStart(SurfaceViewController *surface) {
  if (!CofrePerfLoggingRequested()) return;
  if (!cofrePerfQueue) cofrePerfQueue = dispatch_queue_create("com.ignacio.cofre.perf", DISPATCH_QUEUE_SERIAL);
  // Air's HUD timer drains pojavGetAndResetFps(). Cofre owns that read while
  // logging so GL (ANGLE/MobileGlues) and Air's Vulkan fallback are not lost.
  CofrePerfDisableAirStatsTimer(surface);
  NSString *renderer = [PLProfiles resolveKeyForCurrentProfile:@"renderer"];
  NSString *environmentRenderer = NSProcessInfo.processInfo.environment[@"AMETHYST_RENDERER"];
  if (environmentRenderer.length && ![environmentRenderer isEqualToString:@"auto"]) renderer = environmentRenderer;
  BOOL metal = [renderer.lowercaseString containsString:@"metallum"] ||
      [NSProcessInfo.processInfo.environment[@"AMETHYST_METAL"] isEqualToString:@"1"];
  dispatch_sync(cofrePerfQueue, ^{
    atomic_store(&cofrePerfActive, false);
    if (cofrePerfTimer) {
      dispatch_source_cancel(cofrePerfTimer);
      cofrePerfTimer = nil;
    }
    cofrePerfRenderer = [renderer copy];
    atomic_store(&cofrePerfMetal, metal);
    atomic_store(&cofrePerfMetalFrames, 0);
    cofrePerfElapsedSeconds = 0;
    cofrePerfSampleCount = 0;
    cofrePerfFrameTotal = 0;
    memset(cofrePerfFrameCounts, 0, sizeof(cofrePerfFrameCounts));
    memset(cofrePerfFrameTimes, 0, sizeof(cofrePerfFrameTimes));
    (void)pojavGetAndResetFps();
    cofrePerfTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, cofrePerfQueue);
    dispatch_source_set_timer(cofrePerfTimer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, 50 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(cofrePerfTimer, ^{ CofrePerfTick(); });
    dispatch_resume(cofrePerfTimer);
    atomic_store(&cofrePerfActive, true);
  });
}

void CofreLaunchGameExited(int code) {
  CofrePerfLogStop();
  dispatch_async(dispatch_get_main_queue(), ^{ if (cofreLaunchEventHandler) cofreLaunchEventHandler(CofreLaunchEventExited, code, [NSString stringWithFormat:@"exit code %d", code]); });
}
// Air's UIKit_returnToSplitView (patch 0002) lands here: put Cofre's root back from the launch overlay instead of
// Air's split view. Air only returns before the JVM starts, while the overlay still holds Cofre's root.
void CofreReturnToLauncher(void) {
  CofrePerfLogStop();
  dispatch_async(dispatch_get_main_queue(), ^{
    UIWindow *overlay = cofreLaunchOverlayWindow;
    UIViewController *root = overlay.rootViewController;
    NSLog(@"[Cofre] engine returned to launcher restored=%d", root != nil);
    AmeGameLandscapeLockExit();
    if (!root) return;
    cofreLaunchOverlayWindow = nil;
    overlay.rootViewController = nil;
    overlay.hidden = YES;
    UIWindow *window = UIWindow.mainWindow;
    window.rootViewController = root;
    [window makeKeyAndVisible];
  });
}
static void CofreReportLaunchFailure(CofreLaunchEvent event, NSString *message) {
  NSString *detail = message.length ? message : @"Minecraft couldn't start. Check the launcher log.";
  // Only the first error of a launch is shown; later ones (and errors outside a launch) are logged.
  if (atomic_exchange(&cofreLaunchPhase, CofreLaunchPhaseIdle) == CofreLaunchPhaseIdle) {
    NSLog(@"[Cofre] engine error outside a launch: %@", detail);
    // Only visible on the owned fallback root (CofreCore failed to load).
    CofreShowOwnedFailure(detail);
    return;
  }
  atomic_store(&cofreLaunchFailurePending, true);
  NSLog(@"[Cofre] launch failed before game start event=%ld: %@", (long)event, detail);
  CofreReturnToLauncher();
  dispatch_async(dispatch_get_main_queue(), ^{
    if (cofreLaunchEventHandler) cofreLaunchEventHandler(event, 0, detail);
  });
}
void CofreLaunchFailed(NSString *message) { CofreReportLaunchFailure(CofreLaunchEventFailed, message); }
// Air's showDialog and Java's UIKit.showError (patch 0002) land here instead of a UIAlertController.
void CofreEngineAlert(NSString *title, NSString *message) {
  NSString *detail = message.length ? message : title;
  NSLog(@"[Cofre] engine alert routed title=%@ message=%@", title ?: @"", detail ?: @"");
  @synchronized(CofreAirBridgeAdapter.class) { cofreLastEngineAlert = detail; }
  BOOL downloading = atomic_load(&cofreLaunchPhase) == CofreLaunchPhaseDownloading;
  CofreReportLaunchFailure(downloading ? CofreLaunchEventDownloadFailed : CofreLaunchEventFailed, detail);
}
static NSString *CofreTakeEngineAlert(void) {
  @synchronized(CofreAirBridgeAdapter.class) {
    NSString *alert = cofreLastEngineAlert;
    cofreLastEngineAlert = nil;
    return alert;
  }
}
BOOL CofreConsumeLaunchFailure(void) {
  return atomic_exchange(&cofreLaunchFailurePending, false);
}

static void CofreFinishSurface(UIWindow *window);

// Air sizes Minecraft's window and lays out its game view from the surface's first layout. Built while an iPhone is
// still turning from portrait, the game starts at 1206x2622 and Air's rotation handler later moves its root view to
// the lower left. Wait up to 2 s for the landscape turn.
static void CofreAfterLandscape(UIWindow *window, int waitedMs, dispatch_block_t then) {
  CGSize size = window.windowScene.coordinateSpace.bounds.size;
  if (size.width >= size.height || waitedMs >= 2000) {
    NSLog(@"[Cofre] launch surface size=%.0fx%.0f waitedMs=%d", size.width, size.height, waitedMs);
    then();
    return;
  }
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
    CofreAfterLandscape(window, waitedMs + 50, then);
  });
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

    // Minecraft sizes its window from the surface's first layout, so turn to
    // landscape first, as Air's own Play button does.
    AmeGameLandscapeLockEnter();
    CofreAfterLandscape(window, 0, ^{
      SurfaceViewController *surface = [[SurfaceViewController alloc] initWithMetadata:metadata];
      CofreArmFirstDrawable();
      [CofreGameOverlayHost installOnSurface:surface];
      window.alpha = 0;
      window.rootViewController = surface;
      [window makeKeyAndVisible];
      [UIView animateWithDuration:0.2 animations:^{ window.alpha = 1; }];
      CofrePerfLogStart(surface);

      NSLog(@"[Cofre] launch surface presented with Cofre overlay");
    });
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
// Air keeps launcher_profiles.json in memory and saves all of it on its own changes; reload after Cofre writes it
// so neither side overwrites the other.
- (void)reloadProfiles {
  [PLProfiles updateCurrent];
  _profiles = [PLProfiles current];
}
- (BOOL)jvmUsedInProcess { return JVMUsedInProcess(); }

#pragma mark - Instances

- (NSDictionary *)instanceSummary:(NSString *)name {
  NSDictionary *profile = _profiles.profiles[name];
  if (!profile)
    return nil;
  NSDictionary *parsed =
      [ModpackExportService parseVersionId:profile[@"lastVersionId"] ?: @""];
  return @{@"id": name, @"name": profile[@"name"] ?: name,
           @"version": profile[@"cofreGameVersion"] ?: parsed[@"minecraft"] ?: profile[@"lastVersionId"] ?: @"",
           @"loader": profile[CofreRequestedLoaderKey] ?: profile[@"loader"] ?: parsed[@"loader"] ?: @"vanilla",
           @"loaderVersion": profile[@"loaderVersion"] ?: parsed[@"loaderVersion"] ?: @"",
           @"fabricAPI": profile[@"cofreInstallFabricAPI"] ?: @NO,
           @"icon": profile[@"icon"] ?: @"",
           @"cofreIcon": profile[@"cofreIcon"] ?: @"",
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

- (NSURL *)gameDirectoryForProfile:(NSString *)profile {
  NSDictionary *p = self.profiles.profiles[profile];
  NSString *path = p ? amePCLVersionGameDirAbsolute(p, nil) : nil;
  return path.length ? [NSURL fileURLWithPath:path isDirectory:YES] : nil;
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
      candidateURLsForVendor:CofreLoaderKindFromRaw(loader) == CofreLoaderKindQuilt ? @"Quilt"
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
    CofreRequestedLoaderKey : loader,
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
  profile[CofreRequestedLoaderKey] = loader;
  [profile removeObjectForKey:@"loader"];
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
// installer and runs Air's processor JVM without presenting another screen.
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
  if (JVMUsedInProcess()) {
    done(CofreAirError(@"Reopen Cofre to install another loader."));
    return;
  }
  CofreTakeEngineAlert();
  NSDictionary *profile = _profiles.profiles[name];
  NSString *game = profile[@"cofreGameVersion"] ?: profile[@"lastVersionId"];
  BOOL neo = CofreLoaderKindFromRaw(loader) == CofreLoaderKindNeoForge;
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
  // Minecraft's version IDs are lower-case and differ between the loaders.
  // NeoForge uses `neoforge-<loader>`, while Forge uses `<mc>-forge-<loader>`.
  NSString *versionID;
  if (neo) {
    versionID = [NSString stringWithFormat:@"neoforge-%@", full];
  } else {
    NSString *forgeVersion = [version hasPrefix:[game stringByAppendingString:@"-"]]
                                  ? [version substringFromIndex:game.length + 1]
                                  : version;
    versionID = [NSString stringWithFormat:@"%@-forge-%@", game, forgeVersion];
  }
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
          // The installers download libraries synchronously through the shared
          // session; running them on its serial callback queue deadlocks.
          dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
          // Air never clears this flag, so a run that stopped before the JVM started would
          // make the next attempt skip the processors and miss their status file.
          atomic_store(&g_ame_headlessJvmFinished, 0);
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
              // The processors' JVM reports through showDialog, which patch 0002 routes to CofreEngineAlert.
              NSString *alert = CofreTakeEngineAlert();
              NSLog(@"[Cofre] loader install failed %@: %@", versionID,
                    installError.localizedDescription ?: alert ?: @"no reason");
              completion(installError ?: CofreAirError(alert ?: @"Air could not install this loader."));
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
            updated[CofreRequestedLoaderKey] = loader;
            [updated removeObjectForKey:@"loader"];
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
          });
        }] resume];
}

#pragma mark - End instances


/* accounts are read by CofreKit; Air only owns token cleanup. */
- (void)removeAccountToken:(NSString *)accountID {
  if (accountID.length == 0) return;
  NSDictionary *query = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                          (__bridge id)kSecAttrService: @"AccountToken",
                          (__bridge id)kSecAttrAccount: accountID};
  SecItemDelete((__bridge CFDictionaryRef)query);
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
}
static NSString *CofreProfileFieldForPreference(NSString *key) {
  if ([key isEqualToString:@"video.renderer"]) return @"renderer";
  if ([key isEqualToString:@"video.graphics_api"]) return @"graphicsApi";
  if ([key isEqualToString:@"java.java_version"]) return @"javaVersion";
  if ([key isEqualToString:@"java.java_args"]) return @"javaArgs";
  if ([key isEqualToString:@"java.allocated_memory"]) return @"allocatedMemory";
  return nil;
}

- (id)preferenceObject:(NSString *)key profile:(NSString *)profile {
  NSString *field = CofreProfileFieldForPreference(key);
  if (profile.length && field.length) {
    NSMutableDictionary *candidate = self.profiles.profiles[profile];
    if ([field isEqualToString:@"renderer"] && [candidate[@"cofreRendererPicked"] boolValue]) return @"auto";
    if ([field isEqualToString:@"allocatedMemory"]) {
      NSNumber *value = candidate[field];
      if (value.integerValue > 0) return value;
      return getPrefObject(key);
    }
    return [PLProfiles profile:candidate ?: [NSMutableDictionary dictionary]
                    resolveKey:field];
  }
  return getPrefObject(key);
}

- (void)setPreferenceObject:(NSString *)key
                      value:(id)value
                    profile:(NSString *)profile {
  NSString *field = CofreProfileFieldForPreference(key);
  if (profile.length && field.length) {
    NSMutableDictionary *candidate = [self.profiles.profiles[profile] mutableCopy];
    if (!candidate) candidate = [NSMutableDictionary dictionary];
    candidate[field] = value;
    if ([field isEqualToString:@"renderer"]) [candidate removeObjectForKey:@"cofreRendererPicked"];
    [self.profiles saveProfile:candidate withName:profile];
    return;
  }
  setPrefObject(key, value);
}

// Air's Play flow (LauncherNavigationController launchMinecraft:): download the
// version's files, then hand the window to SurfaceViewController, which starts
// the JVM on a background queue. Cofre has already turned on JIT. Progress is
// download plus the real AmeLaunchProgress stages; completion waits for a frame.
- (void)launchProfile:(NSString *)profile
            accountID:(NSString *)accountID
        gameArguments:(NSArray<NSString *> *)gameArguments
             progress:(void (^)(CofreLaunchEvent, double, NSString *))progress {
  atomic_store(&cofreLaunchFailurePending, false);
  atomic_store(&cofreLaunchPhase, CofreLaunchPhaseDownloading);
  cofreLaunchEventHandler = progress;
  [_profiles setSelectedProfileName:profile];
  if (accountID.length &&
      ![[BaseAuthenticator.current authData][@"accountId"] isEqual:accountID]) {
    BaseAuthenticator *saved = [BaseAuthenticator loadSavedName:accountID];
    if (saved)
      BaseAuthenticator.current = saved;
  }
  if (!BaseAuthenticator.current) {
    CofreLaunchFailed(@"Sign in to your Minecraft account first.");
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
    UIWindow *window = UIWindow.mainWindow;
    task.handleError = ^{ failed = YES; };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      [task downloadVersion:version];
    });
    [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
      if (failed) {
        [timer invalidate];
        // Air's own error (showDialog) usually got there first with the reason.
        if (atomic_load(&cofreLaunchPhase) != CofreLaunchPhaseIdle)
          CofreReportLaunchFailure(CofreLaunchEventDownloadFailed, @"Check your connection and the launcher log.");
        return;
      }
      NSProgress *total = task.progress;
      task.textProgress.completedUnitCount = total.totalUnitCount * total.fractionCompleted;
      if (!task.textProgress.finished) {
        progress(CofreLaunchEventDownloading, total.fractionCompleted, @"Game files");
        return;
      }
      [timer invalidate];
      int downloading = CofreLaunchPhaseDownloading;
      if (!atomic_compare_exchange_strong(&cofreLaunchPhase, &downloading, CofreLaunchPhaseStarting)) return;
      if (!task.metadata) {
        CofreLaunchFailed(@"Air couldn't read this version's files.");
        return;
      }
      NSMutableDictionary *metadata = [task.metadata mutableCopy];
      if (![self pickRendererForProfile:profile metadata:metadata]) return;
      [self setGameLanguageForProfile:profile metadata:metadata];
      progress(CofreLaunchEventPreparing, 0, @"Starting Minecraft");
      // A JVM property belongs to this launch only; never persist it into a profile/version file.
      NSMutableDictionary *arguments = [metadata[@"arguments"] mutableCopy] ?: [NSMutableDictionary dictionary];
      NSMutableArray *jvm = [arguments[@"jvm_processed"] mutableCopy] ?: [NSMutableArray array];
      NSData *json = [NSJSONSerialization dataWithJSONObject:gameArguments options:0 error:nil];
      [jvm addObject:[@"-Dcofre.gameArguments=" stringByAppendingString:[json base64EncodedStringWithOptions:0]]];
      arguments[@"jvm_processed"] = jvm;
      metadata[@"arguments"] = arguments;
      CofrePresentSurface(window, metadata);
    }];
  });
}
// Swift owns the renderer decision; ObjC only applies the Air preference.
- (BOOL)pickRendererForProfile:(NSString *)name metadata:(NSMutableDictionary *)metadata {
  NSMutableDictionary *profile = [_profiles.profiles[name] mutableCopy];
  Class entry = NSClassFromString(@"CofreCoreEntry");
  SEL resolve = NSSelectorFromString(@"rendererForProfile:metadata:globalSetting:");
  if (!profile || ![entry respondsToSelector:resolve]) {
    CofreLaunchFailed(@"Cofre could not resolve this instance's renderer. Reopen Cofre and try again.");
    return NO;
  }
  NSString *global = getPrefObject(@"video.renderer");
  NSString *pick = ((id (*)(id, SEL, id, id, id))objc_msgSend)(entry, resolve, profile, metadata, global ?: @"auto");
  if (!pick.length) {
    CofreLaunchFailed(@"Cofre could not resolve this instance's renderer. Reopen Cofre and try again.");
    return NO;
  }
  NSString *library = [pick isEqual:@"auto"] ? @"libtinygl4angle.dylib" : pick;
  NSString *libraryPath = [[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks"] stringByAppendingPathComponent:library];
  if (![NSFileManager.defaultManager fileExistsAtPath:libraryPath]) {
    NSLog(@"[Cofre] renderer unavailable: %@", library);
    CofreReportLaunchFailure(CofreLaunchEventRendererUnsupported, @"The selected renderer is not available in this build.");
    return NO;
  }
  SEL javaResolve = NSSelectorFromString(@"javaRuntimeDecisionForProfile:metadata:renderer:availableJavaMajors:");
  if (![entry respondsToSelector:javaResolve]) {
    CofreLaunchFailed(@"Cofre could not validate the Metal Java runtime. Reopen Cofre and try again.");
    return NO;
  }
  NSDictionary *javaDecision = ((id (*)(id, SEL, id, id, id, id))objc_msgSend)(
      entry, javaResolve, profile, metadata, pick, CofreBundledJavaMajors());
  NSString *javaAction = javaDecision[@"action"];
  if ([javaAction isEqualToString:@"unsupportedSelection"]) {
    CofreLaunchFailed([NSString stringWithFormat:
        @"Metal needs Java %@ or newer, but this instance selects Java %@. Choose Auto in its Java settings.",
        javaDecision[@"minimum"], javaDecision[@"selected"]]);
    return NO;
  }
  if ([javaAction isEqualToString:@"unavailable"]) {
    NSNumber *minimum = javaDecision[@"minimum"] ?: @22;
    CofreLaunchFailed([NSString stringWithFormat:
        @"Metal needs Java %@ or newer, but this build has no bundled runtime that can start it.", minimum]);
    return NO;
  }
  if ([javaAction isEqualToString:@"use"]) {
    NSNumber *major = javaDecision[@"major"];
    // SurfaceViewController reads this minimum when starting the JVM. Only
    // change the launch copy; the version file and user's profile stay intact.
    NSMutableDictionary *java = [metadata[@"javaVersion"] mutableCopy] ?: [NSMutableDictionary dictionary];
    java[@"majorVersion"] = major;
    metadata[@"javaVersion"] = java;
    if ([javaDecision[@"selected"] integerValue] > 0) {
      NSLog(@"[Cofre] Metal Java runtime: using selected Java %@ (game requires Java %@)",
            major, javaDecision[@"required"]);
    } else {
      NSLog(@"[Cofre] Metal Java override: auto selected bundled Java %@ (game requires Java %@)",
            major, javaDecision[@"required"]);
    }
  }
  BOOL explicit = [profile[@"renderer"] isKindOfClass:NSString.class]
      && [profile[@"renderer"] length] && ![profile[@"renderer"] isEqual:@"auto"]
      && ![profile[@"cofreRendererPicked"] boolValue];
  // Cofre stores friendly renderer IDs, while Air's launch path requires the
  // actual dylib filename. Canonicalize explicit picks too: Metal otherwise
  // stays "metallum", so Air never sets AMETHYST_METAL and Fabric falls back
  // to ANGLE before MetalUniversal can create its device.
  BOOL needsRendererCanonicalName = explicit && ![profile[@"renderer"] isEqual:pick];
  if (!explicit || needsRendererCanonicalName) {
    if ([pick isEqual:@"auto"]) {
      [profile removeObjectForKey:@"renderer"];
      [profile removeObjectForKey:@"cofreRendererPicked"];
    } else {
      profile[@"renderer"] = pick;
      if (!explicit) profile[@"cofreRendererPicked"] = @YES;
      else [profile removeObjectForKey:@"cofreRendererPicked"];
    }
    NSMutableDictionary *profiles = [_profiles.profiles mutableCopy];
    profiles[name] = profile;
    NSError *error = nil;
    if (![self persistInstanceProfiles:profiles selected:name error:&error]) {
      CofreLaunchFailed(error.localizedDescription);
      return NO;
    }
  }
  NSLog(@"[Cofre] renderer resolved -> %@ for %@ loader=%@", pick, metadata[@"id"],
        profile[CofreRequestedLoaderKey] ?: profile[@"loader"] ?: @"inferred");
  [self applyResolution];
  return YES;
}

// Settings › Resolution keeps the picked size in Cofre's defaults; Air reads video.resolution at launch. MobileGlues'
// FSR stays off: its upscale shader is desktop GLSL 4.50, which ANGLE on iOS rejects, so the screen stays black.
- (void)applyResolution {
  NSNumber *picked = [NSUserDefaults.standardUserDefaults objectForKey:@"cofre.render.scale"];
  if (picked) setPrefObject(@"video.resolution", @(picked.doubleValue * 100));
  setPrefObject(@"mobileglues.fsr1_setting", @0);
  NSLog(@"[Cofre] resolution %.0f%% fsr=off", getPrefFloat(@"video.resolution"));
}
// Air's Java launcher sets Minecraft to Chinese (lang:zh_cn) when options.txt has no language, so write the
// phone's language first. Only when none is set: after that the game owns options.txt.
- (void)setGameLanguageForProfile:(NSString *)name metadata:(NSDictionary *)metadata {
  NSString *path = [amePCLVersionGameDirAbsolute(_profiles.profiles[name], nil)
      stringByAppendingPathComponent:@"options.txt"];
  NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
  if ([text hasPrefix:@"lang:"] || [text containsString:@"\nlang:"]) return;

  NSString *game = metadata[@"inheritsFrom"] ?: metadata[@"id"] ?: @"";
  NSArray<NSString *> *parts = [game componentsSeparatedByString:@"."];
  // 1.10 and older need "en_US"; lowercase crashes the oldest versions.
  BOOL legacy = [parts.firstObject isEqualToString:@"1"] && parts.count > 1 && parts[1].integerValue < 11;
  NSLocale *locale = [NSLocale localeWithLocaleIdentifier:NSLocale.preferredLanguages.firstObject ?: @"en-US"];
  NSString *language = locale.languageCode.lowercaseString ?: @"en";
  NSString *region = locale.countryCode ?: ([language isEqualToString:@"en"] ? @"us" : language);
  region = legacy ? region.uppercaseString : region.lowercaseString;
  NSString *lang = [NSString stringWithFormat:@"lang:%@_%@", language, region];

  [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
                          withIntermediateDirectories:YES attributes:nil error:nil];
  [[NSString stringWithFormat:@"%@\n%@", lang, text] writeToFile:path atomically:YES
                                                         encoding:NSUTF8StringEncoding error:nil];
  NSLog(@"[Cofre] game %@ for Minecraft %@", lang, game);
}
- (void)hideCofreLaunchOverlay {
  NSLog(@"[Cofre] launch overlay closing");
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
                          @"size" : version.fileSize ?: @0,
                          @"dependencies" : [raw[@"dependencies"]
                              isKindOfClass:NSArray.class]
                              ? raw[@"dependencies"]
                              : @[]
                        }];
                      }
                      completion(rows, error);
                    }];
}

- (void)importPack:(NSURL *)url
          progress:(void (^)(double, NSString *))progress
        completion:(void (^)(NSError *))completion {
  // Air's importer blocks while it downloads; Air itself runs it off the main thread.
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    ModpackImportService *service = [ModpackImportService new];
    NSError *error = nil;
    NSDictionary *info = [service parseModpackAtURL:url error:&error];
    NSLog(@"[Cofre] air pack import start format=%@ loader=%@", info[@"format"] ?: @"?", info[@"loader"] ?: @"?");
    BOOL ok = info && [service importModpack:info progress:progress error:&error];
    if (!ok && !error)
      error = [NSError
          errorWithDomain:@"CofreAir"
                     code:1
                 userInfo:@{NSLocalizedDescriptionKey : @"Air import failed"}];
    NSLog(@"[Cofre] air pack import result=%@", ok ? @"ok" : @"fail");
    dispatch_async(dispatch_get_main_queue(), ^{
      if (completion) completion(ok ? nil : error);
    });
  });
}
- (void)gameInputKey:(NSString *)name down:(BOOL)down {
  CofreInputKey(name.UTF8String, down);
}
- (void)gameInputMouseButton:(NSInteger)button down:(BOOL)down {
  CofreInputMouseButton((int)button, down);
}
- (void)gameInputLookX:(float)deltaX y:(float)deltaY {
  CofreInputLook(deltaX, deltaY);
}
- (void)setGameKeyboardShown:(BOOL)shown {
  shown ? CofreInputShowKeyboard() : CofreInputHideKeyboard();
}
- (void)gameInputScroll:(NSInteger)steps {
  CofreInputScroll((int)steps);
}
- (NSDictionary<NSString *, NSNumber *> *)gameScreenState {
  return CofreGameScreenState();
}
@end

