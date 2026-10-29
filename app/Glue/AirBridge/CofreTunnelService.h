#import <Foundation/Foundation.h>
#import <NetworkExtension/NetworkExtension.h>
@interface CofreTunnelService : NSObject
+ (NETunnelProviderManager *)cofreManagerFromManagers:
    (NSArray<NETunnelProviderManager *> *)managers;
/// Starts Cofre's VPN if the user already allowed it. Setup's VPN step
/// (CofreVPN.swift) creates the configuration, so launch never asks.
+ (void)startIfInstalled;
@end
