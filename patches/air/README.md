# Patches to Air (budget: at most 5)

| Patch | What | Drop when |
|---|---|---|
| `0001-compile-cofre-glue.patch` | Compiles Cofre's ObjC glue (`app/Glue/AirBridge/*.m`, copied to `Natives/CofreGlue/` by `scripts/run.sh`) and links NetworkExtension; shader source dumps require `COFRE_SHADER_DUMPS=1` (compiled cache stays on) | Air offers a plugin point |
| `0002-install-cofre-root.patch` | Makes the scene show Cofre's root screen (falls back to Air's UI if CofreCore fails to load); Air's launch popups (translation notice, Air updater, version isolation wizard) only show over Air's UI | Air offers a root-controller hook |
| `0003-cofre-owns-jit.patch` | Stops Air's external JIT enablers and missing-tool prompts while Cofre owns the root; failed JIT mapping returns a launch error | Air offers an embedded JIT-provider hook |
| `0004-cofre-launch-exit-notification.patch` | Posts the JVM exit code (Cofre's launch screen shows exits before the first frame) and skips Air's crash UI when `CofreHandleGameExit()` (`CofreStartup.m`) returns YES, so Cofre's crash screen shows instead | Air exposes a game-exit callback that can replace its crash UI |
| `0005-cofre-text-input-policy.patch` | Routes SDL text-input calls through Cofre's policy: UIKit keyboard starts only after Minecraft supplies a text area, stops on focus loss, and emits verification logs/signals | Air exposes a supported text-input focus callback to Cofre |

`debug.jit_enabler=manual` still displays external-tool guidance, and forced TXM reattachment ignores it. Patch 0003 uses the glue's process-local `CofreOwnsJIT()` flag instead; Air's fallback UI retains its original behavior. Cofre's launch checks `CS_DEBUGGED`, enables JIT through its VPN when needed, and checks again before entering Air.

Regenerate a patch: make the change in a clean `git worktree` of `upstream/air`, commit with `Reason:` / `Drop when:` lines, then `git format-patch --zero-commit --no-signature`. Both `scripts/run.sh` and `scripts/update-upstream.sh` apply every patch here in order.
