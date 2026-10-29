#import <Foundation/Foundation.h>
#import <NetworkExtension/NetworkExtension.h>
@interface CofreTunnelService : NSObject
+ (NETunnelProviderManager *)cofreManagerFromManagers:
    (NSArray<NETunnelProviderManager *> *)managers;
+ (void)installAndStart;
@end
