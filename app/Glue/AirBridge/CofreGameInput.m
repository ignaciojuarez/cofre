#import "CofreGameInput.h"
#import "SurfaceViewController.h"
#import "LauncherPreferences.h"
#import "utils.h"

#include "glfw_keycodes.h"
#include <objc/message.h>
#include <objc/runtime.h>
#include <string.h>
#include <stdatomic.h>

static _Atomic(BOOL) cofreTextInputAreaReady = NO;

void CofreTextInputAreaDidChange(BOOL ready) {
    atomic_store(&cofreTextInputAreaReady, ready);
}

BOOL CofreShouldShowTextInput(void) {
    return atomic_load(&cofreTextInputAreaReady);
}

static int CofreKeyCode(const char *name) {
    if (name == NULL) return GLFW_KEY_UNKNOWN;
    if (strcmp(name, "W") == 0) return GLFW_KEY_W;
    if (strcmp(name, "A") == 0) return GLFW_KEY_A;
    if (strcmp(name, "S") == 0) return GLFW_KEY_S;
    if (strcmp(name, "D") == 0) return GLFW_KEY_D;
    if (strcmp(name, "SPACE") == 0) return GLFW_KEY_SPACE;
    if (strcmp(name, "SHIFT") == 0) return GLFW_KEY_LEFT_SHIFT;
    if (strcmp(name, "CTRL") == 0) return GLFW_KEY_LEFT_CONTROL;
    if (strcmp(name, "E") == 0) return GLFW_KEY_E;
    if (strcmp(name, "T") == 0) return GLFW_KEY_T;
    if (strcmp(name, "Q") == 0) return GLFW_KEY_Q;
    if (strcmp(name, "ESC") == 0) return GLFW_KEY_ESCAPE;
    if (strcmp(name, "F5") == 0) return GLFW_KEY_F5;
    if (strcmp(name, "F1") == 0) return GLFW_KEY_F1;
    if (strcmp(name, "TAB") == 0) return GLFW_KEY_TAB;
    if (strcmp(name, "F") == 0) return GLFW_KEY_F;
    if (name[0] >= '1' && name[0] <= '9' && name[1] == '\0') return GLFW_KEY_1 + name[0] - '1';
    return GLFW_KEY_UNKNOWN;
}

static void CofreAirInputKey(const char *name, BOOL down) {
    int key = CofreKeyCode(name);
    if (key == GLFW_KEY_UNKNOWN) return;
    CallbackBridge_nativeSendKey(key, 0, down ? 1 : 0, 0);
}

static void CofreAirInputMouseButton(int button, BOOL down) {
    int key = button == 1 ? GLFW_MOUSE_BUTTON_RIGHT : button == 2 ? GLFW_MOUSE_BUTTON_MIDDLE : GLFW_MOUSE_BUTTON_LEFT;
    CallbackBridge_nativeSendMouseButton(key, down ? 1 : 0, 0);
}

static void CofreAirInputLook(float deltaX, float deltaY) {
    CallbackBridge_nativeSendCursorPos(ACTION_MOVE_MOTION, deltaX, deltaY);
}

static void CofreAirInputShowKeyboard(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        SurfaceViewController *surface = [SurfaceViewController currentInstance];
        if (!surface) return;
        @try {
            id field = [surface valueForKey:@"inputTextField"];
            [field setAlpha:1.0];
            [field becomeFirstResponder];
            [field setText:@" "];
            NSLog(@"[Cofre] keyboard show reason=manual");
        } @catch (NSException *exception) {
            NSLog(@"[Cofre] keyboard manual failed=%@", exception.reason);
        }
    });
}

static void CofreAirInputHideKeyboard(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        SurfaceViewController *surface = [SurfaceViewController currentInstance];
        if (!surface) return;
        @try {
            id field = [surface valueForKey:@"inputTextField"];
            if ([field isFirstResponder]) {
                [field resignFirstResponder];
            }
            NSLog(@"[Cofre] keyboard hide");
        } @catch (NSException *exception) {
            NSLog(@"[Cofre] keyboard hide failed=%@", exception.reason);
        }
    });
}

void CofreInputKey(const char *name, BOOL down) { CofreAirInputKey(name, down); }
void CofreInputMouseButton(int button, BOOL down) { CofreAirInputMouseButton(button, down); }
void CofreInputLook(float deltaX, float deltaY) { CofreAirInputLook(deltaX, deltaY); }
void CofreInputShowKeyboard(void) { CofreAirInputShowKeyboard(); }
void CofreInputHideKeyboard(void) { CofreAirInputHideKeyboard(); }
void CofreInputScroll(int steps) { CallbackBridge_nativeSendScroll(0, steps); }

NSDictionary<NSString *, NSNumber *> *CofreGameScreenState(void) {
    // isGrabbing: Minecraft grabbed the cursor, so the player is in the world (no screen open).
    // guiScale is kept current by Air from options.txt; windowWidth is the game's framebuffer width in pixels.
    CGFloat points = SurfaceViewController.currentInstance.view.bounds.size.width;
    double pixelsPerPoint = points > 0 && windowWidth > 0 ? windowWidth / points : 0;
    return @{
        @"inWorld": @(isGrabbing == JNI_TRUE),
        @"guiScale": @(guiScale),
        @"pixelsPerPoint": @(pixelsPerPoint),
    };
}

void CofreSDLTextInputStateChanged(BOOL active, const char *reason) {
    NSString *why = reason ? [NSString stringWithUTF8String:reason] : @"sdl";
    dispatch_async(dispatch_get_main_queue(), ^{
        if (active) {
            NSLog(@"[Cofre] keyboard show reason=%@", why);
        } else {
            NSLog(@"[Cofre] keyboard hide");
        }
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"CofreSDLTextInputStateChanged"
                          object:nil
                        userInfo:@{@"active": @(active), @"reason": why}];
    });
}

// MARK: Touch diagnostics: where touches land and what sits on top, so "nothing responds" reports have evidence.

static int cofreTouchLogsLeft = 30;
static void (*CofreOriginalSendEvent)(id, SEL, UIEvent *);

static NSString *CofreViewChain(UIView *view) {
    NSMutableArray *names = [NSMutableArray array];
    for (int i = 0; view && i < 6; i++, view = view.superview) [names addObject:NSStringFromClass(view.class)];
    return [names componentsJoinedByString:@" < "];
}

static void CofreDiagnosticSendEvent(UIWindow *window, SEL cmd, UIEvent *event) {
    if (event.type == UIEventTypeTouches && cofreTouchLogsLeft > 0) {
        for (UITouch *touch in event.allTouches) {
            if (touch.phase != UITouchPhaseBegan || cofreTouchLogsLeft <= 0) continue;
            cofreTouchLogsLeft--;
            CGPoint p = [touch locationInView:window];
            NSLog(@"[Cofre] diag touch window=%@ level=%.0f key=%d at=%.0f,%.0f view=%@",
                  NSStringFromClass(window.class), window.windowLevel, window.isKeyWindow, p.x, p.y,
                  CofreViewChain(touch.view));
        }
    }
    CofreOriginalSendEvent(window, cmd, event);
}

static void CofreDumpTouchState(NSString *when) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            NSLog(@"[Cofre] diag %@ window=%@ level=%.0f hidden=%d alpha=%.2f key=%d touch=%d root=%@ presented=%@ frame=%@",
                  when, NSStringFromClass(w.class), w.windowLevel, w.hidden, w.alpha, w.isKeyWindow,
                  w.userInteractionEnabled, NSStringFromClass(w.rootViewController.class),
                  NSStringFromClass(w.rootViewController.presentedViewController.class),
                  NSStringFromCGRect(w.frame));
        }
    }
    UIView *game = SurfaceViewController.currentInstance.view;
    for (UIView *v in game.subviews) {
        NSLog(@"[Cofre] diag %@ game.subview=%@ hidden=%d alpha=%.2f touch=%d frame=%@", when,
              NSStringFromClass(v.class), v.hidden, v.alpha, v.userInteractionEnabled, NSStringFromCGRect(v.frame));
    }
}

static void CofreStartTouchDiagnostics(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Method m = class_getInstanceMethod(UIWindow.class, @selector(sendEvent:));
        CofreOriginalSendEvent = (void (*)(id, SEL, UIEvent *))method_setImplementation(m, (IMP)CofreDiagnosticSendEvent);
    });
    for (NSNumber *delay in @[@3, @15, @40]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ CofreDumpTouchState([NSString stringWithFormat:@"t+%@s", delay]); });
    }
}

@interface CofreGameOverlayView : UIView
@end

@implementation CofreGameOverlayView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

@implementation CofreGameOverlayHost
+ (void)installOnSurface:(UIViewController *)surface {
    if (![surface isKindOfClass:SurfaceViewController.class]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        SurfaceViewController *game = (SurfaceViewController *)surface;
        CofreStartTouchDiagnostics();
        UIView *container = game.view;
        if (!container) return;
        for (UIView *view in container.subviews) {
            if ([view isKindOfClass:CofreGameOverlayView.class]) return;
        }

        // Prefs disable Air's HUD/menu; the control view is hidden only because Air
        // has no "no controls" layout. The underlying touch view remains untouched.
        setPrefBool(@"control.menu_button_visible", NO);
        setPrefBool(@"video.performance_hud", NO);
        game.ctrlView.hidden = YES;
        game.gameMenuOverlay.hidden = YES;

        CofreGameOverlayView *overlay = [[CofreGameOverlayView alloc] initWithFrame:container.bounds];
        overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        overlay.userInteractionEnabled = YES;
        overlay.backgroundColor = UIColor.clearColor;
        [container addSubview:overlay];

        // Cofre's SwiftUI overlay (CofreCore.framework) owns world touches; menus and the hotbar fall through
        // to Air, so Air's hotbar taps must stay on.
        setPrefBool(@"control.gesture_hotbar", YES);
        Class entry = NSClassFromString(@"CofreCoreEntry");
        SEL make = NSSelectorFromString(@"touchOverlay");
        UIViewController *touch = [entry respondsToSelector:make]
            ? ((UIViewController *(*)(id, SEL))objc_msgSend)(entry, make) : nil;
        if (!touch) {
            NSLog(@"[Cofre] touch overlay missing; Air touch remains active");
            return;
        }
        [game addChildViewController:touch];
        touch.view.frame = overlay.bounds;
        touch.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [overlay addSubview:touch.view];
        [touch didMoveToParentViewController:game];
        NSLog(@"[Cofre] touch overlay installed");
    });
}

@end
