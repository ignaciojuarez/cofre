#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_TOOLS="${BUILD_TOOLS:-<local-volume>/Developer/kiwios/tools/build-runners}"
source "$BUILD_TOOLS/lib/common.sh"
source "$BUILD_TOOLS/lib/device.sh"
source "$BUILD_TOOLS/lib/relay.sh"
source "$ROOT/scripts/run.config"
if [[ -f "$ROOT/scripts/run.local.config" ]]; then
  source "$ROOT/scripts/run.local.config"
fi
BUILD=0
SQIM=0
export RELAY_HOST RELAY_DEVICE_ID SIGNING_IDENTITY TEAM_ID BOOTJDK MAKE_ARGS
for a in "$@"; do
  case "$a" in
    --build) BUILD=1 ;;
    --sqim) SQIM=1 ;;
    --relay-host=*) RELAY_HOST=${a#*=} ;;
    --device=*) RELAY_DEVICE_ID=${a#*=} ;;
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
  # Apply every Air patch once, in order (the same patches scripts/update-upstream.sh applies).
  for patch in "$ROOT"/patches/air/*.patch; do
    git -C "$AIR" apply --reverse --check "$patch" 2>/dev/null && continue
    git -C "$AIR" apply "$patch" || bt_die "Air patch does not apply: $(basename "$patch")"
  done
  rm -rf "$AIR/Natives/CofreGlue" && mkdir -p "$AIR/Natives/CofreGlue"
  cp "$ROOT"/app/Glue/CofreConstants.h "$ROOT"/app/Glue/AirBridge/*.[hm] "$AIR/Natives/CofreGlue/"
  rm -rf "$ROOT/artifacts/Payload/PlugIns" "$ROOT/artifacts/Payload/Cofre.app/PlugIns" 2>/dev/null || true
  cp -R "$ROOT"/app/Resources/AppIcon/*.appiconset "$AIR/Natives/Assets.xcassets/"
  (cd "$AIR" && eval "gmake -j4 dsym package PLATFORM=2 BOOTJDK=\"$BOOTJDK\" JOBS=4 $MAKE_ARGS")
  mkdir -p "$ROOT/artifacts/Payload"; rm -rf "$APP"; IPA=$(find -L "$ROOT/.work/air/artifacts" -maxdepth 1 -type f -name "*-ios.ipa" -print -quit)
  if [[ -n "$IPA" && -f "$IPA" ]]; then unzip -q -o "$IPA" -d "$ROOT/artifacts"; else BUILT_APP=$(find "$AIR/Natives/build" -maxdepth 1 -type d -name "*.app" -print -quit); [[ -n "$BUILT_APP" && -d "$BUILT_APP" ]] || bt_die "no IPA or app artifact"; cp -R "$BUILT_APP" "$ROOT/artifacts/Payload/AngelAuraAmethyst.app"; fi
  mv "$ROOT/artifacts/Payload/AngelAuraAmethyst.app" "$APP"
  python3 "$ROOT/scripts/update-info-plist.py" "$APP/Info.plist"
  bt_step "Build CofreCore framework"
  SIGNING="$ROOT/.build-tools/signing"
  (cd "$SIGNING" && xcodegen generate --spec project.yml --quiet) || bt_die "could not generate the signing project"
  xcodebuild -project "$SIGNING/CofreSigning.xcodeproj" -scheme CofreSigning -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath "$SIGNING/build" -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM_ID" -quiet build || bt_die "CofreCore build failed"
  mkdir -p "$APP/Frameworks"
  cp -R "$SIGNING/build/Build/Products/Debug-iphoneos/CofreCore.framework" "$APP/Frameworks/"
  bt_step "Build VPN extension"
  SIGNING="$ROOT/.build-tools/signing"
  (cd "$SIGNING" && xcodegen generate --spec project.yml --quiet) || bt_die "could not generate the signing project"
  xcodebuild -project "$SIGNING/CofreSigning.xcodeproj" -scheme CofreSigning -configuration Debug \
    -destination 'generic/platform=iOS' -derivedDataPath "$SIGNING/build" \
    -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM_ID" -quiet build || bt_die "VPN extension build failed"
  rm -rf "$APP/PlugIns"
  mkdir -p "$APP/PlugIns"
  cp -R "$SIGNING/build/Build/Products/Debug-iphoneos/PacketTunnel.appex" "$APP/PlugIns/PacketTunnel.appex"
  python3 "$ROOT/scripts/sign-development.py"
fi
[[ -d "$APP" ]] || bt_die "no signed app at $APP; run with --build"
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q get-task-allow || bt_die "not development-signed"
if (( SQIM )); then bt_sqim_upload "$APP"; exit 0; fi
bt_relay_preflight; bt_relay_install "$APP" "$BUNDLE_ID"
