#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -P "$(dirname "$0")/.." && pwd)"
UDID="${1:-SIMULATOR_UDID}"
SHA="$(git -C "$ROOT" rev-parse --short HEAD)"
OUT="${COFRE_SIM_OUT:-${TMPDIR:-/tmp}/cofre-sim-${SHA}-$$}"
APP="$OUT/Cofre.app"
SIGNING="$ROOT/.build-tools/signing"
mkdir -p "$OUT"
source "$ROOT/scripts/run.config"
[[ -f "$ROOT/scripts/run.local.config" ]] && source "$ROOT/scripts/run.local.config"
echo "CofreBuild $SHA"
echo "Output $OUT"
# Air's simulator CMake graph still links device-only framework stubs. Build
# current CofreCore, then retag and sign every Mach-O in this disposable copy.
cp -R "$ROOT/artifacts/Payload/Cofre.app" "$APP"
rm -rf "$APP/PlugIns"
python3 "$ROOT/scripts/update-info-plist.py" "$APP/Info.plist"
(cd "$SIGNING" && xcodegen generate --spec project.yml --quiet)
xcodebuild -project "$SIGNING/CofreSigning.xcodeproj" -scheme CofreSigning -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath "$OUT/derived" CODE_SIGNING_ALLOWED=NO build >/dev/null
CORE="$OUT/derived/Build/Products/Debug-iphoneos/CofreCore.framework"
[[ -d "$CORE" ]] || { echo "CofreCore.framework was not built" >&2; exit 1; }
rm -rf "$APP/Frameworks/CofreCore.framework"
cp -R "$CORE" "$APP/Frameworks/"
for bundle in "$OUT/derived"/Build/Products/Debug-iphoneos/*_*.bundle; do
  [[ -d "$bundle" ]] || continue
  rm -rf "$APP/$(basename "$bundle")"
  cp -R "$bundle" "$APP/"
done
retag() {
  local file="$1" tmp="$1.vtool"
  file "$file" | grep -q 'Mach-O' || return 0
  xcrun vtool -remove-build-version ios -output "$tmp" "$file" >/dev/null 2>&1 || cp "$file" "$tmp"
  mv "$tmp" "$file"
  xcrun vtool -remove-build-version iossim -output "$tmp" "$file" >/dev/null 2>&1 || cp "$file" "$tmp"
  mv "$tmp" "$file"
  xcrun vtool -set-build-version iossim 14.0 26.2 -output "$tmp" "$file" >/dev/null
  mv "$tmp" "$file"
}
while IFS= read -r -d '' f; do retag "$f"; done < <(find "$APP" -type f -print0)
while IFS= read -r -d '' f; do
  file "$f" | grep -q 'Mach-O' && codesign --force --sign - "$f" >/dev/null
done < <(find "$APP/Frameworks" -type f -print0)
codesign --force --sign - "$APP"
while IFS= read -r -d '' f; do
  xcrun vtool -show-build "$f" 2>/dev/null | grep -q 'platform IOSSIMULATOR' || { echo "platform validation failed: $f" >&2; exit 1; }
done < <(find "$APP" -type f -print0 | while IFS= read -r -d '' f; do file "$f" | grep -q 'Mach-O' && printf '%s\0' "$f"; done)
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" com.ignaciojuarez.cofre
echo "Installed $APP on $UDID"
