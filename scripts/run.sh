#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; APP_ROOT="$ROOT"
BUILD_TOOLS="${BUILD_TOOLS:-<local-volume>/Developer/kiwios/tools/build-runners}"
source "$BUILD_TOOLS/lib/common.sh"; source "$BUILD_TOOLS/lib/device.sh"; source "$BUILD_TOOLS/lib/relay.sh"
source "$ROOT/scripts/run.config"; [[ ! -f "$ROOT/scripts/run.local.config" ]] || source "$ROOT/scripts/run.local.config"
BUILD=0
for a in "$@"; do case "$a" in --build) BUILD=1;; --relay-host=*) RELAY_HOST=${a#*=};; --device=*) RELAY_DEVICE_ID=${a#*=};; *) bt_die "unknown option: $a";; esac; done
APP="$ROOT/artifacts/Payload/$APP_BUNDLE_NAME"
if (( BUILD )); then
  bt_step "Build ($APP_NAME)"
  (cd "$ROOT/upstream/air" && eval "gmake -j4 dsym package PLATFORM=2 BOOTJDK=\"$BOOTJDK\" JOBS=4 $MAKE_ARGS")
  mkdir -p "$ROOT/artifacts/Payload"; unzip -q -o "$(ls -t "$ROOT/upstream/air"/artifacts/*-ios.ipa | head -1)" -d "$ROOT/artifacts"
  mv "$ROOT/artifacts/Payload/AngelAuraAmethyst.app" "$APP"
  python3 "$ROOT/scripts/sign-development.py"
fi
[[ -d "$APP" ]] || bt_die "no signed app at $APP; run with --build"
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q get-task-allow || bt_die "not development-signed"
bt_relay_preflight; bt_relay_install "$APP" "$BUNDLE_ID"
