#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Input event seam used by CofreGameInput.swift and the touch overlay.
// These five functions are implemented by the framework shim and delivered to
// Air through notifications. The Air-side implementation keeps the callback
// bridge private to the game executable.
void CofreInputKey(const char *name, BOOL down);
void CofreInputMouseButton(int button, BOOL down);
void CofreInputLook(float deltaX, float deltaY);
void CofreInputShowKeyboard(void);
void CofreInputHideKeyboard(void);

/// Called by Air's SDL hook when Minecraft starts/stops text input.
void CofreSDLTextInputStateChanged(BOOL active, const char *reason);
void CofreTextInputAreaDidChange(BOOL ready);
BOOL CofreShouldShowTextInput(void);

@interface CofreGameOverlayHost : NSObject
+ (void)installOnSurface:(UIViewController *)surface;
@end

NS_ASSUME_NONNULL_END
