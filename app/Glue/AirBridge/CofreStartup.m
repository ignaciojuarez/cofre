#import "AirBridgeAdapter.h"
#import "PLProfiles.h"
#import "CofreTunnelService.h"
#import <UIKit/UIKit.h>
static void CofreStartAfterLaunch(void) {
    @autoreleasepool {
        CofreAirBridgeAdapter *bridge = [CofreAirBridgeAdapter new];
        [bridge ensureAutomaticMemoryDefault];
        NSArray *instances = [bridge instances]; NSString *profile = bridge.profiles.selectedProfileName;
        NSLog(@"[Cofre] AirBridge connected instances=%lu profile=%@", (unsigned long)instances.count, profile ?: @"(none)");
        if (profile.length) [bridge worldsForProfile:profile completion:^(NSArray *worlds){ NSLog(@"[Cofre] worlds=%lu", (unsigned long)worlds.count); }];
        [CofreTunnelService installAndStart];
    }
}

__attribute__((constructor)) static void CofreStartup(void) {
    // Air's globals and profile services are initialized by UIApplication startup.
    // Defer until the launch notification instead of touching them from a Mach-O
    // constructor (which can run before ObjC singletons are ready).
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                       object:nil
                                                        queue:[NSOperationQueue mainQueue]
                                                   usingBlock:^(__unused NSNotification *note) {
        CofreStartAfterLaunch();
    }];
}
