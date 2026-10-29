# Llave pairing engine

Paste one command into Terminal:

```sh
curl -fsSL <RAW_URL>/pair.sh | sh
```

`pair.sh` checks macOS and CPU architecture, downloads one pinned SHA-256 checked `Llave.app.zip`, and launches it with `open -W`. The temporary download is deleted when the window closes. `--dry-run` launches the same signed app with simulation enabled; set `LLAVE_APP_PATH` to test a local build.

The plain window auto-detects devices, waits for unlock and Trust, pairs over lockdown, enables `EnableWifiConnections`, then uses idevice house_arrest/AFC to write `Documents/StikJIT/pairingFile.plist` into `com.ignaciojuarez.cofre`. It reports Cofre missing or placement failure and offers AirDrop or Save to Desktop. No sudo is used, pairing records are never saved to usbmuxd, and secrets are never printed or uploaded.

Cofre imports the placed file at launch and logs `[Cofre] pairing imported`. If the file arrives through AirDrop on iOS 17+, it lands in Files → Downloads; use the Share sheet to send it to Cofre.

To bump idevice, update its pinned version/features in `core/Cargo.toml`, run `cargo update -p idevice`, run Rust and Swift tests, then run `scripts/release.sh`. The release script builds arm64 and x86_64, signs the app and helper with the available Developer ID identity, zips the app, writes `SHA256SUMS`, and updates the hash in `pair.sh`. It never uploads releases.
