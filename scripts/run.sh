#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -P "$(dirname "$0")/.." && pwd)"
load_config() {
  source "$ROOT/scripts/run.config"
  if [[ -f "$ROOT/scripts/run.local.config" ]]; then source "$ROOT/scripts/run.local.config"; fi
}
load_config
[[ -n "$BUILD_TOOLS" ]] || { echo "Set BUILD_TOOLS in scripts/run.local.config" >&2; exit 1; }
source "$BUILD_TOOLS/lib/common.sh"
source "$BUILD_TOOLS/lib/device.sh"
source "$BUILD_TOOLS/lib/relay.sh"
load_config # the build tools reset some of these
BUILD=0
SQIM=0
NO_INSTALL=0
LOCAL_INSTALL=0
export RELAY_HOST RELAY_DEVICE_ID SIGNING_IDENTITY TEAM_ID BOOTJDK MAKE_ARGS BUNDLE_ID TUNNEL_BUNDLE_ID
DEVICE_ID="${DEVICE_ID:-$RELAY_DEVICE_ID}"
export DEVICE_ID

[[ "$BUNDLE_ID" == com.* ]] || bt_die "invalid app bundle ID: $BUNDLE_ID"
[[ "$TUNNEL_BUNDLE_ID" == "$BUNDLE_ID."* ]] || bt_die "invalid tunnel bundle ID: $TUNNEL_BUNDLE_ID"

# Match the shared iOS runner's convenient entry points while keeping Cofre's
# Air build pipeline local to this project:
#   scripts/run.sh local fast     Build and install on a phone attached here.
#   scripts/run.sh remote fast    Build and install through the MacBook relay.
#   scripts/run.sh local sim      Use the simulator runner.
if [[ "${1:-}" == local || "${1:-}" == remote ]]; then
  WHERE=$1
  shift
  MODE=${1:-fast}
  shift || true
  case "$MODE" in
    sim)
      [[ "$WHERE" == local ]] || bt_die "simulator mode is local only"
      exec "$ROOT/scripts/sim.sh" "$@"
      ;;
    fast|full)
      BUILD=1
      [[ "$WHERE" == local ]] && LOCAL_INSTALL=1
      ;;
    *) bt_die "unknown runner mode: $MODE (use sim, fast, or full)" ;;
  esac
fi

for a in "$@"; do
  case "$a" in
    --build) BUILD=1 ;;
    --sqim) SQIM=1 ;;
    --no-install) NO_INSTALL=1 ;;
    --local) LOCAL_INSTALL=1 ;;
    --relay-host=*) RELAY_HOST=${a#*=} ;;
    --device=*) RELAY_DEVICE_ID=${a#*=}; DEVICE_ID=${a#*=} ;;
    *) bt_die "unknown option: $a" ;;
  esac
done
APP="$ROOT/artifacts/Payload/$APP_BUNDLE_NAME"
if (( BUILD )); then
  bt_step "Build ($APP_NAME)"
  AIR="$ROOT/.work/air"
  # Drop only caches copied from another tree; matching ones keep native deps incremental.
  while IFS= read -r cache; do
    dir=$(dirname "$cache")
    grep -qxF "CMAKE_CACHEFILE_DIR:INTERNAL=$dir" "$cache" || { rm -f "$cache"; rm -rf "$dir/CMakeFiles"; }
  done < <(find "$AIR" -name CMakeCache.txt)
  mkdir -p "$AIR/Natives/Assets.xcassets"
  # Apply every Air patch in order (the same patches scripts/update-upstream.sh applies). When the
  # patch set changes, first restore every file the old and new sets touch, so edited patches apply.
  stamp="$AIR/.cofre-patches"
  sum=$(cat "$ROOT"/patches/air/*.patch | shasum | cut -d' ' -f1)
  if [[ "$(head -n1 "$stamp" 2>/dev/null)" != "$sum" ]]; then
    while IFS= read -r file; do
      [[ -n "$file" ]] || continue
      git -C "$AIR" checkout -q -- "$file" 2>/dev/null || rm -f "${AIR:?}/$file"
    done < <({ tail -n +2 "$stamp" 2>/dev/null || true; sed -n 's|^+++ b/||p' "$ROOT"/patches/air/*.patch; } | sort -u)
    for patch in "$ROOT"/patches/air/*.patch; do
      git -C "$AIR" apply "$patch" || bt_die "Air patch does not apply: $(basename "$patch")"
    done
    { echo "$sum"; sed -n 's|^+++ b/||p' "$ROOT"/patches/air/*.patch; } > "$stamp"
  fi
  rm -rf "$AIR/Natives/CofreGlue" && mkdir -p "$AIR/Natives/CofreGlue"
  cp "$ROOT"/app/Glue/CofreConstants.h "$ROOT"/app/Glue/AirBridge/*.[hm] "$AIR/Natives/CofreGlue/"
  rm -rf "$ROOT/artifacts/Payload/PlugIns" "$ROOT/artifacts/Payload/Cofre.app/PlugIns" 2>/dev/null || true
  cp -R "$ROOT"/app/Resources/AppIcon/*.appiconset "$AIR/Natives/Assets.xcassets/"
  (cd -P "$AIR" && eval "gmake -j4 dsym package PLATFORM=2 BOOTJDK=\"$BOOTJDK\" JOBS=4 $MAKE_ARGS")
  mkdir -p "$ROOT/artifacts/Payload"; rm -rf "$APP"; IPA=$(find -L "$ROOT/.work/air/artifacts" -maxdepth 1 -type f -name "*-ios.ipa" -print -quit)
  if [[ -n "$IPA" && -f "$IPA" ]]; then unzip -q -o "$IPA" -d "$ROOT/artifacts"; else BUILT_APP=$(find "$AIR/Natives/build" -maxdepth 1 -type d -name "*.app" -print -quit); [[ -n "$BUILT_APP" && -d "$BUILT_APP" ]] || bt_die "no IPA or app artifact"; cp -R "$BUILT_APP" "$ROOT/artifacts/Payload/AngelAuraAmethyst.app"; fi
  mv "$ROOT/artifacts/Payload/AngelAuraAmethyst.app" "$APP"
  python3 "$ROOT/scripts/update-info-plist.py" "$APP/Info.plist"
  bt_step "Repair Metallum agent"
  python3 "$ROOT/scripts/repair-metallum-agent.py" "$APP/libs/metallum_agent.jar" || bt_die "metallum_agent.jar still has missing classes"
  bt_step "Generate renderer manifest"
  python3 "$ROOT/scripts/generate-renderer-manifest.py" "$APP/libs/metallum_agent.jar" "$APP/RendererManifest.json"
  bt_step "Build CofreCore framework"
  SIGNING="$ROOT/.build-tools/signing"
  "$ROOT/scripts/stikjit-sources.sh" || bt_die "could not prepare StikJIT sources"
  (cd "$SIGNING" && xcodegen generate --spec project.yml --quiet) || bt_die "could not generate the signing project"
  xcodebuild -project "$SIGNING/CofreSigning.xcodeproj" -scheme CofreSigning -configuration Debug \
    -destination 'generic/platform=iOS' -derivedDataPath "$SIGNING/build" \
    -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM_ID" -quiet build || bt_die "Cofre signing build failed"
  mkdir -p "$APP/Frameworks"
  cp -R "$SIGNING/build/Build/Products/Debug-iphoneos/CofreCore.framework" "$APP/Frameworks/"
  # SwiftPM resources (CofreUI fonts) live in *_*.bundle; Bundle.module looks for them at the app root.
  for bundle in "$SIGNING"/build/Build/Products/Debug-iphoneos/*_*.bundle; do
    rm -rf "${APP:?}/$(basename "$bundle")"
    cp -R "$bundle" "$APP/"
  done
  [[ -d "$APP/CofreUI_CofreUI.bundle" ]] || bt_die "CofreUI resources missing from the app"
  rm -rf "$APP/PlugIns"
  mkdir -p "$APP/PlugIns"
  cp -R "$SIGNING/build/Build/Products/Debug-iphoneos/PacketTunnel.appex" "$APP/PlugIns/PacketTunnel.appex"
  "$ROOT/scripts/slim-app.sh" "$APP"
  python3 "$ROOT/scripts/sign-development.py"
fi
[[ -d "$APP" ]] || bt_die "no signed app at $APP; run with --build"
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q get-task-allow || bt_die "not development-signed"
if (( SQIM )); then bt_sqim_upload "$APP"; exit 0; fi
if (( NO_INSTALL )); then exit 0; fi
if (( LOCAL_INSTALL )); then
  [[ -n "$DEVICE_ID" ]] || bt_die "set DEVICE_ID (or pass --device=<udid>) for local installs"
  bt_step "Install $APP_NAME on $DEVICE_ID"
  xcrun devicectl device install app --device "$DEVICE_ID" "$APP"
  xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing "$BUNDLE_ID"
else
  bt_relay_preflight
  bt_relay_install "$APP" "$BUNDLE_ID"
fi
