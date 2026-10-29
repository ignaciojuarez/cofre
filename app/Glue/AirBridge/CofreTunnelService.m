#import "CofreTunnelService.h"
#import <NetworkExtension/NetworkExtension.h>
@implementation CofreTunnelService
+ (void)installAndStart {
    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray<NETunnelProviderManager *> *managers, NSError *error) {
        NETunnelProviderManager *m = managers.firstObject ?: [NETunnelProviderManager new];
        NETunnelProviderProtocol *p = [NETunnelProviderProtocol new];
        p.providerBundleIdentifier = @"com.ignaciojuarez.cofre.tunnel";
        p.serverAddress = @"10.7.0.1";
        m.protocolConfiguration = p; m.localizedDescription = @"Cofre loopback"; m.enabled = YES;
        [m saveToPreferencesWithCompletionHandler:^(NSError *saveError) {
            if (saveError) { NSLog(@"[Cofre] tunnel save failed %@", saveError); return; }
            [m loadFromPreferencesWithCompletionHandler:^(NSError *loadError) {
                if (loadError) { NSLog(@"[Cofre] tunnel reload failed %@", loadError); return; }
                NSError *startError = nil; [m.connection startVPNTunnelAndReturnError:&startError];
                if (startError) NSLog(@"[Cofre] tunnel start failed %@", startError);
                else NSLog(@"[Cofre] tunnel requested 10.7.0.1");
            }];
        }];
    }];
}
@end
