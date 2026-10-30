# Cofre UI, UX, copy and website review

Read-only review, 2026-10-29. Scope: `cofre/app/UI`, `cofre/tools/llave/App/Sources/Views`, `cofre/docs/`, `README.md`, `PAIRING.md`. Paths are relative to `cofre/` unless they say otherwise.

- **CONFIRMED** means I reproduced it from the code, a run, a measurement or a registry lookup.
- **PLAUSIBLE** means it follows from the code or a source, but I didn't check it on a device.

## What I ran

| Check | Result |
|---|---|
| `xcodebuild test -scheme CofreUI` on the shared iPhone 18 Pro sim `4EC427DF…` (derived data in `/tmp`) | ✅ 11/11 passed. There are no view or snapshot tests, and contrast is only tested for the purple accent. |
| `swift test` (macOS, scratch path in `/tmp`) | ✅ 2/2 passed |
| Headless Chromium screenshots of `docs/index.html` at 360, 768 and 1280 px | ✅ No overflow at 360. Layout matches the tokens. |
| Contrast of the site and app token pairs (WCAG 2.x) | Everything passes AA **except the Emerald accent's button text, at 4.38:1** (#12). |
| `whois -h whois.nic.site cofre.site` | **"Domain cofre.site is available for registration"** (#1) |
| HTTP status of every external link | The upstream, Apple and idevice links return 200. All `github.com/ignaciojuarez/cofre/...` links return 404 because they're still placeholders. |
| Search for "iloader" | It doesn't appear in any shipped Cofre file. Details are in the iloader section near the end. |

---

## Critical

### 1. The app sends users to an unregistered domain to get a `curl … | sh` command — CONFIRMED
- **Where:** `app/UI/Sources/CofreUI/CofreUI.swift:33` (`https://cofre.site/pair`), shown at `Screens/Shared.swift:175` ("The command is at **cofre.site/pair**"), shared to the Mac at `Shared.swift:182` ("Send to Mac"), and in Settings → JIT & Java through `PairingGuide` (`SettingsScreen.swift:229`). Screenshot: `cofre-design/system/screens/iphone-setup-pairing.png`.
- **What the user experiences:** Today the link is dead. Anyone can register `cofre.site` and serve their own Terminal command. The app, the site and the README all train non-technical users to paste whatever command that page shows. That is a full compromise of their Mac, and through the pairing record, of their iPhone.
- **Fix:**
  - Before any build ships, register `cofre.site` and add `docs/CNAME`.
  - Or point `CofreLinks.pairing` at a URL you already control, such as `https://ignaciojuarez.github.io/cofre/pair/`.
  - Add a unit test that fails if `CofreLinks.pairing.host` isn't on an allowlist.

## High

### 2. "You tapped Don't Trust": `PAIRING.md` sends people to a destructive reset first — CONFIRMED (Apple sources in the fact-check section)
- **Where:** `PAIRING.md:57` says to Reset Location & Privacy. `tools/llave/App/Sources/Views/StateScreen.swift:91` says to unplug and plug back in.
- **What the user experiences:** Following `PAIRING.md`, the user wipes every app's location and privacy permissions and every trusted computer. Apple says a Don't Trust choice isn't remembered: the alert comes back the next time you connect.
- **Fix, `PAIRING.md:57`:** "Unplug your iPhone, unlock it, and plug it back in. The Trust alert comes back; tap **Trust**. Still no alert? Then: **Settings → General → Transfer or Reset iPhone → Reset → Reset Location & Privacy** (this also resets app location permissions), and run the command again."
- **Fix, Llave:** Keep the current copy and add the fallback: "No alert after plugging back in? See PAIRING.md."

### 3. The fallback paths leave the pairing key on a friend's Mac, with no warning — CONFIRMED (copy), PLAUSIBLE (iCloud)
- **Where:**
  - "Save to Desktop": `tools/llave/App/Sources/Views/ContentView.swift:110-113` and `StateScreen.swift:73-77`.
  - The copy that contradicts it: `docs/index.html:221`, `README.md:75` (image alt), `PAIRING.md:21` ("nothing stays on their Mac") and `docs/index.html:379` ("never leaves your devices").
- **What the user experiences:** After Save to Desktop, the friend's Desktop holds a file that can control the user's iPhone. After AirDrop, the file also stays in Files → Downloads on the iPhone. If that Downloads folder is in iCloud Drive, the file is uploaded (PLAUSIBLE; Apple doesn't say where AirDrop's Downloads folder lives).
- **Fix, copy:** After saving, show: "Saved to the Desktop. AirDrop it to your iPhone, then **move it to the Trash**. Never share this file: it's a key to your iPhone." Add to every AirDrop fallback (site, README, `PAIRING.md`): "3. After Cofre says **Key found**, delete the file from Files → Downloads."
- **Fix, logic:** Delete the temporary file after a successful AirDrop. Prefer AirDrop over Save to Desktop.

### 4. Setup restarts at Welcome, and briefly shows for users who already finished it — CONFIRMED
- **Where:** `Model/CofreStore.swift:12` (every check starts at `.unknown`), `:60` (`showsSetup`) and `:64-72`, together with `Screens/SetupFlow.swift:35`. The resume step is picked in `onAppear`, before `start()` has loaded anything, and nothing re-picks it afterwards.
- **What the user experiences:**
  - Users who finished setup see the wizard flash on every cold start.
  - Users who are part-way always land on Welcome.
  - `setupDismissed` isn't saved, so if any live check (VPN, JIT) reports not-ready at launch, the whole wizard comes back. That part is PLAUSIBLE and depends on the backend's semantics.
- **Fix:**
  - Add a `setupLoaded` flag and show a neutral splash until `setupState()` returns.
  - Re-pick the step with `.onChange(of: store.setup)` when `startAt == nil`.
  - Save a "setup completed once" flag. After that, route live failures to a Banner on Play, not to the wizard.

### 5. The site's Step 4 doesn't match what the app does — CONFIRMED
- **Where:** `docs/index.html:262-263` and `README.md:79-80` say "setup moves on by itself… Cofre then tests JIT for you". The app needs Set up → Next (Dev Mode) → Next (Trust) → Next (Key found) → Allow VPN → Test JIT → Next → Sign in → Finish → Play: `SetupFlow.swift:94, 118, 147, 172, 210, 235, 276, 282, 305`.
- **What the user experiences:** About 10 taps where the site promised 3, and a manual "Test JIT" the site said was automatic.
- **Fix:**
  - Auto-advance with `.onChange(of: store.setup.<check>) { if $0.isReady { step += 1 } }` on the Dev Mode, Pairing, VPN and JIT steps.
  - Start `testJIT()` in a `.task` when the JIT step appears.
  - If that isn't wanted, change the copy: "Open Cofre and follow the steps: tap **Allow** for the VPN, **Test JIT**, then **Sign in with Microsoft**."

### 6. Deleting an instance has no confirmation from three of its four entry points — CONFIRMED
- **Where:** `Screens/InstancesScreen.swift:108` (⋯ menu and context menu) and `:62` (swipe). Only the detail pane asks first (`:153-155`).
- **What the user experiences:** One tap in a menu deletes the instance and its worlds.
- **Fix:** Route every Delete through the same `confirmationDialog`: "Delete {name}? Worlds and mods in its folder are removed too."

### 7. Controls that look live but do nothing — CONFIRMED

| Control | File:line | What happens |
|---|---|---|
| Worlds "+ New", "+ Add server" | `PlayScreen.swift:117`, `:134` | Nothing |
| World context menu: Back up, Open folder, **Delete** | `Shared.swift:81-83` | Nothing. Delete looks like it worked. |
| "Own folder" switch on instance detail | `InstancesScreen.swift:177` | `.constant`, so it won't toggle |
| New instance: "Own folder", "Add Fabric API" | `InstancesScreen.swift:245-246`, `:287` | Never passed to `createInstance` |
| Renderer: Shader cache, Multidraw, Compute shaders | `SettingsScreen.swift:129-155` | Local `@State`, so it resets every time |
| Look: "App icon", "Language", "LAN room" with › | `SettingsScreen.swift:375-379` | They look like buttons but aren't |
| "Env variables · **2 set**" | `SettingsScreen.swift:241` | A fake hard-coded value |
| ⋯ → "Export .mrpack" | `InstancesScreen.swift:107` | The URL is thrown away, so the user sees nothing |
| DropZone inside the Instances list | `InstancesScreen.swift:40` | `onChoose: {}` |
| Controller hint strip "A Play · B Back · Y Search · LB/RB" | `InputHint.swift:73-78` (used at `PlayScreen.swift:56`, `SettingsScreen.swift:177`) | The focus bridge isn't built, so the buttons do nothing |

- **Fix:** Hide each one until it's wired up: `if backend supports X`. Delete the "2 set" value. Show the export `ShareLink` from the menu too. Only show `HintStrip` once `ControllerFocusBridge` exists.

### 8. The "never share your pairing file" rule is weak or missing in the app and in Llave — CONFIRMED

| Surface | Today | Verdict |
|---|---|---|
| Site, Step 3 | Red banner (`docs/index.html:196-202`) and FAQ (`:349-352`) | ✅ Prominent |
| `README.md` | CAUTION callout (`:61-62`) and FAQ (`:134-137`) | ✅ |
| `PAIRING.md` | CAUTION at the top (`:5-6`) and in the AI prompt (`:66`, `:73`) | ✅ |
| App, setup S04 | 11 pt mono muted label: "Stays on this device. Never share it." (`SetupFlow.swift:179`) | ⚠️ Smallest, lowest-contrast style on the screen |
| App, Settings → JIT & Java ("I have a file") | Nothing (`SettingsScreen.swift:229-234`) | ❌ |
| Llave window | Only "Nothing is uploaded" (`ContentView.swift:94`); nothing in the AirDrop or Save states | ❌ That's where the file actually exists. |
| AirDrop fallback copy (site, README, `PAIRING.md`) | No "delete it after" step | ❌ |

- **Fix, app:** Replace the label with a warn `Banner` on S04 and X04: "**Never share your pairing file.** Not in a chat, not with AI. It's a key to this iPhone."
- **Fix, Llave:** In the `.ready` and `.placementFailed` states, change the help to "Send it only to your own iPhone. Never share this file." and change the footer to "Nothing is uploaded · Never share your key".

### 9. The AirDrop fallback steps are wrong on iOS 26.2+ and for a friend's Mac — CONFIRMED (Apple sources)
- **Where:** `docs/index.html:207`, `README.md:67`, `PAIRING.md:27` and the Llave note at `ContentView.swift:108`.
- **What the user experiences:**
  - On a friend's Mac, the iPhone doesn't appear in AirDrop unless it's set to *Everyone for 10 Minutes*, or the friend is a contact.
  - On iOS 26.2 and later, a sender who isn't a contact must enter an **AirDrop code**.
  - On the user's own Mac with the same Apple Account, there's no Accept prompt at all.
  - The Llave note doesn't say where the file lands.
- **Fix:** "Click **Send with AirDrop** and pick your iPhone. Not listed? On the iPhone open Control Center, touch and hold the Wi-Fi group, tap AirDrop → **Everyone for 10 Minutes**. On the iPhone tap **Accept** (if it asks for an **AirDrop code**, tap **Get AirDrop Code** and type it on the Mac). The file lands in **Files → Downloads**."
- **Llave note:** "…In Cofre, tap **I have a file → Downloads**, then the file named after your iPhone."

## Medium

### 10. Missing loading, empty and error states — CONFIRMED

| Screen | Problem | Fix |
|---|---|---|
| Play (`PlayScreen.swift:57-60`) | Shows "No instances yet" while instances load, because the store has no loading flag (`CofreStore.swift:20`, `:74-81`) | Add `libraryLoaded`. Show a Spinner row "Loading instances…" until it's set. |
| Instances list (`InstancesScreen.swift:44-65`) | No empty state, and no "no results" state for search | `EmptyState("No instances yet", …)` and `EmptyState("No matches", message: "Try another name.")` |
| Mods browser (`ModsScreen.swift:56-58`) | Blank while searching. "No results" also shows when offline. The spec's offline state isn't built. | Spinner row while `searching`. On error: `EmptyState("Can't reach Modrinth", message: "Check your connection, then try again.") { BlockButton("Try again") }` |
| Installed (`ModsScreen.swift:192-193`) | The empty state promises "drop .jar and .zip files here", but there's no drop handler. A filter with no matches also says "Nothing here yet". | Copy: "No mods yet. Get them in Get mods." Add a separate "No matches" for the filter. |
| New instance (`InstancesScreen.swift:259-266`) | If the version list fails, it silently ends up empty: Create is disabled with no reason. A failed create still closes the sheet (`:287-289`). | Show "Couldn't load versions · Try again". Keep the sheet open on failure. |
| Mod page (`ModsScreen.swift:145-146`) | The button reads "Install " with no version while versions load | Spinner until versions arrive |
| Settings → Logs (`SettingsScreen.swift:326`) | `exportLog` runs after `streamLog`, which never ends on a live stream (`Requirements.swift:21-22`), so "Share log" never appears | Run the export in its own `Task`, or export on tap |

### 11. Errors give no next step — CONFIRMED
- **Where:** The global banner shows the raw `localizedDescription` (`CofreUI.swift:98-104`). A JIT failure shows only that message (`SetupFlow.swift:231`, `SettingsScreen.swift:220`). A launch failure offers only Close and Copy log (`LaunchScreen.swift:80`, `:97-98`).
- **What the user experiences:** An error with no way forward. The README's five-point JIT checklist never appears in the app.
- **Fix:** Map the failing `JITStep.Kind` to copy:
  - `.pairing`: "Your key may be stale. Run the Mac step again: cofre.site/pair."
  - `.vpn`: "Turn off other VPNs (work, ad blocker), then try again."
  - `.diskImage`: "Connect to Wi-Fi. After a restart, JIT needs internet once."
  - `.debugger`: "Check Developer Mode is on."

  For launch errors, add "Test JIT" and "Lower memory" buttons.

### 12. The Emerald accent fails AA on primary buttons — CONFIRMED (4.38:1)
- **Where:** `Tokens/Tokens.swift:66-68` (white `onFace` on `#1f8a4c`). The test only checks purple: `Tests/CofreUITests/CofreUITests.swift:21`.
- **What the user experiences:** Low-contrast labels on every primary button once they pick Emerald.
- **Fix:** Darken `face` to `#1a7a43` (about 5.2:1). Loop the contrast test over `AccentFamily.all`.

### 13. Tap targets under 44 pt — CONFIRMED

| Target | File:line | Size |
|---|---|---|
| Back ‹ | `Components/ColumnHeader.swift:22` | 30 pt wide |
| Instance-row ⋯ | `InstancesScreen.swift:56` | 30 pt wide |
| Detail ⋯ | `InstancesScreen.swift:131` | 30 pt tall |
| Sidebar pinned instances | `NavChrome.swift:127` | 36 pt tall |

- **Fix:** `minWidth: 44` / `minHeight: 44`, or `.minimumHitArea()`. That modifier exists at `Block.swift:71` but nothing uses it.

### 14. The rail's JIT status relies on color, and the account may be hidden from VoiceOver — CONFIRMED (visual), PLAUSIBLE (VoiceOver)
- **Where:** `NavChrome.swift:76-82`: "JIT" is the same word in green or gray. Screenshot: `ipad11-portrait-mods.png`. At `:83-84`, `.accessibilityHidden(false)` probably can't undo the `accessibilityHidden(true)` inside `PixelIcon`.
- **Fix:** Show "JIT ✓" or "JIT ✕" (or "On"/"Off") under the bolt. Give the account its own element: `Color.clear.accessibilityElement().accessibilityLabel(name)`.

### 15. The memory copy says Cofre picks a safe amount; the code doesn't — CONFIRMED (code), PLAUSIBLE (thresholds)
- **Where:** `README.md:102` and `docs/index.html:305` say "Cofre picks a safe amount". But `Facade/Models.swift:113` defaults to `autoRAM = false, ramMB = 4096`, and the slider goes up to 100% of RAM with only a "Keep ≤ 75%" note (`SettingsScreen.swift:93`).
- **Fix:**
  - Default `autoRAM = true`.
  - Cap the slider at `os_proc_available_memory()` minus about 1 GB.
  - Change the note to "Closes while loading? Lower this."
  - Mark "about 150 mods" as untested or remove it. See the memory fact-check.

### 16. Developer Mode step: copy and deep link — CONFIRMED (copy), PLAUSIBLE (deep link and reachability)
- **Where:** `SetupFlow.swift:114` says "Restart → Turn On"; Apple's wording is "Enable". `:116` says "Do the Mac step first". `:120` "Open Settings" can't reach Privacy & Security through public API (the mock is a no-op: `MockBackend.swift:59`). Cofre is development-signed (`get-task-allow`, `artifacts/Development.entitlements`), so iOS won't even open it while Developer Mode is off. The step's "Off" state is likely unreachable.
- **Fix:**
  - Copy: "Restart → **Turn On** (or **Enable**)" and "No switch? Do **Step 3 · Connect to a Mac**, then come back."
  - Label the button "Open Settings app" and open the Settings root.

### 17. Plain-language problems for a non-technical friend — CONFIRMED

| Where | Today | Proposed |
|---|---|---|
| VPN step diagram `SetupFlow.swift:195-201` | "Lets Cofre reach this device's debugger." · "App → Loop → 10.7.0.1" | "Lets Cofre turn on JIT by talking to this iPhone. Nothing leaves the phone." · "Cofre → this iPhone" |
| `InstancesScreen.swift:250` | "installs with Air's installer next." | "Forge installs in the next step." |
| `SettingsScreen.swift:196`, `:198` | "Air's editor…", "Air's controls editor isn't connected in this build." | "Opens full screen." · "The controls editor isn't available yet." |
| Site hero `docs/index.html:59`, README banner | "JIT" is never explained | Add once: "JIT (what makes Java fast on iPhone) and a local VPN, built in." |
| Site Step 1 `docs/index.html:91` | "We send you a link that shares your iPhone's ID" | "We send you a link. Open it on your iPhone so we can add it to Cofre." |

### 18. Numbers and step counts disagree across surfaces — CONFIRMED

| Surface | Says |
|---|---|
| App Welcome (`SetupFlow.swift:92`) | **6** Checks · **5** Minutes · 1× Computer |
| Site hero (`docs/index.html:65-67`) and README (`:9`) | **4** Steps · **10** Minutes · 1× Mac visit |
| Site step badges | 4 + 2 + 2 + 3 = **11** min |
| Site heading (`docs/index.html:75`) | "Four steps. One button each." Step 2's only button is "Don't see it?"; Step 4's is "Stuck?". |

- **Fix:**
  - App: `Stat("4", "Steps"); Stat("10", "Minutes"); Stat("1×", "Mac visit")`, with the StepBar kept as "checks".
  - Site heading: "Four steps. About 10 minutes."

### 19. Step 3 copy gaps between the site, README, Llave and the app — CONFIRMED
- **Passcode:** `PAIRING.md:18` says "tap Trust, **enter your passcode**". `docs/index.html:188`, `README.md:58` and the app (`Shared.swift:156`) leave it out. Llave says it (`StateScreen.swift:58`). Add "enter your passcode" everywhere.
- **Allow accessory:** Llave's no-device state (`StateScreen.swift:49`) never mentions the Mac's **"Allow accessory to connect?"** prompt, which `PAIRING.md:55` covers. Help copy: "Use a cable that carries data. If your Mac asks to allow the accessory, click **Allow**."
- **iPad:** All Llave copy says "iPhone" even though iPads are supported. That's acceptable, but "Pick your iPhone or iPad" would be clearer.

### 20. The Wi-Fi copy is stricter than reality — CONFIRMED (third-party sources)
- **Where:** `docs/index.html:286` and `:363`, `README.md:96` and `:146`.
- **Fix:** "Turning on JIT needs Wi-Fi or Airplane Mode. No Wi-Fi? Open Cofre, turn on Airplane Mode, tap Play, then turn Airplane Mode off once the game is loading." Verify on the 17 Pro first.

### 21. Broken links and placeholders in the README — CONFIRMED
- **Broken:** `README.md:187` links `tools/readme-art.html` and `:194` links `FACTS.md`. Both actually live under `site/` (`site/tools/…`, `site/FACTS.md`).
- **Missing file:** `.github/ISSUE_TEMPLATE/invite.yml` doesn't exist. The "Request an invite" link (`README.md:6`, `docs/app.js:5`) depends on it.
- **Placeholders:** Every `ignaciojuarez/cofre` URL returns 404 (documented), along with Llave's `getCofre` (`ContentView.swift:16`) and the mock's `sourceURL`.
- **PLAUSIBLE:** A GitHub-issue invite requires a GitHub account, and the issue is public, so "tell us who you are" ends up on a public page. Use a private form or email for invites.

### 22. The Mod page "Share" button shares the icon image — CONFIRMED
- **Where:** `ModsScreen.swift:101`. If `iconURL` is set, that's what gets shared. CurseForge projects fall back to a Modrinth URL. Also, `ColumnHeader("")` (`:100`) gives VoiceOver an empty heading.
- **Fix:** Add `ProjectSummary.pageURL` and share that. Use `ColumnHeader(p.title)`.

### 23. Launch progress isn't announced to VoiceOver — CONFIRMED (spec §2 #13)
- **Where:** `LaunchScreen.swift:27-49`.
- **Fix:** Post an announcement on `onChange(of: store.launch?.stage)`, at most once every 2 s: "Step 3 of 8, Libraries".

## Low

### 24. Duplication against "one source of truth" — CONFIRMED
- **What's good:** All hex values live in `Tokens.swift`, and there are **no device or model checks**.
- **Duplicates:**
  - The back-chevron button is implemented three times: `ColumnHeader.swift:20`, `Sheet.swift:45`, `SetupFlow.swift:51`.
  - "Label + Spacer + `SelectButton.compactStyle()` + `.padding(11).block(.panel)`" repeats six times in `SettingsScreen.swift` (plus `InstancesScreen.swift:238`). It should be one `PickerRow`.
  - The 44 pt hit-area inset is re-derived inside each component while `minimumHitArea` goes unused.
  - Raw colors bypass the tokens: `BlockSlider.swift:52-53`, `Switch.swift:45-46`.

### 25. SwiftUI performance pitfalls — CONFIRMED (code)
- `AppIcon.swift:10-12` decodes the PNG from disk on every body evaluation, and the rail and sidebar re-render on every store change. Cache a static `CGImage`.
- `Spinner.swift:11` keeps a 4 Hz `TimelineView` running under Reduce Motion. Branch so it's static.
- `CofreUI.swift:66` uses `.id(accent.id)`, so changing the accent rebuilds the whole tree. `AdaptiveShell.swift:25` uses `.id(nav.section)`, so every section switch drops scroll position and pushed state. The spec wants that state preserved (§3.1).
- `LogView.swift:26` calls `scrollTo` on every line, and the log arrays grow without bound. The launch log `Task` at `CofreStore.swift:153-155` never ends.
- `InstancesScreen.swift:136` seeds the scene from `hashValue`, so the art changes on every launch. Use a stable hash.

### 26. Keyboard and controller support — PLAUSIBLE
- `.onKeyPress(.escape)` on views that can't take focus probably never fires: `LaunchScreen.swift:19`, `Sheet.swift:28`. Use a hidden `Button` with `.keyboardShortcut(.cancelAction)`.
- The custom slider can't be adjusted with the keyboard (`BlockSlider.swift:60`). Add `.focusable()` and `.onMoveCommand`.
- In Llave, Esc quits even mid-transfer (`ContentView.swift:57`, `:117`). Ignore Esc while the state is `.pairing` or `.placing`.

### 27. Settings → About licenses are incomplete — CONFIRMED
- **Where:** `SettingsScreen.swift:406-410` lists Air, StikJIT and the fonts only.
- **Missing:** **idevice (MIT)**, which StikJIT uses through `upstream/stikjit/Sources/IdeviceFFI.swift` (MIT requires the notice), and **Amethyst (GPL-3.0)**.

### 28. Smaller copy and logic slips — CONFIRMED
- `Models.swift:281`: `agoLong` returns "last week" for anything older, including months ago.
- `LaunchScreen.swift:63` and `InstancesScreen.swift:247` hard-code "Java 21".
- The Trust step shows check icons on rows that are still unknown: `SetupFlow.swift:135-140`.
- Removing an account has no confirmation: `SettingsScreen.swift:258`.
- The CurseForge key only saves on Return: `SettingsScreen.swift:274-275`. Add a Save button.
- "Microphone" appears twice: Game → Audio and Look → Extras.

### 29. Pixel-font legibility — PLAUSIBLE
- At small bold sizes, Pixelify Sans "2" and "3" look like "8", and an uppercase "B" in badges looks like "G" ("FABRIC" reads "FAGRIC"). See the 360 px site screenshot and `ipad11-portrait-mods.png`.
- **Fix:** Use Geist SemiBold for step-number digits and badges, or test with users.

### 30. The site works well — CONFIRMED
- Weight is about 180 KB per load (25 KB HTML, 18 KB CSS, 2 KB JS, fonts at 16 KB each, tiny images), and there are no third-party requests.
- It has a skip link, `:focus-visible` rings, `role=status` copy feedback, smooth scroll only when motion isn't reduced, `prefers-contrast` support, no overflow at 360 px, and AA contrast everywhere.
- Without JavaScript the command is hidden, but `<noscript>` points to the README. That's acceptable.

---

## iloader mentions
- **Shipped Cofre files (app, Llave, site, README, `PAIRING.md`):** none ✅
- **Mentions that need cleanup:**
  - `upstream/air/METAL_TUTORIAL.txt:29`, an upstream doc. Make sure it isn't copied into the app bundle.
  - The approved mockups: `launcher-plan/ui/index.html:362` and `cofre-design/system/ipad.html:460` ("Get iloader").
  - `launcher-plan/PLAN.md:68` and `:88`.

  Update the mockups so nobody copies the old step back in.

---

## Fact-check

| Claim | Verdict | Evidence |
|---|---|---|
| **After "Don't Trust"**: `PAIRING.md` says Reset Location & Privacy; Llave says unplug and plug back in | **Llave is right as the first step.** `PAIRING.md` is only correct as a fallback. | Apple [109054](https://support.apple.com/en-us/109054): "If you choose not to trust a computer… The alert message appears every time that you connect your device to that computer." The reset is how you make a device forget computers you *trusted*. Apple [108643](https://support.apple.com/en-us/108643) says: "If you don't see the alert, or you accidentally tapped Don't Trust, reset location and privacy settings". So order the fix as unplug and replug first, reset only if no alert appears (#2). |
| **Developer Mode is hidden until the iPhone is paired with a Mac** | **True per Apple, but incomplete** | Apple, [Enabling Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device): "Developer Mode only appears in Settings if you initiate pairing or if you previously paired the device to a Mac." Apple's steps are Restart, then "swipe up, tap **Enable** … and enter your device passcode". Community reports say the switch also appears after you try to open a sideloaded or development-signed app ("Developer Mode Required"): [AltStore](https://x.com/altstoreio/status/1569403161562972161), [Apple forum 799370](https://developer.apple.com/forums/thread/799370). Cofre is development-signed, so "Open Cofre once, then check Settings" may be the faster fix. Still unverified (PLAN spike S2). Proposed copy: "Don't see it? Tap Cofre once (iOS says **Developer Mode Required**), then look again. Still missing? Do Step 3 first." |
| **AirDrop on iOS 17+ saves to Files → Downloads; "tap Accept"** | **Downloads is right. "Tap Accept" is incomplete.** | Apple DTS, [forum 737971](https://developer.apple.com/forums/thread/737971): "On iOS 17, the behavior of saving an AirDropped file to the Downloads folder (and then launching Files.app) is intended." Declaring the document type doesn't change this. Apple, [AirDrop guide](https://support.apple.com/guide/iphone/use-airdrop-to-send-items-to-nearby-devices-iphcd8b9f0af/ios): "With iOS 26.2, iPadOS 26.2, macOS 26.2, or later, if someone tries to send you an item with AirDrop and they're not in your contacts, they must use an AirDrop code." Same Apple Account: "the item is automatically accepted." Receiving requires *Contacts Only* or *Everyone for 10 Minutes* (#9). |
| **"Wi-Fi is needed to turn on JIT"** | **Mostly true: Wi-Fi *or* Airplane Mode** | [StikDebug](https://stikdebug.org/): "LocalDevVPN is not optional"; "Make sure the VPN (LocalDevVPN) is on and your device is connected to Wi-Fi." [Geode launcher guide](https://github.com/geode-sdk/ios-launcher/blob/main/APPLE-DEV-CERT-INSTALL-GUIDE.md): "LocalDevVPN only works on Wi-Fi and airplane mode". Its cellular recipe: connect the VPN, switch to Airplane Mode, launch with JIT, turn Airplane Mode off. So on cellular you aren't limited to single-player. Cofre uses its own built-in tunnel, so verify on a device (#20). |
| **"Cofre is about 760 MB"** | **Confirmed for the installed app** | Measured locally: `du -sh artifacts/Payload/Cofre.app` gives **760M**, of which `java_runtimes` is 443M and `Frameworks` 264M. The download is smaller: upstream [Air 5.1.0](https://github.com/herbrine8403/Amethyst-iOS-MyRemastered/releases) IPA is 244 MB (via the GitHub API). iPhone Storage may show a slightly different number. |
| **Memory: "Cofre picks a safe amount… 6 GB iPhones: about 150 mods"** | **Not supported** | Nothing public backs "150 mods"; it comes only from `PLAN.md` (`site/FACTS.md:25`). The code doesn't pick a safe amount (#15). Apple publishes no per-app limits. The `increased-memory-limit` entitlement only raises the jetsam cap and is no guarantee ([Apple forum 685084](https://developer.apple.com/forums/thread/685084), [summary](https://zenn.dev/mtfum/articles/ios_memory_entitlements?locale=en)). Amethyst's maintainer reports that on new installs it "doesnt work between 2gb and 4gb" on 8 GB devices ([Amethyst #33](https://github.com/AngelAuraMC/Amethyst-iOS/issues/33), [LiveContainer #852](https://github.com/LiveContainer/LiveContainer/issues/852)). Cofre's default of 4096 MB sits on that boundary. Proposed copy: "**Memory.** Phones have less RAM than PCs. If a pack closes while loading, lower Memory or Resolution in Settings → Game. Big packs (100+ mods) need a recent iPhone." |
| Pairing key stops working after an iOS update or reset | Confirmed (third-party source) | [StikDebug](https://stikdebug.org/): "If you updated or reset your device, your pairing file will no longer work." |

---

## Top 5 to fix first

1. **#1: Register `cofre.site`, or repoint `CofreLinks.pairing` to a domain you control,** before any build leaves the Mac.
2. **#8 and #3: Make "never share your pairing file" prominent in the app (S04, X04) and in Llave's AirDrop and Save states. Tell people to delete the file afterwards,** and stop claiming "nothing stays on their Mac" while Save to Desktop exists.
3. **#2 and #9: Fix the Don't Trust and AirDrop fallback copy** in `PAIRING.md`, the site, the README and Llave (unplug and replug first; AirDrop visibility and code on iOS 26.2+).
4. **#4 and #5: Make setup resume correctly and auto-advance** (no Welcome flash, start the JIT test automatically), or change the site's Step 4 copy to match what the app does.
5. **#6 and #7: Confirm before every instance Delete, and hide the dead controls** (world Delete, "+ Add server", fake "Env variables · 2 set", controller hints).
