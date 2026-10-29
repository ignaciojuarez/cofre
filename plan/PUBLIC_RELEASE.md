# Cofre: Apple account and going public

Status markers: ✅ known, ⚠️ verify before relying on it. Rows marked [n] were checked on 2026-10-28; sources in §4.

## 1. What our paid Apple Developer account lets us skip

| Thing | With our paid account (friends now) | A free Apple ID (public sideloading) |
|---|---|---|
| Install | We sign Cofre for each registered iPhone and send an install link | The user sideloads with their own Apple ID (SideStore or AltStore) |
| Expiry | 1 year ✅ [1] | 7 days; refresh weekly ✅ [2] |
| App limit | None | 3 sideloaded apps at a time ✅ [2] |
| Built-in VPN (Network Extension) | ✅ | ❌ Free accounts can't sign it ✅ [3], so a separate VPN app is needed |
| Extra RAM entitlement | ✅ | Partly ✅ [3][4]: Increased Memory Limit works (AltStore 2.2+, Xcode; SideStore drops it). Extended Virtual Addressing is paid-only |
| JIT (`get-task-allow`) | ✅ | ✅ Every sideloaded app is development-signed |
| Device cap | 100 iPhones per membership year ✅ | Not applicable |

**Yes, we're skipping steps.** Today the account handles signing, yearly expiry, the built-in VPN and the RAM boost. A public user without our account would have to sideload, refresh weekly and run a separate VPN app.

## 2. Problems if we make it public

| # | Risk | Impact | Mitigation |
|---|---|---|---|
| 1 | **Apple Program License:** development signing is meant for your own team's testing. Registering strangers' devices is a misuse. | Apple can revoke the certificate (every install stops launching) or terminate the account. | Keep our-account installs to a small set of known friends. Public users sideload with their own Apple ID. |
| 2 | **No App Store, TestFlight or EU marketplace.** Distribution strips `get-task-allow`, so there's no JIT, and launchers that run downloaded code are rejected. | Only sideloading or development signing works. | Ship the IPA on GitHub Releases for sideloading. |
| 3 | **Microsoft sign-in:** Air's Azure client ID belongs to Air. | A public app needs its own Azure app plus Mojang's Minecraft API access approval ⚠️ [5] (likely: launchers report HTTP 403 until approved), which takes time. | Register our own client ID before any public release. It's a single config value. |
| 4 | **Minecraft brand:** no "Minecraft" in the app name and no Mojang assets. | Takedown risk. | Our pixel art is original. Add "Not an official Minecraft product. Not approved by or associated with Mojang or Microsoft." Users must own Java Edition. |
| 5 | **Licenses:** Air is GPL-3.0, so all of Cofre (UI included) is GPL-3.0. StikJIT is MPL-2.0, idevice is MIT, and the fonts are OFL. | We must publish source with every build. | Public repo, NOTICE file, Licenses screen. |
| 6 | **iOS updates** can break JIT (TXM), Developer Mode or pairing. | Sudden "stopped working" reports. | Pin known-good iOS versions on the site and add an in-app JIT self-test. |
| 7 | **The pairing file is a key to the phone.** | A leak gives someone access to the device. | Llave stores nothing and Cofre keeps the file local. The site says "never share it". |
| 8 | **Llave on Mac only.** | Windows and Linux friends are stuck. | The idevice core is cross-platform. Add a Windows build later. |
| 9 | **Llave distribution** needs Developer ID signing plus notarization. | Gatekeeper blocks unsigned apps. | Our paid account covers it. Add notarization credentials to the build. |
| 10 | **Hosting:** the IPA is about 250 MB. | Bandwidth. | GitHub Releases (2 GB per file limit). |
| 11 | **Server-join packs run code.** | Malicious servers. | Signed cards, a trust prompt on first join, verified hashes (see `server-join/`). |

## 3. Recommended tracks

| Track | Who | How | Features |
|---|---|---|---|
| A · Friends | Small and known, at most 100 | Our account, install link (in person: plug into the Mac) | Everything |
| B · Public | Anyone | Open-source IPA, sideloaded with a free Apple ID, plus a VPN app | Everything except the built-in VPN; refresh weekly |
| C · Power users | Their own paid account | They sign it themselves | Everything |

Build variant needed for B: Cofre must detect a missing Network Extension entitlement and fall back to "install a VPN app" in setup.

## 4. Fact-check (2026-10-28)

| # | Finding | Source |
|---|---|---|
| 1 | Development certificates are valid for 1 year. | Apple, [Managing development certificates](https://developer.apple.com/library/archive/documentation/ToolsLanguages/Conceptual/DevPortalGuide/ManagingiOSDevelopmentCertificates/ManagingiOSDevelopmentCertificates.html) |
| 2 | Free (Personal Team): 3 apps per device, profiles expire 7 days from issuance, 10 App IDs per 7 days. | Apple, [Choosing a membership](https://developer.apple.com/support/compare-memberships/) |
| 3 | The free "Apple Developer" tier has no *Network extensions*, *Personal VPN*, *Extended Virtual Addressing* or *Increased Debugging Memory Limit*. | Apple, [Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios); Apple DTS, [forum 746373](https://developer.apple.com/forums/thread/746373) |
| 4 | *Increased Memory Limit* can be added on a free account. SideStore currently drops it. | [AltStore 2.2 release notes](https://faq.altstore.io/release-notes/altstore); [SideStore #1616](https://github.com/SideStore/SideStore/issues/1616) |
| 5 | New Azure client IDs get HTTP 403 from `login_with_xbox` until Mojang approves them via [aka.ms/mce-reviewappid](https://aka.ms/mce-reviewappid). Evidence is third-party launcher docs; Mojang's [help article](https://help.minecraft.net/hc/en-us/articles/16254801392141) didn't load (JS-only), so this stays ⚠️. | e.g. [HU-Minecraft #1](https://github.com/rb98t/HU-Minecraft/issues/1) |
| 6 | **AirDrop has no "Open with…" since iOS 17.** Received files go to Files → Downloads, so friends must pick the file inside Cofre (or Share → Cofre). | Apple DTS, [forum 737971](https://developer.apple.com/forums/thread/737971) (accepted answer) |
| 7 | **Developer Mode only appears after the device is paired with a Mac.** Path: Settings → Privacy & Security → Developer Mode (under Security) → Restart → confirm (Apple says "Enable") + passcode. | Apple, [Enabling Developer Mode on a device](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device) |
