#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

static BOOL CofreValidPairing(NSData *data, NSString **udidOut) {
    NSError *error = nil; id obj = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:&error];
    if (![obj isKindOfClass:[NSDictionary class]]) return NO;
    NSDictionary *p = obj; NSArray *required = @[@"HostID", @"HostCertificate", @"HostPrivateKey", @"RootCertificate", @"SystemBUID"];
    for (NSString *key in required) if (!p[key]) return NO;
    NSString *udid = [p[@"UDID"] isKindOfClass:[NSString class]] ? p[@"UDID"] : @"unknown"; if (udidOut) *udidOut = udid; return YES;
}
static void CofreImportPairingURL(NSURL *url) {
    if (!url.isFileURL) return; NSData *data = [NSData dataWithContentsOfURL:url]; NSString *udid = nil; if (!data || !CofreValidPairing(data, &udid)) { NSLog(@"[Cofre] pairing import rejected"); return; }
    NSURL *docs = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject]; NSURL *dir = [docs URLByAppendingPathComponent:@"StikJIT" isDirectory:YES]; NSURL *dst = [dir URLByAppendingPathComponent:@"pairingFile.plist"];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil]; NSURL *tmp = [dir URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]]; if ([data writeToURL:tmp options:NSDataWritingAtomic error:nil]) { chmod(tmp.path.fileSystemRepresentation, 0600); [[NSFileManager defaultManager] removeItemAtURL:dst error:nil]; [[NSFileManager defaultManager] moveItemAtURL:tmp toURL:dst error:nil]; }
    NSString *last4 = udid.length > 4 ? [udid substringFromIndex:udid.length-4] : udid; NSLog(@"[Cofre] pairing imported udid=%@", last4);
}
__attribute__((constructor)) static void CofrePairingImportInstall(void) {
    [[NSNotificationCenter defaultCenter] addObserverForName:UISceneOpenURLContextsNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        for (UIOpenURLContext *context in note.userInfo[UISceneOpenURLContextsKey]) CofreImportPairingURL(context.URL);
    }];
}
