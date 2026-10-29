#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_TOOLS="${BUILD_TOOLS:-<local-volume>/Developer/kiwios/tools/build-runners}"
source "$BUILD_TOOLS/lib/common.sh"; source "$BUILD_TOOLS/lib/device.sh"; source "$BUILD_TOOLS/lib/relay.sh"
source "$ROOT/scripts/run.config"; [[ ! -f "$ROOT/scripts/run.local.config" ]] || source "$ROOT/scripts/run.local.config"
BUILD=0; SQIM=0
export RELAY_HOST RELAY_DEVICE_ID SIGNING_IDENTITY TEAM_ID BOOTJDK MAKE_ARGS
for a in "$@"; do case "$a" in --build) BUILD=1;; --sqim) SQIM=1;; --relay-host=*) RELAY_HOST=${a#*=};; --device=*) RELAY_DEVICE_ID=${a#*=};; *) bt_die "unknown option: $a";; esac; done
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
  if ! grep -q "CofreMakeRootViewController" "$AIR/Natives/SceneDelegate.m"; then git -C "$AIR" apply "$ROOT/patches/air/0002-install-cofre-root.patch" || bt_die "failed to apply Cofre root patch"; fi
  mkdir -p "$AIR/Natives/CofreGlue"
  cp "$ROOT"/app/Glue/AirBridge/AirBridgeAdapter.* "$AIR/Natives/CofreGlue/"
  cp "$ROOT"/app/Glue/AirBridge/CofreStartup.m "$AIR/Natives/CofreGlue/"
  cp "$ROOT"/app/Glue/AirBridge/CofreTunnelService.* "$AIR/Natives/CofreGlue/"
  cp "$ROOT"/app/Glue/AirBridge/CofreRootFactory.m "$AIR/Natives/CofreGlue/"
  cp "$ROOT"/app/Glue/AirBridge/CofrePairingImport.m "$AIR/Natives/CofreGlue/"
  python3 - <<PY2
from pathlib import Path
p=Path("$AIR/Natives/CMakeLists.txt")
s=p.read_text()
needle="  main_hook.m\n"
for f in ("CofreGlue/AirBridgeAdapter.m", "CofreGlue/CofreStartup.m", "CofreGlue/CofreTunnelService.m", "CofreGlue/CofrePairingImport.m", "CofreGlue/CofreRootFactory.m"):
    if f not in s: s=s.replace(needle, needle+"  "+f+"\n")
if "NetworkExtension" not in s: s=s.replace("target_link_libraries(AngelAuraAmethyst", "target_link_libraries(AngelAuraAmethyst\n  -framework NetworkExtension")
p.write_text(s)
PY2
  rm -rf "$ROOT/artifacts/Payload/PlugIns" "$ROOT/artifacts/Payload/Cofre.app/PlugIns" 2>/dev/null || true
  cp -R "$ROOT"/app/Resources/AppIcon/*.appiconset "$AIR/Natives/Assets.xcassets/"
  (cd "$AIR" && eval "gmake -j4 dsym package PLATFORM=2 BOOTJDK=\"$BOOTJDK\" JOBS=4 $MAKE_ARGS")
  mkdir -p "$ROOT/artifacts/Payload"; rm -rf "$APP"; IPA=$(find -L "$ROOT/.work/air/artifacts" -maxdepth 1 -type f -name "*-ios.ipa" -print -quit)
  if [[ -n "$IPA" && -f "$IPA" ]]; then unzip -q -o "$IPA" -d "$ROOT/artifacts"; else BUILT_APP=$(find "$AIR/Natives/build" -maxdepth 1 -type d -name "*.app" -print -quit); [[ -n "$BUILT_APP" && -d "$BUILT_APP" ]] || bt_die "no IPA or app artifact"; cp -R "$BUILT_APP" "$ROOT/artifacts/Payload/AngelAuraAmethyst.app"; fi
  mv "$ROOT/artifacts/Payload/AngelAuraAmethyst.app" "$APP"
  INFO="$APP/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" "$INFO" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0 dict" "$INFO" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$INFO" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string cofre" "$INFO" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes array" "$INFO" 2>/dev/null || /usr/libexec/PlistBuddy -c "Print :CFBundleDocumentTypes" "$INFO" >/dev/null || bt_die "plist document types failed"
  /usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0 dict" "$INFO" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:CFBundleTypeName string iPhone Pairing File" "$INFO" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes array" "$INFO" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:0 string com.apple.mobiledevicepairing" "$INFO" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:1 string com.apple.property-list" "$INFO" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :UTImportedTypeDeclarations array" "$INFO" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :UTImportedTypeDeclarations:0 dict" "$INFO" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :UTImportedTypeDeclarations:0:UTTypeIdentifier string com.apple.mobiledevicepairing" "$INFO" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :UTImportedTypeDeclarations:0:UTTypeConformsTo array" "$INFO" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :UTImportedTypeDeclarations:0:UTTypeConformsTo:0 string public.data" "$INFO" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :UTImportedTypeDeclarations:0:UTTypeTagSpecification dict" "$INFO" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :UTImportedTypeDeclarations:0:UTTypeTagSpecification:public.filename-extension array" "$INFO" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :UTImportedTypeDeclarations:0:UTTypeTagSpecification:public.filename-extension:0 string mobiledevicepairing" "$INFO" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :UTImportedTypeDeclarations:0:UTTypeTagSpecification:public.filename-extension:1 string plist" "$INFO" 2>/dev/null || true
  echo "[Cofre] document types:"; /usr/libexec/PlistBuddy -c "Print :CFBundleDocumentTypes" "$INFO" >/dev/null || bt_die "document types missing"; echo "[Cofre] imported types:"; /usr/libexec/PlistBuddy -c "Print :UTImportedTypeDeclarations" "$INFO" >/dev/null || bt_die "imported types missing"
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
