#import "AirBridgeAdapter.h"
#import "CofreTunnelService.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/message.h>

static Class CofreCoreClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("@executable_path/Frameworks/CofreCore.framework/CofreCore", RTLD_NOW | RTLD_LOCAL);
        if (!handle) NSLog(@"[Cofre] UI fallback reason=framework missing");
        cls = NSClassFromString(@"CofreCoreEntry");
        if (!cls) NSLog(@"[Cofre] UI fallback reason=class missing");
    });
    return cls;
}

static void CofreStartAfterLaunch(void) {
    CofreAirBridgeAdapter *bridge = [CofreAirBridgeAdapter new];
    Class cls = CofreCoreClass();
    if (cls) {
        ((void (*)(id, SEL, id))objc_msgSend)(cls, @selector(startWithBridge:), bridge);
        if (!((id (*)(id, SEL))objc_msgSend)(cls, @selector(rootViewController))) NSLog(@"[Cofre] UI fallback reason=start failed");
        [bridge ensureAutomaticMemoryDefault];
    }
    [CofreTunnelService installAndStart];
}

__attribute__((constructor)) static void CofreStartup(void) {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) { CofreStartAfterLaunch(); }];
}

UIViewController *CofreMakeRootViewController(void) {
    Class cls = CofreCoreClass();
    if (!cls) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(cls, @selector(rootViewController));
}
