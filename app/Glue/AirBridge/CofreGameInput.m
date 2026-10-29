#import "CofreGameInput.h"
#import "SurfaceViewController.h"
#import "LauncherPreferences.h"
#import "utils.h"

#include "glfw_keycodes.h"
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
    if (name[0] >= '1' && name[0] <= '9' && name[1] == '\0') return GLFW_KEY_1 + name[0] - '1';
    return GLFW_KEY_UNKNOWN;
}

static void CofreAirInputKey(const char *name, BOOL down) {
    int key = CofreKeyCode(name);
    if (key == GLFW_KEY_UNKNOWN) return;
    CallbackBridge_nativeSendKey(key, 0, down ? 1 : 0, 0);
}

static void CofreAirInputMouseButton(int button, BOOL down) {
    int key = button == 1 ? GLFW_MOUSE_BUTTON_RIGHT : GLFW_MOUSE_BUTTON_LEFT;
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

        UIButton *(^button)(NSString *, SEL) = ^UIButton *(NSString *title, SEL action) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
            b.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
            b.layer.cornerRadius = 8;
            [b setTitle:title forState:UIControlStateNormal];
            [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
            return b;
        };
        UIButton *keyboard = button(@"⌨", @selector(cofreShowKeyboard:));
        UIButton *jump = button(@"JUMP", @selector(cofreJump:));
        UIButton *mode = button(@"AUTO", @selector(cofreMode:));
        for (UIButton *b in @[keyboard, jump, mode]) [overlay addSubview:b];
        keyboard.frame = CGRectMake(16, 16, 56, 42);
        jump.frame = CGRectMake(CGRectGetWidth(container.bounds) - 104, CGRectGetHeight(container.bounds) - 70, 88, 48);
        mode.frame = CGRectMake(84, 16, 72, 42);
        jump.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin;
        NSLog(@"[Cofre] touch overlay installed; Air touch look/tap/hold remains active");
    });
}

+ (void)cofreShowKeyboard:(id)sender { CofreAirInputShowKeyboard(); }
+ (void)cofreJump:(id)sender { CofreAirInputKey("SPACE", YES); CofreAirInputKey("SPACE", NO); }
+ (void)cofreMode:(id)sender { NSLog(@"[Cofre] input mode=auto"); }
@end
