#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

static BOOL CofreValidPairing(NSData *data, NSString **udidOut) {
    NSError *error = nil;
    id obj = [NSPropertyListSerialization propertyListWithData:data
                                                       options:NSPropertyListImmutable
                                                        format:nil
                                                         error:&error];
    if (![obj isKindOfClass:[NSDictionary class]]) {
        return NO;
    }
    NSDictionary *p = (NSDictionary *)obj;
    NSArray *required = @[
        @"HostID",
        @"HostCertificate",
        @"HostPrivateKey",
        @"RootCertificate",
        @"SystemBUID"
    ];
    for (NSString *key in required) {
        if (!p[key]) {
            return NO;
        }
    }
    // Type checks for critical cryptographic keys
    if (![p[@"HostCertificate"] isKindOfClass:[NSData class]] ||
        ![p[@"HostPrivateKey"] isKindOfClass:[NSData class]] ||
        ![p[@"RootCertificate"] isKindOfClass:[NSData class]]) {
        return NO;
    }

    NSString *udid = [p[@"UDID"] isKindOfClass:[NSString class]] ? p[@"UDID"] : @"unknown";
    if (udidOut) {
        *udidOut = udid;
    }
    return YES;
}

static void CofreImportPairingURL(NSURL *url) {
    if (!url || !url.isFileURL) {
        return;
    }
    NSData *data = [NSData dataWithContentsOfURL:url];
    NSString *udid = nil;
    if (!data || !CofreValidPairing(data, &udid)) {
        NSLog(@"[Cofre] pairing import rejected");
        return;
    }

    NSURL *docs = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
    NSURL *dir = [docs URLByAppendingPathComponent:@"StikJIT" isDirectory:YES];
    NSURL *dst = [dir URLByAppendingPathComponent:@"pairingFile.plist"];

    [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *tmp = [dir URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];

    NSDictionary *attrs = @{NSFileProtectionKey: NSFileProtectionComplete};
    if ([[NSFileManager defaultManager] createFileAtPath:tmp.path contents:data attributes:attrs]) {
        chmod(tmp.path.fileSystemRepresentation, 0600);
        [[NSFileManager defaultManager] removeItemAtURL:dst error:nil];
        [[NSFileManager defaultManager] moveItemAtURL:tmp toURL:dst error:nil];
    } else if ([data writeToURL:tmp options:NSDataWritingAtomic | NSDataWritingFileProtectionComplete error:nil]) {
        chmod(tmp.path.fileSystemRepresentation, 0600);
        [[NSFileManager defaultManager] removeItemAtURL:dst error:nil];
        [[NSFileManager defaultManager] moveItemAtURL:tmp toURL:dst error:nil];
    }

    NSString *last4 = udid.length > 4 ? [udid substringFromIndex:udid.length - 4] : udid;
    NSLog(@"[Cofre] pairing imported udid=%@", last4);
}

__attribute__((constructor)) static void CofrePairingImportInstall(void) {
    [[NSNotificationCenter defaultCenter] addObserverForName:UISceneOpenURLContextsNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        NSArray<UIOpenURLContext *> *contexts = note.userInfo[UISceneOpenURLContextsKey];
        for (UIOpenURLContext *context in contexts) {
            CofreImportPairingURL(context.URL);
        }
    }];

    [[NSNotificationCenter defaultCenter] addObserverForName:UISceneWillConnectNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        UISceneConnectionOptions *options = note.userInfo[UISceneConnectionOptionsKey];
        if (options && options.URLContexts) {
            for (UIOpenURLContext *context in options.URLContexts) {
                CofreImportPairingURL(context.URL);
            }
        }
    }];
}
