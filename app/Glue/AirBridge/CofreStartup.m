// Starts Cofre inside Air's executable: loads CofreCore.framework (our Swift UI
// and backend), hands it the Air bridge, and starts the VPN if allowed. Air's
// SceneDelegate (patch 0002) asks CofreMakeRootViewController() for the root
// screen and falls back to Air's UI on nil.
#import "AirBridgeAdapter.h"
#import "CofreTunnelService.h"
#import "LauncherPreferences.h"
#import "utils.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const CofreCorePath =
    @"@executable_path/Frameworks/CofreCore.framework/CofreCore";

static BOOL cofreOwnsJIT = NO;
static NSMutableArray<NSURL *> *cofrePendingURLs;
static BOOL cofreRootReady = NO;
static NSString *const CofreOpenURLNotification = @"CofreOpenURL";

static void CofreReceiveURL(NSURL *url) {
  if (!url) return;
  NSLog(@"[Cofre] open url scheme=%@", url.scheme.lowercaseString ?: @"");
  dispatch_async(dispatch_get_main_queue(), ^{
    if (cofreRootReady) {
      [[NSNotificationCenter defaultCenter] postNotificationName:CofreOpenURLNotification object:url];
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
      [[NSNotificationCenter defaultCenter] postNotificationName:CofreOpenURLNotification object:url];
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

/// Loads CofreCore once and returns its entry class, or nil (logging why) if it
/// can't be loaded.
static Class CofreCoreEntryClass(void) {
  static Class entry;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    void *handle = dlopen(CofreCorePath.UTF8String, RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
      NSLog(@"[Cofre] UI fallback reason=framework missing (%s)", dlerror());
      return;
    }
    entry = NSClassFromString(@"CofreCoreEntry");
    if (!entry) {
      NSLog(@"[Cofre] UI fallback reason=class missing");
    }
  });
  return entry;
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
    CofreAirBridgeAdapter *bridge = [CofreAirBridgeAdapter new];
    ((void (*)(id, SEL, id))objc_msgSend)(entry, @selector(startWithBridge:),
                                          bridge);
    [bridge ensureAutomaticMemoryDefault];
    CofreConfigureAirJIT();
    CofreWatchLifecycle();
    // The game owns VSync and its frame limit in options.txt. With this Air setting on, Air's Java launcher
    // overwrites both (VSync off, 260 FPS) at every launch, undoing what the player picked in game.
    setPrefBool(@"video.disable_game_vsync", NO);
    // Air defaults every download to the BMCLAPI mirror in China; use Mojang and the loaders' own servers first.
    setPrefObject(@"general.download_source", @"official");
  });
}

UIViewController *CofreMakeRootViewController(void) {
  CofreEnsureStarted();
  Class entry = CofreCoreEntryClass();
  if (!entry) {
    return nil;
  }
  UIViewController *root =
      ((id (*)(id, SEL))objc_msgSend)(entry, @selector(rootViewController));
  if (!root) {
    NSLog(@"[Cofre] UI fallback reason=start failed");
  }
  cofreOwnsJIT = root != nil;
  return root;
}

/// Air's handleExitCode: asks first (patch 0004). With Cofre's UI up, Cofre
/// shows the exit (its launch screen before the first frame, its crash screen
/// after) and Air's crash screen stays hidden. Called from the exiting thread,
/// which then blocks until the process ends, so the screen goes to the main
/// queue.
BOOL CofreHandleGameExit(int code) {
  Class entry = cofreOwnsJIT ? CofreCoreEntryClass() : nil;
  if (!entry) {
    return NO;
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
                    [CofreTunnelService startIfInstalled];
                  }];
}
