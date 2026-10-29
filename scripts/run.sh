#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; APP_ROOT="$ROOT"
BUILD_TOOLS="${BUILD_TOOLS:-<local-volume>/Developer/kiwios/tools/build-runners}"
source "$BUILD_TOOLS/lib/common.sh"; source "$BUILD_TOOLS/lib/device.sh"; source "$BUILD_TOOLS/lib/relay.sh"
source "$ROOT/scripts/run.config"; [[ ! -f "$ROOT/scripts/run.local.config" ]] || source "$ROOT/scripts/run.local.config"
BUILD=0; SQIM=0
for a in "$@"; do case "$a" in --build) BUILD=1;; --sqim) SQIM=1;; --relay-host=*) RELAY_HOST=${a#*=};; --device=*) RELAY_DEVICE_ID=${a#*=};; *) bt_die "unknown option: $a";; esac; done
APP="$ROOT/artifacts/Payload/$APP_BUNDLE_NAME"
if (( BUILD )); then
  bt_step "Build ($APP_NAME)"
  AIR="$ROOT/.work/air"
  find "$AIR" -name CMakeCache.txt -delete
  find "$AIR" -type d -name CMakeFiles -prune -exec rm -rf {} +
  mkdir -p "$AIR/Natives/Assets.xcassets"
  mkdir -p "$AIR/Natives/CofreGlue"
  cp "$ROOT"/app/Glue/AirBridge/AirBridgeAdapter.* "$AIR/Natives/CofreGlue/"
  cp "$ROOT"/app/Glue/AirBridge/CofreStartup.m "$AIR/Natives/CofreGlue/"
  cp "$ROOT"/app/Glue/AirBridge/CofreTunnelService.* "$AIR/Natives/CofreGlue/"
  python3 - <<PY2
from pathlib import Path
p=Path("$AIR/Natives/CMakeLists.txt")
s=p.read_text()
needle="  main_hook.m\n"
for f in ("CofreGlue/AirBridgeAdapter.m", "CofreGlue/CofreStartup.m", "CofreGlue/CofreTunnelService.m"):
    if f not in s: s=s.replace(needle, needle+"  "+f+"\n")
if "NetworkExtension" not in s: s=s.replace("target_link_libraries(AngelAuraAmethyst", "target_link_libraries(AngelAuraAmethyst\n  -framework NetworkExtension")
p.write_text(s)
PY2
  rm -rf "$ROOT/artifacts/Payload/PlugIns" "$ROOT/artifacts/Payload/Cofre.app/PlugIns" 2>/dev/null || true
  cp -R "$ROOT"/app/Resources/AppIcon/*.appiconset "$AIR/Natives/Assets.xcassets/"
  (cd "$AIR" && eval "gmake -j4 dsym package PLATFORM=2 BOOTJDK=\"$BOOTJDK\" JOBS=4 $MAKE_ARGS")
  mkdir -p "$ROOT/artifacts/Payload"; rm -rf "$APP"; unzip -q -o "$(ls -t "$ROOT/.work/air"/artifacts/*-ios.ipa | head -1)" -d "$ROOT/artifacts"
  mv "$ROOT/artifacts/Payload/AngelAuraAmethyst.app" "$APP"
  rm -rf "$APP/PlugIns"
  mkdir -p "$APP/PlugIns"
  cp -R "$ROOT/.build-tools/signing/build/Build/Products/Debug-iphoneos/PacketTunnel.appex" "$APP/PlugIns/PacketTunnel.appex"
  python3 "$ROOT/scripts/sign-development.py"
fi
[[ -d "$APP" ]] || bt_die "no signed app at $APP; run with --build"
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q get-task-allow || bt_die "not development-signed"
if (( SQIM )); then bt_sqim_upload "$APP"; exit 0; fi
bt_relay_preflight; bt_relay_install "$APP" "$BUNDLE_ID"
