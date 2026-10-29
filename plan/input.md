# Cofre game input

## Findings

- Minecraft 26.3 uses `com.mojang.blaze3d.platform.TextInputManager`. `startTextInput(owner)` calls `SDL_StartTextInput` after a text-input focus change; `stopTextInput(owner)` calls `SDL_StopTextInput` when that owner closes. `setTextInputArea` calls `SDL_SetTextInputArea` before or during start. Air's SDL hook already moves these UIKit calls to the main thread. Patch `0005` logs the three calls and sends a Cofre notification.
- Air sets `SDL_ENABLE_SCREEN_KEYBOARD=1` before SDL initialization. Patch `0005` calls the Cofre-owned `CofreShouldShowTextInput()` policy seam from Air's existing dlsym wrapper and gates StartTextInput on a recent SetTextInputArea call, so an early desktop-style start cannot present UIKit. The failure mode is a Minecraft screen that legitimately starts text input without setting an area; it will be logged as `SDL_StartTextInput suppressed (no text area)` and needs a later per-screen exception.
- Older GLFW versions use Air's hidden `TrackedTextField` in `SurfaceViewController`/`JavaGUIViewController`. `becomeFirstResponder` opens the keyboard; the text field sends characters through `CallbackBridge_nativeSendChar`/`nativeSendCharMods`, and key presses through `CallbackBridge_nativeSendKey`.
- Air touch behavior stays in `SurfaceViewController`: drag in the grabbed game sends relative mouse motion (camera look), tap sends the configured click action, and long press sends left mouse down/up (break). Cofre's overlay returns `nil` from `hitTest` outside its buttons, so those touches continue to Air.
- Air's existing `ControllerInput` maps `GCController` buttons and sticks through `CallbackBridge`; `SurfaceViewController` registers `GCMouse` callbacks and `KeyboardInput` maps `GCKeyboard` presses. Cofre only selects the mode and injects the same callback events.

## API

`GameInputService` in `app/UI/Sources/CofreUI/Facade/Requirements.swift` exposes:

- `inputMode` (effective mode) and `inputModeOverride` (`auto`, `touch`, `controller`, `keyboardMouse`).
- `press`/`release` for WASD, jump, sneak, sprint, inventory, chat, drop, Escape, F5 and hotbar 1–9.
- `mouseButton` for attack/use and `look(deltaX:deltaY:)` for relative camera motion.
- `textInputRequests()` for the Start/Stop signal, plus `showKeyboard()` and `hideKeyboard()`.

`CofreGameInput` maps those calls to Air's `CallbackBridge_nativeSendKey`, `nativeSendMouseButton`, and `nativeSendCursorPos`. SDL3 and GLFW are selected by Air at runtime.

## Mode rules

| Override | Effective mode | Touch controls |
| --- | --- | --- |
| Auto | Controller if any `GCController`, otherwise Keyboard & mouse if `GCKeyboard` or `GCMouse` exists, otherwise Touch | hidden for hardware modes |
| Touch | Touch | shown by the future Cofre UI |
| Controller | Controller | hidden |
| Keyboard & mouse | Keyboard & mouse | hidden |

Connect/disconnect notifications recompute the effective mode live. The selected override is stored as `cofre.input.mode`.

The current placeholder host hides Air's control view, QWERTY drawer, menu gear and FPS/MEM HUD while preserving the underlying game touch view. It adds three debug buttons; the design agent can replace them without changing this API.
