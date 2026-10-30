# Cofre logic, security and maintainability review

Scope: `cofre/` only, plus `launcher-plan/server-join/`. Read-only review on 2026-10-29. Findings are ranked by impact. `CONFIRMED` means reproduced from the checked-in code or a requested check; `PLAUSIBLE` means the failure follows from an untested platform/runtime assumption.

## Critical

1. **The production shell is still a blank placeholder** — **CONFIRMED** (`cofre/app/Shell/CofreRootViewController.swift:1-5`)
   - **What goes wrong:** The root controller only creates an empty `UIView`; it never imports `CofreUI`, creates `CofreServices`, or starts a store. A real launch therefore shows a blank screen even though the UI tests pass against `MockBackend`.
   - **Fix:** Implement the documented shell wiring: construct a real `CofreBackendAdapter`, call `CofreUI.makeRootViewController`, embed it, and start its store. Add an app-target smoke test that launches the actual root controller.

2. **The loopback tunnel has no peer/socket bridge** — **CONFIRMED** (`cofre/extensions/PacketTunnel/LoopbackTunnel.swift:17-24`)
   - **What goes wrong:** Every packet read from `packetFlow` is written straight back to the same `packetFlow` after swapping IPv4 addresses. No UDP/TCP socket, `NWConnection`, or StikJIT listener receives packets at `10.7.0.1`; the host packet is reinjected as inbound traffic. JIT traffic cannot reach a service in the appex.
   - **Fix:** Define the transport explicitly and implement a real bridge (for example, a local socket listener/connector bound to the tunnel address, or a supported Network.framework path), with protocol-aware forwarding and integration tests for a TCP connect and reply.

3. **Cofre never supplies the UI with a real backend** — **CONFIRMED** (`cofre/app/UI/Sources/CofreUI/Facade/Services.swift:58-76`, `cofre/app/UI/Sources/CofreUI/Mocks/MockBackend.swift:4-6`)
   - **What goes wrong:** `CofreServices` requires a `CofreBackend`, but the only checked-in implementation is `MockBackend`; the ObjC `CofreAirBridgeAdapter` implements only a small unrelated subset and cannot satisfy the UI protocols. Features such as launch, pairing, mods, accounts, and JIT remain simulated or disconnected.
   - **Fix:** Add one production adapter implementing every `CofreBackend` requirement and make the shell use it. Keep `MockBackend` test/preview-only and fail the app build if the production target references it.

## High

4. **Starting Cofre can reconfigure and start an unrelated VPN** — **CONFIRMED** (`cofre/app/Glue/AirBridge/CofreTunnelService.m:5-16`)
   - **What goes wrong:** The code takes `managers.firstObject` without matching Cofre's provider bundle or localized description. If another VPN manager is first, Cofre overwrites its protocol and starts it.
   - **Fix:** Find the manager whose `protocolConfiguration` is `NETunnelProviderProtocol` with `providerBundleIdentifier == com.ignaciojuarez.cofre.tunnel`; create a new manager only when absent, and verify the identifier again after reload.

5. **Pairing reports Wi-Fi enabled even when both lockdown writes fail** — **CONFIRMED** (`cofre/tools/llave/core/src/pair.rs:135-152`)
   - **What goes wrong:** Errors from `EnableWifiConnections` and `EnableWifiDebugging` are discarded, then `WifiEnabled` is emitted. On a device that rejects either setting, the app stores a pairing file and claims success; later JIT fails with a misleading error.
   - **Fix:** Propagate each `set_value` error, emit a structured failure, and only emit `WifiEnabled` after both writes succeed (or explicitly record a supported “USB-only” mode).

6. **RemotePairing setup failures are silently downgraded to a seemingly valid file** — **CONFIRMED** (`cofre/tools/llave/core/src/pair.rs:169-187`)
   - **What goes wrong:** On iOS 17.4+, connect/generate/handshake errors are ignored. The required RemotePairing keys are then absent, but the legacy-key validation can still pass and the file is written. Cofre cannot attach through RSD.
   - **Fix:** For versions requiring RemotePairing, return the exact error when any step fails and validate the RP key set before `Validated`/write; only allow the legacy path on versions below the cutoff.

7. **Pairing import can delete the good key and lose the new key** — **CONFIRMED** (`cofre/app/Glue/AirBridge/CofrePairingImport.m:55-67`)
   - **What goes wrong:** The importer removes `pairingFile.plist` before moving the temporary file and ignores both directory/move errors. A full container or interruption leaves no pairing file, while the UI has no failure signal.
   - **Fix:** Write a protected temporary file, fsync/close it, atomically replace the destination (`replaceItemAtURL`), check every error, and report failure to the UI without deleting the old file first.

8. **The importer accepts structurally fake device credentials** — **CONFIRMED** (`cofre/app/CofreKit/PairingFileValidator.swift:20-37`, duplicate logic at `cofre/app/Glue/AirBridge/CofrePairingImport.m:14-37`)
   - **What goes wrong:** `HostID` and `SystemBUID` only need to exist (any type/value), certificates are any non-empty or even empty `Data`, and UDID is optional. A malformed plist is stored and fails much later in the tunnel with no useful diagnosis.
   - **Fix:** Use one validator, require exact string types and non-empty bounded values, validate certificate/key encodings and required RemotePairing keys for iOS 17.4+, and reject a missing/invalid UDID when the workflow needs device binding.

9. **`--out` can overwrite an arbitrary local file** — **CONFIRMED** (`cofre/tools/llave/core/src/pair.rs:230-240`)
   - **What goes wrong:** `File::create(out_path)` follows an existing symlink and accepts any path supplied by the caller. A wrapper or UI bug passing `/some/file` can truncate it while writing private pairing material.
   - **Fix:** Restrict output to an app-created directory, open with `create_new`/`O_NOFOLLOW`, write atomically, and reject symlinks and existing non-pairing files.

## Medium

10. **The updater does not do what `UPDATING.md` promises** — **CONFIRMED** (`cofre/scripts/update-upstream.sh:7-21`)
    - **What goes wrong:** It fetches refs and edits/commits `UPSTREAM.lock`, but never creates `.work` trees, applies patches, builds, runs smoke, checks license hashes, updates `CHANGELOG.md`, or creates the documented branch. It can record a SHA that is not checked out or buildable.
    - **Fix:** Make the script implement the documented pipeline (or rewrite the runbook): detached worktree at the candidate SHA, `git am --3way`, patch/license checks, build and smoke logs, and only then a lockfile commit with an explicit branch.

11. **Signing is tied to one developer, one team, and one device** — **CONFIRMED** (`cofre/scripts/sign-development.py:7-16`)
    - **What goes wrong:** Any other maintainer or a renewed profile fails because the identity, team ID, and UDID are hardcoded. The script also changes only the host `CFBundleIdentifier`; it does not verify the appex bundle ID matches the provider/profile before signing.
    - **Fix:** Read identity/team/device policy from explicit environment/config, validate both bundle IDs against the built products and profiles, and make device checks opt-in for local development.

12. **`scripts/run.sh` mutates the upstream worktree and hides build failures** — **CONFIRMED** (`cofre/scripts/run.sh:12-35`, `:37-56`)
    - **What goes wrong:** It deletes CMake caches and copies glue directly into `.work/air`; repeated runs accumulate edits outside a patch. `ls -t ... | head -1` can produce an empty path, while many `PlistBuddy` operations are deliberately ignored, so a malformed or unsigned package can continue to signing.
    - **Fix:** Build from a fresh detached worktree/apply-patch output, select artifacts with a checked non-empty `find`, and fail on every required plist/appex operation; verify bundle IDs, entitlements, and embedded extension before signing.

13. **The server-join spec and schema disagree on the wire format** — **CONFIRMED** (`launcher-plan/server-join/SPEC.md:107-129`, `launcher-plan/server-join/schema/server-card.schema.json:1`)
    - **What goes wrong:** The prose requires `schema_version`, `addresses` objects, `update_policy`, and `signing`; the JSON schema requires `schema`, `server`, `updatePolicy`, and `security`. An implementation following the prose will reject its own cards, while one following the schema can omit signature details described as required for trust.
    - **Fix:** Choose one versioned schema, generate the prose/examples from it, require the signature object and exact address/host/hash constraints in JSON Schema, and run one validator in CI against all examples.

14. **The server-join trust model allows TOFU cards to bootstrap arbitrary downloads** — **PLAUSIBLE** (`launcher-plan/server-join/SPEC.md:179-197`, `:64-80`)
    - **What goes wrong:** A first fetch can be redirected through DNS/TXT/deep-link discovery, then TOFU pins the attacker's key. The allowlist is described in prose but not enforced by the schema, and wildcard host rules (`*.github.com`, `*.modrinth.com`) are broad enough to accept attacker-controlled repositories/accounts.
    - **Fix:** Bind the first key to the HTTPS origin or an explicit user confirmation showing origin and fingerprint, canonicalize/strictly match registrable domains, disallow arbitrary TXT/redirect origins without consent, and make signature/host/hash checks mandatory in code and schema.

## Low

15. **Release hash replacement can silently fail** — **CONFIRMED** (`cofre/tools/llave/scripts/release.sh:8-12`)
    - **What goes wrong:** The Python regex replacement is not checked. If `pair.sh` changes its variable spelling or format, release still exits successfully while shipping an old checksum and every download fails.
    - **Fix:** Assert exactly one replacement occurred, write atomically, then run a local checksum/download verification before publishing.

16. **The license notice is incomplete for a GPL distribution** — **CONFIRMED** (`cofre/NOTICE.txt:1-6`; no root `LICENSE`/`COPYING` is tracked)
    - **What goes wrong:** The repository names GPL/MPL/AGPL components but ships no root GPL-3.0 license text and does not enumerate Air/Amethyst notices, idevice copyright, fonts, or complete source/build-offer details in the notice itself. This makes a handed-out binary's corresponding-source offer incomplete.
    - **Fix:** Add the GPL-3.0 text and complete third-party notices/copyrights, include exact upstream SHAs and source/patch/build instructions in the release artifact, and keep AGPL text only with the fallback app if it is distributed.

17. **ShellCheck is noisy because vendored/generated scripts are not scoped** — **CONFIRMED** (requested ShellCheck run)
    - **What goes wrong:** A whole-tree run reports an error in vendored Air `glslang/Test/validate-shaders.sh`, obscuring the actionable warnings in Cofre scripts (`SC2053`, `SC2086`, unused variables, and ignored source paths). CI cannot distinguish our regressions from upstream code.
    - **Fix:** Run ShellCheck on tracked project scripts only, pin exclusions for immutable upstream submodules, and fail CI on project errors while recording upstream findings separately.

## Top 5 to fix first

1. Wire a real production root/backend (`CofreRootViewController.swift`, `CofreBackendAdapter`).
2. Replace the packet self-loop with a tested socket/network bridge.
3. Make pairing Wi-Fi and RemotePairing errors fatal and validate the complete key set.
4. Select only Cofre's VPN manager and make pairing-file replacement atomic.
5. Replace the updater/run scripts with a build/apply-patch pipeline that actually verifies the candidate.

## Requested checks

| Check | Result |
|---|---|
| `scripts/smoke.sh` | **PASS**; all upstreams/files present, patch budgets within limit, `UPSTREAM.lock` found. |
| `cargo test` in `tools/llave/core` | **PASS**; 1 test passed. |
| `cargo clippy` in `tools/llave/core` | **PASS with 2 warnings** (`collapsible_if` at `src/pair.rs:111` and `:172`). |
| `sh tools/llave/test-pair.sh` | **PASS**; simulation launched and completed. |
| CofreUI `xcodebuild test` on a shared simulator | **PASS**; 11 tests, 0 failures. Xcode emitted repeated `invalidDigitCount(94232)` diagnostics but the test action succeeded. |
| ShellCheck | `uvx` unavailable. `pipx run shellcheck-py` ran: project scripts produced warnings/info; the full tree also reported a vendored Air error (`glslang/Test/validate-shaders.sh:19`, `SC2145`). |
| `launcher-plan/server-join/validate_examples.py` | **PASS**; valid examples pass and malicious/missing-required fixtures fail as expected. |

No physical devices were used. No files under `cofre/` were edited.
