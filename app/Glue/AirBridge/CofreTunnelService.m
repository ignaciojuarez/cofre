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
+ (void)startIfInstalled {
  [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(
                               NSArray *managers, NSError *error) {
    if (error) {
      NSLog(@"[Cofre] tunnel load failed %@", error);
      return;
    }
    NETunnelProviderManager *m = [self cofreManagerFromManagers:managers];
    if (!m || !m.enabled) {
      NSLog(@"[Cofre] tunnel not allowed yet");
      return;
    }
    if (m.connection.status == NEVPNStatusConnected ||
        m.connection.status == NEVPNStatusConnecting)
      return;
    NSError *startError = nil;
    [m.connection startVPNTunnelAndReturnError:&startError];
    if (startError)
      NSLog(@"[Cofre] tunnel start failed %@", startError);
    else
      NSLog(@"[Cofre] tunnel starting");
  }];
}
@end
