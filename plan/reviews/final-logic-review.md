# Final Cofre logic and security review

Read-only review of code added since plan/reviews/logic-review.md. Fixed items from that review are omitted.

## Critical

No new critical findings.

## High

1. **JIT reports success before it has succeeded — CONFIRMED** (extensions/PacketTunnel/PacketTunnelProvider.swift:50-61, app/CofreKit/CofreJIT.swift:53-61)
   - **Failure:** The appex starts StikJIT.enableJIT in a detached task, then immediately replies with state enabling and mode txm. The app treats any mode as enabled. If attach, RSD, TXM, or the script fails, setup still reports JIT ready.
   - **Fix:** Keep the request pending until the task finishes; return state enabled only after success and state failed with a reason on every failure. Make the app require the explicit success state.

2. **Production join installs an unverified pack — CONFIRMED** (app/Glue/AirBridge/ServerJoinAdapter.swift:100-123, app/Glue/AirBridge/AirBridgeAdapter.m:56)
   - **Failure:** After verifying the card envelope, install passes the card URL directly to Air. It never downloads with the signed sha512/size, and InstallEngine is never called. A redirected or replaced pack is imported without the signed bytes being checked.
   - **Fix:** Download through a bounded streaming path, enforce the declared size and allowed hosts, compute SHA-512 before Air sees the file, then import the verified staged file and atomically roll back on failure.

3. **Trust confirmation and deep-link pinning are bypassed — CONFIRMED** (app/Glue/AirBridge/ServerJoinAdapter.swift:66-78,100-123, app/CofreKit/ServerJoin/Sources/CofreServerJoin/Trust.swift:27-52)
   - **Failure:** request.pin is never compared. TrustVerifier.confirm is never called, and install ignores trust.keyChanged and firstVisit. The static MemoryTrustStore is also lost on process restart. A first-use or rotated key can therefore proceed without the required user confirmation or durable pin.
   - **Fix:** Reject a pin mismatch, block changed keys unless the previous-key signature validates, require explicit first-use/rotation confirmation before install, call confirm, and persist records in protected app storage.

4. **VPN start errors are ignored and the message races tunnel setup — CONFIRMED** (app/CofreKit/CofreJIT.swift:34-36)
   - **Failure:** startVPNTunnel() is wrapped in try?; the code immediately sends the provider message without waiting for connected. A normal startup race is surfaced as a generic JIT failure and may trigger the external fallback even though the tunnel would soon be ready.
   - **Fix:** Propagate start errors, observe session status until connected with a timeout, then send the provider message.

5. **TXM patch requests can wrap addresses — CONFIRMED** (extensions/PacketTunnel/CofreTXM.js:65-72)
   - **Failure:** The patch path bounds only byte count. An address near 0xffffffffffffffff plus the requested size wraps, so later M packets target unrelated low addresses.
   - **Fix:** Require a 64-bit address, reject address plus size overflow and invalid ranges before the loop, and apply the same bounds helper to every memory operation.

6. **Stopping the extension leaves JIT work and pairing files behind — CONFIRMED** (extensions/PacketTunnel/PacketTunnelProvider.swift:6-18,39-60)
   - **Failure:** stopTunnel only calls its completion handler. It neither cancels the detached task nor removes pairingURL. If iOS stops the appex or kills it between the write and task cleanup, protected temporary pairing files and an active attach can survive.
   - **Fix:** Track a cancellable task, cancel and await it in stopTunnel, synchronously remove the current file, clear the reference, and delete stale Cofre temp files at tunnel start.

7. **Unbounded pack responses can exhaust memory — CONFIRMED** (app/CofreKit/ServerJoin/Sources/CofreServerJoin/Discovery.swift:4-9, app/CofreKit/ServerJoin/Sources/CofreServerJoin/InstallEngine.swift:27-38)
   - **Failure:** URLSession.shared.data(from:) buffers an entire response. The optional size_bytes is not enforced at download time, so a server can send far more than the 2 GiB post-load check before hashing/import.
   - **Fix:** Use a streaming download with a hard byte budget, abort on overflow, and hash while streaming.

## Medium

8. **Setup observers are retained forever — CONFIRMED** (app/Glue/AirBridge/CofreBackendAdapter.swift:53-58)
   - **Failure:** Every setupUpdates call appends a continuation, but onTermination does nothing. Dead observers remain retained and receive all future events.
   - **Fix:** Store continuations by ID and remove each one from onTermination; finish all on adapter teardown.

9. **Air callback errors are lost and import can report false success — CONFIRMED** (app/Glue/AirBridge/AirBridgeAdapter.m:54-56)
   - **Failure:** Server search maps results even when Air supplies an error, turning outages into an empty successful result. importPack calls completion with nil when import returns false without setting an error.
   - **Fix:** Return the original error unchanged; synthesize a failure when an operation returns false with no error.

10. **Main-actor code can deadlock on Air callbacks — PLAUSIBLE** (app/Glue/AirBridge/CofreBackendAdapter.swift:137-141, app/Glue/AirBridge/AirBridgeAdapter.m:22-31)
   - **Failure:** deleteWorld runs on the main actor and waits on a semaphore while the asynchronous world scan may deliver completion on the main queue. The UI freezes.
   - **Fix:** Make the bridge async and await its completion; never block the main actor with a semaphore.

11. **Memory settings do not control the configured heap — CONFIRMED** (app/Glue/AirBridge/AirBridgeAdapter.m:39-50, app/Glue/AirBridge/CofreBackendAdapter.swift:156-177)
   - **Failure:** The adapter reports the global ame141_currentLaunchAllocMem as every profile's RAM and setPreferences never writes a RAM value or java.auto_ram. The UI can show and edit a cap that launch ignores.
   - **Fix:** Read/write Air's actual per-profile heap and auto-RAM keys, clamp them to device policy, and remove the capability until those writes are real.

12. **URL policy accepts redirect, port, userinfo, and non-canonical host variants — PLAUSIBLE** (app/CofreKit/ServerJoin/Sources/CofreServerJoin/Discovery.swift:6-8, app/CofreKit/ServerJoin/Sources/CofreServerJoin/Decoder.swift:51-61)
   - **Failure:** URLSession follows redirects, while validation compares only URL.host. A card can use an allowed hostname on another port or include credentials, and a redirect can move the fetch to an unapproved host.
   - **Fix:** Reject user/password, require approved ports, canonicalize hosts, and revalidate every redirect hop against the card allowlist.

13. **Updater leaves old worktrees behind — CONFIRMED** (scripts/update-upstream.sh:13-15)
   - **Failure:** The EXIT trap captures mutable work. Each loop replaces the trap, so updating multiple upstreams removes only the last worktree; earlier .work trees remain.
   - **Fix:** Remove each worktree immediately after status capture in a cleanup block, or install one trap over all created worktrees.

14. **A deep link is not bound to its advertised server — PLAUSIBLE** (app/Glue/AirBridge/ServerJoinAdapter.swift:66-75)
   - **Failure:** server=trusted.example and a card URL for another host are accepted together; the request server is not compared with card addresses/origin. A crafted link can show a different server identity.
   - **Fix:** Parse host and port canonically and require the requested server to match a card address, or require explicit confirmation of the mismatch.

## Low

15. **Card discovery marks trust before consent — CONFIRMED** (app/Glue/AirBridge/ServerJoinAdapter.swift:72-76)
   - **Failure:** UserDefaults records cofre.server-card.* during resolution, before install or key confirmation. The server list can claim a card is trusted after a cancelled join.
   - **Fix:** Set the marker only after trust confirmation and verified install.

## Requested checks

| Check | Result |
|---|---|
| scripts/smoke.sh | PASS |
| scripts/lint.sh | PASS (ShellCheck runner completed) |
| cargo test (tools/llave/core) | PASS — 1 test |
| cargo clippy -D warnings (tools/llave/core) | PASS |
| swift test (app/CofreKit/ServerJoin) | PASS — 27 tests |
| swift test (tools/server-card) | Builds; fails because the package has no test target/tests |
| node tests/jit/*.test.js | PASS — TXM parsing tests |
| python3 plan/server-join/validate_examples.py | PASS; valid fixtures pass and malicious fixtures fail as expected |

No scripts/run.sh was run. No devices were touched. No source code was modified.

## Top 5 to fix first

1. Return JIT success only after StikJIT completes, and report failures.
2. Verify pack size and SHA-512 before Air imports it.
3. Enforce pin/TOFU confirmation and persist the trust decision.
4. Cancel JIT and remove pairing material when the tunnel stops.
5. Stream and cap downloads, with strict redirect/host/port validation.
