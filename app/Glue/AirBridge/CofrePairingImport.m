#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <sys/stat.h>

static BOOL CofreValidPairing(NSData *data, NSString **udidOut) {
    NSError *error = nil; id obj = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:&error];
    if (![obj isKindOfClass:[NSDictionary class]]) return NO;
    NSDictionary *p = obj;
    for (NSString *key in @[@"HostID", @"SystemBUID", @"UDID"]) if (![p[key] isKindOfClass:[NSString class]] || ![p[key] length] || [p[key] length] > 256) return NO;
    for (NSString *key in @[@"HostCertificate", @"HostPrivateKey", @"RootCertificate", @"RootPrivateKey"]) if (![p[key] isKindOfClass:[NSData class]] || ![p[key] length] || [p[key] length] > 65536) return NO;
    if (udidOut) *udidOut = p[@"UDID"]; return YES;
}
static void CofreImportPairingURL(NSURL *url) {
    if (!url.isFileURL) return; NSData *data = [NSData dataWithContentsOfURL:url]; NSString *udid = nil;
    if (!data || !CofreValidPairing(data, &udid)) { NSLog(@"[Cofre] pairing import rejected"); return; }
    NSFileManager *fm = NSFileManager.defaultManager; NSURL *docs = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject; NSURL *dir = [docs URLByAppendingPathComponent:@"StikJIT" isDirectory:YES]; NSError *error = nil;
    if (![fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionComplete} error:&error]) { NSLog(@"[Cofre] pairing directory failed: %@", error); return; }
    NSURL *tmp = [dir URLByAppendingPathComponent:[NSString stringWithFormat:@".%@.tmp", NSUUID.UUID.UUIDString]]; NSURL *dst = [dir URLByAppendingPathComponent:@"pairingFile.plist"];
    if (![data writeToURL:tmp options:NSDataWritingAtomic | NSDataWritingFileProtectionComplete error:&error] || chmod(tmp.path.fileSystemRepresentation, 0600) != 0) { NSLog(@"[Cofre] pairing temp write failed: %@", error); [fm removeItemAtURL:tmp error:NULL]; return; }
    if ([fm fileExistsAtPath:dst.path]) { if (![fm replaceItemAtURL:dst withItemAtURL:tmp backupItemName:nil options:NSFileManagerItemReplacementUsingNewMetadataOnly resultingItemURL:NULL error:&error]) { NSLog(@"[Cofre] pairing replace failed: %@", error); [fm removeItemAtURL:tmp error:NULL]; return; } }
    else if (![fm moveItemAtURL:tmp toURL:dst error:&error]) { NSLog(@"[Cofre] pairing install failed: %@", error); [fm removeItemAtURL:tmp error:NULL]; return; }
    NSLog(@"[Cofre] pairing imported udid=%@", udid.length > 4 ? [udid substringFromIndex:udid.length - 4] : udid);
}
__attribute__((constructor)) static void CofrePairingImportInstall(void) {
    [[NSNotificationCenter defaultCenter] addObserverForName:@"UISceneOpenURLContextsNotification" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
        for (UIOpenURLContext *c in n.userInfo[@"UISceneOpenURLContextsKey"]) CofreImportPairingURL(c.URL);
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UISceneWillConnectNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
        UISceneConnectionOptions *options = n.userInfo[@"UISceneConnectionOptionsKey"];
        for (UIOpenURLContext *c in options.URLContexts) CofreImportPairingURL(c.URL);
    }];
}
