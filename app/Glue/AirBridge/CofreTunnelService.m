#import "CofreTunnelService.h"
#import "CofreConstants.h"
@implementation CofreTunnelService
+ (NETunnelProviderManager *)cofreManagerFromManagers:
    (NSArray<NETunnelProviderManager *> *)managers {
  for (NETunnelProviderManager *m in managers)
    if ([m.protocolConfiguration
            isKindOfClass:NETunnelProviderProtocol.class] &&
        [((NETunnelProviderProtocol *)m.protocolConfiguration)
                .providerBundleIdentifier
            isEqualToString:COFRE_TUNNEL_BUNDLE_ID])
      return m;
  return nil;
}
+ (void)installAndStart {
  [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(
                               NSArray *managers, NSError *error) {
    if (error) {
      NSLog(@"[Cofre] tunnel load failed %@", error);
      return;
    }
    NETunnelProviderManager *m = [self cofreManagerFromManagers:managers]
                                     ?: [NETunnelProviderManager new];
    NETunnelProviderProtocol *p =
        [m.protocolConfiguration isKindOfClass:NETunnelProviderProtocol.class]
            ? (id)m.protocolConfiguration
            : [NETunnelProviderProtocol new];
    p.providerBundleIdentifier = COFRE_TUNNEL_BUNDLE_ID;
    p.serverAddress = COFRE_TUNNEL_ADDRESS;
    m.protocolConfiguration = p;
    m.localizedDescription = @"Cofre loopback";
    m.enabled = YES;
    [m saveToPreferencesWithCompletionHandler:^(NSError *e) {
      if (e) {
        NSLog(@"[Cofre] tunnel save failed %@", e);
        return;
      }
      [m loadFromPreferencesWithCompletionHandler:^(NSError *e2) {
        if (e2) {
          NSLog(@"[Cofre] tunnel reload failed %@", e2);
          return;
        }
        if (![self cofreManagerFromManagers:@[ m ]]) {
          NSLog(@"[Cofre] tunnel identity changed after reload");
          return;
        }
        NSError *startError = nil;
        [m.connection startVPNTunnelAndReturnError:&startError];
        if (startError)
          NSLog(@"[Cofre] tunnel start failed %@", startError);
      }];
    }];
  }];
}
@end
