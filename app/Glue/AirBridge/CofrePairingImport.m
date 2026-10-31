#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <dlfcn.h>

static const NSUInteger kCofreMaxPairingFileSize = 4 * 1024 * 1024;

/// Imports a user-selected pairing file through the shared Swift validator and
/// writer.
static void CofreImportPairingURL(NSURL *url) {
  if (!url.isFileURL) {
    return;
  }
  NSNumber *fileSize = nil;
  if (![url getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil] ||
      fileSize.unsignedIntegerValue > kCofreMaxPairingFileSize) {
    NSLog(@"[Cofre] pairing import rejected: file too large");
    return;
  }
  NSData *data = [NSData dataWithContentsOfURL:url];
  bool (*importer)(const void *, long) =
      dlsym(RTLD_DEFAULT, "CofreImportPairingData");
  if (!data || data.length > kCofreMaxPairingFileSize || !importer ||
      !importer(data.bytes, (long)data.length)) {
    NSLog(@"[Cofre] pairing import rejected");
  }
}

__attribute__((constructor)) static void CofrePairingImportInstall(void) {
  [[NSNotificationCenter defaultCenter]
      addObserverForName:@"UISceneOpenURLContextsNotification"
                  object:nil
                   queue:NSOperationQueue.mainQueue
              usingBlock:^(NSNotification *notification) {
                for (UIOpenURLContext *context in notification
                         .userInfo[@"UISceneOpenURLContextsKey"]) {
                  CofreImportPairingURL(context.URL);
                }
              }];
  [[NSNotificationCenter defaultCenter]
      addObserverForName:UISceneWillConnectNotification
                  object:nil
                   queue:NSOperationQueue.mainQueue
              usingBlock:^(NSNotification *notification) {
                UISceneConnectionOptions *options =
                    notification.userInfo[@"UISceneConnectionOptionsKey"];
                for (UIOpenURLContext *context in options.URLContexts) {
                  CofreImportPairingURL(context.URL);
                }
              }];
}
