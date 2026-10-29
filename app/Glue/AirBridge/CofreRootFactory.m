#import <UIKit/UIKit.h>
UIViewController *CofreMakeRootViewController(void) {
    Class cls = NSClassFromString(@"Cofre.CofreRootViewController");
    if (!cls) cls = NSClassFromString(@"CofreRootViewController");
    return cls ? [cls new] : nil;
}
