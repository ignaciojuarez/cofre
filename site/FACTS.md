# Fact-check for the site (2026-10-28)

✅ confirmed · ❌ refuted (site says the corrected version) · ⚠️ from our own plan, check on a device before publishing

## Checked against outside sources

| Claim | Verdict | What the site says | Sources |
|---|---|---|---|
| Free Apple ID: apps expire after 7 days, 3 apps per device | ✅ | "7 days", "3 apps at once" | Apple, [Choosing a membership](https://developer.apple.com/support/compare-memberships/): "You can install up to 3 apps per device. Provisioning profiles … will expire 7 days from issuance." Also 10 App IDs per 7 days. |
| Paid account: 1 year | ✅ | "1 year" | Apple, [Managing development certificates](https://developer.apple.com/library/archive/documentation/ToolsLanguages/Conceptual/DevPortalGuide/ManagingiOSDevelopmentCertificates/ManagingiOSDevelopmentCertificates.html): development certificates are valid for one year · [SideStore FAQ](https://docs.sidestore.io/docs/faq) |
| Free accounts can't use the built-in VPN (Network Extension) | ✅ | "Built-in VPN: No, use a separate VPN app" | Apple, [Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios): *Network extensions* and *Personal VPN* are unticked in the free "Apple Developer" column · Apple DTS, [forum 746373](https://developer.apple.com/forums/thread/746373) |
| Extra RAM needs a paid account | Partly | Not on the site | Same Apple table: *Extended Virtual Addressing* and *Increased Debugging Memory Limit* are paid-only. *Increased Memory Limit* works on free accounts via [AltStore 2.2+](https://faq.altstore.io/release-notes/altstore) or Xcode; SideStore drops it ([issue #1616](https://github.com/SideStore/SideStore/issues/1616)). |
| Developer Mode: Settings → Privacy & Security → Developer Mode → Restart → confirm + passcode | ✅ | Exact path, "Turn On (or Enable)" | Apple, [Enabling Developer Mode on a device](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device): switch "under Security", tap **Restart**, then "swipe up, tap Enable … and enter your device passcode". Third-party iOS 26 guides call the button **Turn On**, so the site names both. |
| The Developer Mode switch is always there | ❌ | "Don't see it? Do Step 3 first" | Same Apple page: "Developer Mode only appears in Settings if you initiate pairing or if you previously paired the device to a Mac." |
| AirDrop shows "Open with…" so the file opens in Cofre | ❌ | Fallback: "Files → Downloads → the file → Share → Cofre". Receiving needs *Everyone for 10 Minutes* (or Contacts Only); iOS 26.2+ may ask for an AirDrop code, typed on the sender (checked 2026-10-29). Cofre declares the `.mobiledevicepairing` document type, so Share → Cofre works | Apple DTS, [forum 737971](https://developer.apple.com/forums/thread/737971) (accepted answer): "On iOS 17, the behavior of saving an AirDropped file to the Downloads folder (and then launching Files.app) is intended." Apple, [AirDrop guide](https://support.apple.com/guide/iphone/use-airdrop-to-send-items-to-nearby-devices-iphcd8b9f0af/ios): "some items may be saved in the Files app." Same Apple Account: accepted automatically. |
| After "Don't Trust", unplug and replug: the alert returns. Reset Location & Privacy only if it never does | ✅ (2026-10-29) | PAIRING.md, Llave | Apple [109054](https://support.apple.com/en-us/109054), [108643](https://support.apple.com/en-us/108643) |
| Macs ask "Allow accessory to connect?" for a new USB device | ✅ | PAIRING.md troubleshooting: click Allow | Apple, [Allow USB and other accessories to connect](https://support.apple.com/102282): Mac laptops with Apple silicon, default "Ask for New Accessories". |
| Bedrock players need Geyser to join a Java server | ✅ | "only if the server runs Geyser" | Common knowledge; Java and Bedrock use different protocols. |

## From our own plan (not verified outside)

| Claim on the site | From |
|---|---|
| Tested on iPhone 17 Pro, iOS 26 | Brief |
| App about 760 MB, 1–6 GB per instance, keep 8 GB free | `launcher-plan/PLAN.md` §5 Storage |
| ~~6 GB iPhones: about 150 mods~~ Removed 2026-10-29: nothing public backs it. The site now says "Cofre picks a safe amount automatically" (auto RAM is the default) | UI review fact-check |
| JIT needs Wi-Fi or Airplane Mode; on cellular, turn on Airplane Mode, tap Play, turn it off once loading | UI review fact-check (2026-10-29): [StikDebug](https://stikdebug.org/), [Geode guide](https://github.com/geode-sdk/ios-launcher/blob/main/APPLE-DEV-CERT-INSTALL-GUIDE.md). ⚠️ Cofre uses its own tunnel: verify on the 17 Pro |
| One VPN at a time; JIT needs internet once after a restart (DDI) | `PLAN.md` §5 |
| Invite builds last 1 year, banner 30 days before, reinstall keeps data | `PLAN.md` §3 |
| Pairing file breaks after iOS update / reset | `PLAN.md` §5, [StikDebug guide](https://github.com/StikDebug/StikDebug-Guide/blob/main/pairing_file.md) |
| Mods with desktop natives fail (Simple Voice Chat, Plasmo Voice, Sound Physics Remastered) | `launcher-plan/server-join/SPEC.md` §6.1 |
| One-tap Join is "coming" | `server-join/SPEC.md` (spec only, not built) |
| Step 3 command: downloads a signed helper to a temp folder, opens a Cofre window, puts the key in Cofre over the cable, deletes itself; "Send with AirDrop" fallback writes `.mobiledevicepairing` | User brief, 2026-10-28. **Not built yet:** `pair.sh` and the helper don't exist, so the window's wording is assumed. |
| In-app: Setup "Connect to a Mac" → "Waiting for your key…" (auto) + "I have a file"; Settings → JIT & Java → Test JIT | `cofre/app/UI` commit `bf072b2`; `DESIGN_SYSTEM.md` §4 (S04, X04) |
