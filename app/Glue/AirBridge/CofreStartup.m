// Starts Cofre inside Air's executable: loads CofreCore.framework (our Swift UI
// and backend), hands it the Air bridge, and starts the VPN if allowed. Air's
// SceneDelegate (patch 0002) asks CofreMakeRootViewController() for the root
// screen; every path stays in Cofre UI.
#import "AirBridgeAdapter.h"
#import "LauncherPreferences.h"
#import "utils.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const CofreCorePath =
    @"@executable_path/Frameworks/CofreCore.framework/CofreCore";

static BOOL cofreOwnsJIT = NO;
static BOOL cofreOwnsRootUI = NO;
static BOOL cofreUsingFallbackUI = NO;
static UILabel *cofreFallbackDetail;
static NSMutableArray<NSURL *> *cofrePendingURLs;
static BOOL cofreRootReady = NO;
static NSString *const CofreOpenURLNotification = @"CofreOpenURL";
static Class CofreCoreEntryClass(void);
static void CofreDeliverURL(NSURL *url);

static void CofreReceiveURL(NSURL *url) {
  if (!url) return;
  NSLog(@"[Cofre] open url scheme=%@", url.scheme.lowercaseString ?: @"");
  dispatch_async(dispatch_get_main_queue(), ^{
    if (cofreRootReady) {
      CofreDeliverURL(url);
    } else {
      if (!cofrePendingURLs) cofrePendingURLs = [NSMutableArray array];
      [cofrePendingURLs addObject:url];
    }
  });
}

static void CofreDrainPendingOpenURLs(void) {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!cofreRootReady || cofrePendingURLs.count == 0) return;
    NSArray<NSURL *> *urls = [cofrePendingURLs copy];
    [cofrePendingURLs removeAllObjects];
    for (NSURL *url in urls) {
      CofreDeliverURL(url);
    }
  });
}

static void CofreSceneOpenURLContexts(id self, SEL _cmd, UIScene *scene, NSSet<UIOpenURLContext *> *contexts) {
  for (UIOpenURLContext *context in contexts) CofreReceiveURL(context.URL);
}

static void CofreSceneWillConnect(id self, SEL _cmd, UIScene *scene, UISceneSession *session,
                                  UISceneConnectionOptions *options) {
  SEL original = NSSelectorFromString(@"cofre_original_scene:willConnectToSession:options:");
  ((void (*)(id, SEL, UIScene *, UISceneSession *, UISceneConnectionOptions *))objc_msgSend)(self, original, scene, session, options);
  for (UIOpenURLContext *context in options.URLContexts) CofreReceiveURL(context.URL);
}

static void CofreInstallSceneHooks(void) {
  Class cls = NSClassFromString(@"SceneDelegate");
  if (!cls) return;
  SEL open = @selector(scene:openURLContexts:);
  if (!class_getInstanceMethod(cls, open)) {
    class_addMethod(cls, open, (IMP)CofreSceneOpenURLContexts, "v@:@@");
  }
  SEL willConnect = @selector(scene:willConnectToSession:options:);
  SEL originalAlias = NSSelectorFromString(@"cofre_original_scene:willConnectToSession:options:");
  Method original = class_getInstanceMethod(cls, willConnect);
  if (original && !class_getInstanceMethod(cls, originalAlias)) {
    class_addMethod(cls, originalAlias, method_getImplementation(original), method_getTypeEncoding(original));
    class_replaceMethod(cls, willConnect, (IMP)CofreSceneWillConnect, method_getTypeEncoding(original));
  }
}

BOOL CofreOwnsJIT(void) { return cofreOwnsJIT; }
BOOL CofreOwnsRootUI(void) { return cofreOwnsRootUI; }
extern BOOL CofreConsumeLaunchFailure(void);

static UIViewController *CofreOwnedFallbackRoot(NSString *detail) {
  UIViewController *viewController = [UIViewController new];
  viewController.view.backgroundColor = [UIColor colorWithRed:0.035 green:0.035 blue:0.05 alpha:1];
  UILabel *title = [UILabel new];
  title.translatesAutoresizingMaskIntoConstraints = NO;
  title.text = @"Cofre";
  title.textColor = UIColor.whiteColor;
  title.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
  UILabel *message = [UILabel new];
  message.translatesAutoresizingMaskIntoConstraints = NO;
  message.numberOfLines = 0;
  message.textAlignment = NSTextAlignmentCenter;
  message.textColor = [UIColor colorWithWhite:1 alpha:0.78];
  message.font = [UIFont systemFontOfSize:17 weight:UIFontWeightRegular];
  message.text = detail.length ? detail : @"Cofre could not start its interface. Close and reopen the app.";
  cofreFallbackDetail = message;
  [viewController.view addSubview:title];
  [viewController.view addSubview:message];
  [NSLayoutConstraint activateConstraints:@[
    [title.centerXAnchor constraintEqualToAnchor:viewController.view.centerXAnchor],
    [title.centerYAnchor constraintEqualToAnchor:viewController.view.centerYAnchor constant:-70],
    [message.leadingAnchor constraintGreaterThanOrEqualToAnchor:viewController.view.leadingAnchor constant:28],
    [message.trailingAnchor constraintLessThanOrEqualToAnchor:viewController.view.trailingAnchor constant:-28],
    [message.centerXAnchor constraintEqualToAnchor:viewController.view.centerXAnchor],
    [message.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:20]
  ]];
  return viewController;
}

void CofreShowOwnedFailure(NSString *detail) {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!cofreFallbackDetail) return;
    cofreFallbackDetail.text = detail.length ? detail : @"Cofre could not start its interface. Close and reopen the app.";
  });
}

/// Loads CofreCore once and returns its entry class, or nil (logging why) if it
/// can't be loaded.
static Class CofreCoreEntryClass(void) {
  static Class entry;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    void *handle = dlopen(CofreCorePath.UTF8String, RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
      NSLog(@"[Cofre] owned UI fallback reason=framework missing (%s)", dlerror());
      return;
    }
    entry = NSClassFromString(@"CofreCoreEntry");
    if (!entry) {
      NSLog(@"[Cofre] owned UI fallback reason=class missing");
    }
  });
  return entry;
}

static void CofreDeliverURL(NSURL *url) {
  Class entry = CofreCoreEntryClass();
  SEL handler = @selector(handleOpenURL:);
  if (entry && [entry respondsToSelector:handler]) {
    ((void (*)(id, SEL, NSURL *))objc_msgSend)(entry, handler, url);
    return;
  }
  [[NSNotificationCenter defaultCenter] postNotificationName:CofreOpenURLNotification object:url];
}

/// On iOS 26+ JIT comes from a debugger-made code region. Detaching after it
/// leaves dyld unable to load the unsigned libraries newer Minecraft needs (JNA
/// for 26.3), so keep Cofre's debugger attached for breakpoints only and let
/// Air patch dyld through it, as Air does on these devices.
static void CofreConfigureAirJIT(void) {
  DeviceGetJITFlags(YES);
  if (!DeviceNeedsDebugJITMapping()) {
    return;
  }
  setPrefBool(@"debug.debug_always_attached_jit", YES);
  setPrefBool(@"java.dyld_bypass", YES);
  NSLog(@"[Cofre] JIT mode=attached dyld_bypass=on");
}

/// Background/resume breadcrumbs: whether the JIT debugger is still attached when the app comes back is the main
/// suspect for a game that freezes after the Home Screen.
static void CofreWatchLifecycle(void) {
  NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
  [center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
    NSLog(@"[Cofre] app background jit=%d debugger=%d", isJITEnabled(false), JIT26IsLikelyDebuggerKeepAttached());
  }];
  [center addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
    NSLog(@"[Cofre] app foreground jit=%d debugger=%d", isJITEnabled(false), JIT26IsLikelyDebuggerKeepAttached());
  }];
  [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
    NSLog(@"[Cofre] app active jit=%d debugger=%d", isJITEnabled(false), JIT26IsLikelyDebuggerKeepAttached());
  }];
}

/// Starts CofreCore with the Air bridge exactly once. Safe to call from any
/// launch path.
static void CofreEnsureStarted(void) {
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    Class entry = CofreCoreEntryClass();
    if (!entry) {
      return;
    }
    // Air derives POJAV_GAME_DIR from realpath (/private/var/...). Its zip-slip guard standardizes both the
    // root (which exists, so /private is dropped) and each entry (not yet created, so /private stays), then
    // rejects every modpack override as "escaping the extraction root". Hand Air the standardized form.
    const char *gameDir = getenv("POJAV_GAME_DIR");
    if (gameDir) {
      setenv("POJAV_GAME_DIR", @(gameDir).stringByStandardizingPath.UTF8String, 1);
    }
    CofreAirBridgeAdapter *bridge = [CofreAirBridgeAdapter new];
    ((void (*)(id, SEL, id))objc_msgSend)(entry, @selector(startWithBridge:),
                                          bridge);
    [bridge ensureAutomaticMemoryDefault];
    CofreConfigureAirJIT();
    CofreWatchLifecycle();
    // The game owns VSync and its frame limit in options.txt. With this Air setting on, Air's Java launcher
    // overwrites both (VSync off, 260 FPS) at every launch, undoing what the player picked in game.
    setPrefBool(@"video.disable_game_vsync", NO);
    // Cofre has no FPS overlay; older builds turned Air's on by default.
    setPrefBool(@"video.performance_hud", NO);
    // Air defaults every download to the BMCLAPI mirror in China. Start on
    // Mojang and the loaders' own servers once, then keep the player's pick.
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (![defaults boolForKey:COFRE_DOWNLOAD_SOURCE_DEFAULTED_KEY]) {
      setPrefObject(@"general.download_source", @"official");
      [defaults setBool:YES forKey:COFRE_DOWNLOAD_SOURCE_DEFAULTED_KEY];
    }
  });
}

UIViewController *CofreMakeRootViewController(void) {
  CofreEnsureStarted();
  Class entry = CofreCoreEntryClass();
  if (!entry) {
    cofreUsingFallbackUI = YES;
    cofreOwnsRootUI = YES;
    cofreOwnsJIT = NO;
    return CofreOwnedFallbackRoot(@"CofreCore could not load. Close and reopen Cofre.");
  }
  UIViewController *root =
      ((id (*)(id, SEL))objc_msgSend)(entry, @selector(rootViewController));
  if (!root) {
    NSLog(@"[Cofre] owned UI fallback reason=start failed");
    cofreUsingFallbackUI = YES;
    root = CofreOwnedFallbackRoot(@"Cofre could not start its interface. Close and reopen Cofre.");
  }
  cofreOwnsJIT = root != nil && !cofreUsingFallbackUI;
  cofreOwnsRootUI = root != nil;
  return root;
}

/// The engine's exit boundary routes into Cofre recovery UI. Called from the
/// exiting thread, which then blocks until the process ends, so the screen goes
/// to the main queue.
BOOL CofreHandleGameExit(int code) {
  if (CofreConsumeLaunchFailure()) {
    NSLog(@"[Cofre] suppressed duplicate recovery UI for a pre-launch failure");
    return YES;
  }
  Class entry = cofreOwnsJIT ? CofreCoreEntryClass() : nil;
  if (!entry) {
    CofreShowOwnedFailure([NSString stringWithFormat:@"Minecraft exited before Cofre could start it (code %d).", code]);
    return YES;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    ((void (*)(id, SEL, int))objc_msgSend)(entry, @selector(handleGameExit:),
                                           code);
  });
  return YES;
}

__attribute__((constructor)) static void CofreStartup(void) {
  cofrePendingURLs = [NSMutableArray array];
  CofreInstallSceneHooks();
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  [center addObserverForName:@"CofreRootReady" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
    cofreRootReady = YES;
    CofreDrainPendingOpenURLs();
  }];
  [center addObserverForName:UIApplicationDidFinishLaunchingNotification
                      object:nil
                       queue:[NSOperationQueue mainQueue]
                  usingBlock:^(__unused NSNotification *note) {
                    CofreEnsureStarted();
                  }];
}
