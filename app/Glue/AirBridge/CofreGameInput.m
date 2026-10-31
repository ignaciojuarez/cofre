#import "CofreGameInput.h"
#import "SurfaceViewController.h"
#import "LauncherPreferences.h"
#import "utils.h"

#include "glfw_keycodes.h"
#include <objc/message.h>
#include <stdlib.h>
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
    if (strcmp(name, "G") == 0) return GLFW_KEY_G;
    if (strcmp(name, "ESC") == 0) return GLFW_KEY_ESCAPE;
    if (strcmp(name, "F2") == 0) return GLFW_KEY_F2;
    if (strcmp(name, "F3") == 0) return GLFW_KEY_F3;
    if (strcmp(name, "F5") == 0) return GLFW_KEY_F5;
    if (strcmp(name, "F1") == 0) return GLFW_KEY_F1;
    if (strcmp(name, "TAB") == 0) return GLFW_KEY_TAB;
    if (strcmp(name, "F") == 0) return GLFW_KEY_F;
    if (strcmp(name, "ALT") == 0) return GLFW_KEY_LEFT_ALT;
    if (strcmp(name, "ENTER") == 0) return GLFW_KEY_ENTER;
    if (strcmp(name, "BACKSPACE") == 0) return GLFW_KEY_BACKSPACE;
    if (strcmp(name, "UP") == 0) return GLFW_KEY_DPAD_UP;
    if (strcmp(name, "DOWN") == 0) return GLFW_KEY_DPAD_DOWN;
    if (strcmp(name, "LEFT") == 0) return GLFW_KEY_DPAD_LEFT;
    if (strcmp(name, "RIGHT") == 0) return GLFW_KEY_DPAD_RIGHT;
    if (name[0] >= '0' && name[0] <= '9' && name[1] == '\0') return GLFW_KEY_0 + name[0] - '0';
    if (name[0] >= 'A' && name[0] <= 'Z' && name[1] == '\0') return GLFW_KEY_A + name[0] - 'A';
    // F1–F12 are contiguous in GLFW.
    if (name[0] == 'F' && name[1] >= '1' && name[1] <= '9') {
        int n = atoi(name + 1);
        if (n >= 1 && n <= 12) return GLFW_KEY_F1 + n - 1;
    }
    return GLFW_KEY_UNKNOWN;
}

static void CofreAirInputKey(const char *name, BOOL down) {
    int key = CofreKeyCode(name);
    if (key == GLFW_KEY_UNKNOWN) return;
    CallbackBridge_nativeSendKey(key, 0, down ? 1 : 0, 0);
}

static void CofreAirInputMouseButton(int button, BOOL down) {
    if (button < 0 || button > 2) return;
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

// The keyboard can belong to Air's text field or to SDL's (MC 26.3+), so find whoever holds it.
static __weak UIResponder *cofreFirstResponder;

@interface UIResponder (CofreFirstResponder)
- (void)cofre_captureFirstResponder:(id)sender;
@end

@implementation UIResponder (CofreFirstResponder)
- (void)cofre_captureFirstResponder:(id)sender { cofreFirstResponder = self; }
@end

static UIResponder *CofreCurrentFirstResponder(void) {
    cofreFirstResponder = nil;
    [UIApplication.sharedApplication sendAction:@selector(cofre_captureFirstResponder:) to:nil from:nil forEvent:nil];
    return cofreFirstResponder;
}

static void CofreAirInputHideKeyboard(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIResponder *responder = CofreCurrentFirstResponder();
        // Air's TrackedTextField refuses to resign while this guard is on; Air's own toggle lifts it the same way.
        BOOL guarded = [responder respondsToSelector:NSSelectorFromString(@"setPreventUnexpectedResign:")];
        if (guarded) [responder setValue:@NO forKey:@"preventUnexpectedResign"];
        BOOL resigned = [responder resignFirstResponder];
        if (guarded) [responder setValue:@YES forKey:@"preventUnexpectedResign"];
        NSLog(@"[Cofre] keyboard hide responder=%@ resigned=%d", NSStringFromClass(responder.class), resigned);
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
    if (active) {
        NSLog(@"[Cofre] keyboard show reason=%@", why);
    } else {
        NSLog(@"[Cofre] keyboard hide reason=%@", why);
    }
}

@interface CofreGameOverlayView : UIView
@property(nonatomic, weak) SurfaceViewController *game;
@end

// Air's rotation handler resizes its root view by bounds only, so after a portrait-to-landscape turn the game picture
// keeps the portrait center and sits in the lower left. Pin it back to the top left.
static void CofreAnchorGameRoot(SurfaceViewController *game) {
    UIView *root = game.rootView;
    CGPoint anchored = CGPointMake(CGRectGetMidX(root.bounds), CGRectGetMidY(root.bounds));
    if (!root || CGPointEqualToPoint(root.center, anchored)) return;
    NSLog(@"[Cofre] game root re-anchored from=%@ size=%@", NSStringFromCGPoint(root.frame.origin),
          NSStringFromCGSize(root.bounds.size));
    root.center = anchored;
}

@implementation CofreGameOverlayView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    SurfaceViewController *game = self.game;
    CofreAnchorGameRoot(game);
    // Air's rotation block may set the bounds after this layout pass.
    dispatch_async(dispatch_get_main_queue(), ^{ CofreAnchorGameRoot(game); });
}
@end

@implementation CofreGameOverlayHost
+ (void)installOnSurface:(UIViewController *)surface {
    if (![surface isKindOfClass:SurfaceViewController.class]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        SurfaceViewController *game = (SurfaceViewController *)surface;
        UIView *container = game.view;
        if (!container) return;
        for (UIView *view in container.subviews) {
            if ([view isKindOfClass:CofreGameOverlayView.class]) return;
        }

        // Find and install Cofre's overlay before hiding Air's controls. If the framework is unavailable, Air's
        // controls must remain usable as the fallback.
        Class entry = NSClassFromString(@"CofreCoreEntry");
        SEL make = NSSelectorFromString(@"touchOverlay");
        UIViewController *touch = [entry respondsToSelector:make]
            ? ((UIViewController *(*)(id, SEL))objc_msgSend)(entry, make) : nil;
        UIView *touchView = touch.view;
        if (!touch || !touchView) {
            NSLog(@"[Cofre] touch overlay failed reason=missing");
            return;
        }

        CofreGameOverlayView *overlay = [[CofreGameOverlayView alloc] initWithFrame:container.bounds];
        overlay.game = game;
        overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        overlay.userInteractionEnabled = YES;
        overlay.backgroundColor = UIColor.clearColor;
        BOOL ctrlHidden = game.ctrlView.hidden;
        BOOL menuHidden = game.gameMenuOverlay.hidden;
        @try {
            [game addChildViewController:touch];
            touchView.frame = overlay.bounds;
            touchView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [overlay addSubview:touchView];
            [container addSubview:overlay];
            [touch didMoveToParentViewController:game];
        } @catch (NSException *exception) {
            [touchView removeFromSuperview];
            [touch removeFromParentViewController];
            [overlay removeFromSuperview];
            game.ctrlView.hidden = ctrlHidden;
            game.gameMenuOverlay.hidden = menuHidden;
            NSLog(@"[Cofre] touch overlay failed reason=%@", exception.reason ?: @"install");
            return;
        }

        // Cofre's SwiftUI overlay owns every world touch, the hotbar included; game screens fall through to Air.
        setPrefBool(@"control.menu_button_visible", NO);
        setPrefBool(@"video.performance_hud", NO);
        setPrefBool(@"control.hardware_hide", NO);
        // ⌨ in the overlay is the only keyboard toggle; Air's two-finger tap would open it behind Cofre's back.
        setPrefBool(@"control.two_finger_keyboard", NO);
        game.ctrlView.hidden = YES;
        game.gameMenuOverlay.hidden = YES;
        NSLog(@"[Cofre] touch overlay installed");
    });
}

@end
