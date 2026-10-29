// Starts Cofre inside Air's executable: loads CofreCore.framework (our Swift UI
// and backend), hands it the Air bridge, and starts the VPN if allowed. Air's
// SceneDelegate (patch 0002) asks CofreMakeRootViewController() for the root
// screen and falls back to Air's UI on nil.
#import "AirBridgeAdapter.h"
#import "CofreTunnelService.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/message.h>

static NSString *const CofreCorePath =
    @"@executable_path/Frameworks/CofreCore.framework/CofreCore";

static BOOL cofreOwnsJIT = NO;

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

__attribute__((constructor)) static void CofreStartup(void) {
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  [center addObserverForName:UIApplicationDidFinishLaunchingNotification
                      object:nil
                       queue:[NSOperationQueue mainQueue]
                  usingBlock:^(__unused NSNotification *note) {
                    CofreEnsureStarted();
                    [CofreTunnelService startIfInstalled];
                  }];
}
