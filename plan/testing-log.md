# Testing log

How to test and what each field means: [TESTING.md](TESTING.md). Newest entries last.

| ID | Date | Area | Title | Sev | Status | Commit |
|---|---|---|---|---|---|---|
| B-001 | 2026-10-30 | Onboarding | iPad background filled without enlarging the moon | S4 | fixed | a85dfba |
| B-002 | 2026-10-30 | Modpacks | CurseForge imports create their staging mods directory | S2 | fixed | 28304b5 |
| B-003 | 2026-10-30 | Launcher UX | Simulator launcher pass shows clear first-run states; no blocking UX defect found | UX | can't-repro | — |

### B-001 · Onboarding · iPad background filled without enlarging the moon
- Date: 2026-10-30 · Device: iPad C51DB8A8… · Build: a85dfba
- Steps: Open Cofre on an empty iPad container and wait for onboarding artwork.
- Expected: The full background is painted and the moon remains at its designed size.
- Actual: Before the fix, the background did not fill the iPad layout; the fix uses a fill layer without scaling the moon.
- Evidence: `/tmp/cofre-test/shots/onboarding-ipad.png`
- Severity: S4 · Status: fixed · Commit: a85dfba
- Retest: iPad screenshot ✅ · iPhone layout neighbour ✅

### B-002 · Modpacks · CurseForge imports create their staging mods directory
- Date: 2026-10-30 · Device: simulator-independent fixture path · Build: a5a2159
- Steps: 1. Import a valid CurseForge manifest with an API key. 2. Let the first required file download. 3. Observe the staged destination.
- Expected: The required jar is written under the staging `mods/` directory and import continues.
- Actual: `ModpackImport.importCurseForge` wrote directly to `root/mods/<project>-<file>.jar` without creating `mods`; a clean staging directory therefore failed with a missing-parent error.
- Evidence: `app/UI/Sources/CofreKit/Modpacks.swift` destination path; source-level repro on a fresh staging directory.
- Severity: S2 · Status: fixed · Commit: 28304b5
- Retest: CurseForge path now creates the parent directory ✅ · Modrinth staging path unchanged and tests green ✅

### B-003 · Launcher UX · Simulator launcher pass shows clear first-run states; no blocking UX defect found
- Date: 2026-10-30 · Devices: iPad C51DB8A8… and iPhone 4EC427DF… · Build: a5a2159
- Steps: Launch with the retained empty simulator containers; inspect Play, Worlds, account banner, instance picker, JIT status, and compact layout.
- Expected: A first-time player can tell what is unavailable and where to go next.
- Actual: Account banner has a direct Accounts action; Worlds has an honest empty state; the iPhone and iPad layouts remain readable. No dead button or misleading FSR control observed (FSR removal is intentional).
- Evidence: `/tmp/cofre-test/shots/onboarding-ipad.png`, `/tmp/cofre-test/shots/onboarding-iphone.png`
- Severity: UX · Status: can't-repro · Commit: —
- Retest: kill/relaunch remained readable ✅

### Device queue · simulator blockers
- JIT, pairing, PacketTunnel/VPN, Microsoft sign-in completion, gameplay/first frame, Metal-specific behavior, Forge/NeoForge JVM installation, and real downloads remain device-only or blocked by simulator capabilities; no physical device was touched.
- The disposable simulator payload required retagging and ad-hoc signing; this is test infrastructure only and is not a release build.
