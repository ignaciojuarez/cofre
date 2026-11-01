# Connect to a Mac: get your pairing key

**Once, about 2 minutes.** Cofre needs a pairing key so it can turn on JIT by itself. One command on a Mac puts the key straight into Cofre over the cable.

> [!CAUTION]
> **Never share this file. It's a key to your iPhone.** Don't paste or upload your pairing file to any chat, website or person, not even ChatGPT or Claude: anyone who has it can control your iPhone like a trusted computer.

## Steps

1. **Install Cofre first** ([Step 1](README.md)).
2. **Plug your iPhone into the Mac** with a cable.
3. **Open Terminal**: press <kbd>⌘</kbd> <kbd>Space</kbd>, type `Terminal`, press <kbd>Return</kbd>. Paste this command and press <kbd>Return</kbd>:

   ```sh
   curl -fsSL https://github.com/ignaciojuarez/cofre/releases/latest/download/pair.sh | sh
   ```

4. **A Cofre window opens and guides you.** Unlock your iPhone, tap **Trust**, enter your passcode, then wait for **Done**.
5. **Open Cofre on your iPhone.** It's ready.

No Mac? Borrow a friend's for 2 minutes. Nothing stays on their Mac unless you save a copy.

### If the window shows "Send with AirDrop"

Sometimes the key can't go in over the cable. Then:

1. Click **Send with AirDrop** and pick your iPhone. Not listed? On the iPhone, open Control Center, touch and hold the top-left group, tap **AirDrop → Everyone for 10 Minutes**.
2. On the iPhone, tap **Accept**. On iOS 26.2 or later it may ask for an **AirDrop code**: tap **Get AirDrop Code** and type the code on the Mac. (Same Apple Account on both? It's accepted by itself.)
3. On the iPhone, open **Files → Downloads**, tap the file named after your iPhone (it ends in `.mobiledevicepairing`), then **Share → Cofre**. Or in Cofre: **I have a file → Downloads →** that file.
4. When Cofre says **Key found**, delete the file from Downloads.

The window also has **Save a copy (delete it after sending)**, as a last resort. If you use it, AirDrop the copy from the Desktop, then move it to the Trash. Sources: Apple's [AirDrop guide](https://support.apple.com/guide/iphone/use-airdrop-to-send-items-to-nearby-devices-iphcd8b9f0af/ios).

## What the command does, in plain words

1. **Downloads a small helper**, signed by us, into a temporary folder.
2. **Opens it.** That's the Cofre window.
3. **Asks your iPhone to trust this Mac.** You tap Trust on the phone.
4. **Puts the key inside Cofre over the cable.**
5. **Deletes itself** when it says Done.

## Why it's safe

| | |
|---|---|
| **Nothing uploaded** | The key goes from the Mac to your iPhone over the cable. It's never sent to us or anyone else. |
| **Nothing installed** | The helper runs from a temporary folder and deletes itself. No app stays on the Mac, and no key either, unless you click **Save a copy**. |
| **No password** | It never asks for your Mac password, your Apple ID or `sudo`. If something asks, stop. |
| **No secrets printed** | Terminal and the window show progress only, never the key. |
| **You can read it first** | Run the command without the final `\| sh` to see the script before running it: `curl -fsSL https://github.com/ignaciojuarez/cofre/releases/latest/download/pair.sh` |
| **Open source** | The script and the helper are in [the Cofre repo](https://github.com/ignaciojuarez/cofre). |

Cofre keeps the key on your iPhone. It's never uploaded or logged.

## Troubleshooting

| You see | Do this |
|---|---|
| Nothing happens, or "No iPhone found" | Use a cable that carries data, not just charging. Unlock the iPhone. Try another port. If the Mac asks **Allow accessory to connect?**, click **Allow**. |
| No **Trust** prompt on the iPhone | Unplug, unlock the iPhone, plug in again. |
| You tapped **Don't Trust** | Unplug your iPhone, unlock it, and plug it back in. The Trust alert comes back; tap **Trust**. Still no alert? Then: **Settings → General → Transfer or Reset iPhone → Reset → Reset Location & Privacy** (this also resets app location permissions), and run the command again. Source: Apple [109054](https://support.apple.com/en-us/109054). |
| "Install Cofre first" | Finish [Step 1](README.md), then run the command again. |
| macOS says the helper can't be opened or checked | Stop. Don't change security settings to get around it. Ask us. |
| **Send with AirDrop** | Follow [the fallback above](#if-the-window-shows-send-with-airdrop). |
| JIT won't turn on after the key is in | Use Wi-Fi, or turn on Airplane Mode for a moment. Turn off other VPNs. Then **Settings → JIT & Java → Test JIT** in Cofre. |
| It worked before, but JIT stopped after an iOS update or a reset | Run the command again. A new key replaces the old one. |
| Cofre still says **Waiting for your key…** | Keep Cofre open and the iPhone unlocked. If the window said Done, close Cofre fully and open it again. |

### Ask ChatGPT or Claude

The site has a **Stuck? Ask ChatGPT or Claude** button that copies this text. AI can only explain; the command does the work. **Never give it your pairing file.** Remove email addresses, account IDs, server addresses, tokens, logs, and file paths before pasting anything.

```text
I'm setting up Cofre, a Minecraft: Java Edition launcher for iPhone. I'm stuck on Step 3: with my iPhone plugged into my Mac, I run one command in Terminal, and a Cofre window puts my pairing key into Cofre over the cable.

The steps, what the command does, and troubleshooting are here: https://github.com/ignaciojuarez/cofre/blob/main/PAIRING.md

Please read that page and tell me what to do next, one step at a time, in plain words. You can only explain; the command does the work. Never ask me for my pairing file or what's inside it.

Here's what I see:
```
