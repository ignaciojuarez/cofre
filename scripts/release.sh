#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
PUBLISH=0; CHECK=0
for arg in "$@"; do case "$arg" in --publish) PUBLISH=1;; --check) CHECK=1;; *) echo "usage: $0 [--check] [--publish]" >&2; exit 2;; esac; done
APP="artifacts/Payload/Cofre.app"
if [[ ! -d "$APP" && $CHECK -eq 0 ]]; then mkdir -p .work; while ! mkdir .work/.build-lock 2>/dev/null; do sleep 1; done; trap 'rmdir .work/.build-lock 2>/dev/null || true' EXIT; scripts/run.sh --build --relay-host=none.invalid; fi
[[ -d "$APP" ]] || { echo "missing $APP" >&2; exit 1; }
if (( CHECK )); then
  codesign --verify --deep --strict "$APP"
  PROFILE="$APP/embedded.mobileprovision"; [[ -f "$PROFILE" ]] || { echo "missing embedded.mobileprovision" >&2; exit 1; }
  TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
  security cms -D -i "$PROFILE" > "$TMP"
  COUNT=$(/usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$TMP" 2>/dev/null | grep -c '^    ' || true)
  echo "device count: $COUNT"
  exit 0
fi
TAG="v0.1.$(python3 - <<'PY'
import plistlib
print(plistlib.load(open('artifacts/Payload/Cofre.app/Info.plist','rb'))['CofreBuildNumber'])
PY
)"
rm -rf .work/release Payload manifest.plist Cofre.ipa; mkdir -p .work/release/Payload
cp -R "$APP" .work/release/Payload/Cofre.app
(cd .work/release && zip -qry ../../Cofre.ipa Payload)
python3 - "$TAG" <<'PY'
import plistlib,sys
from pathlib import Path
tag=sys.argv[1]
plist={'items':[{'assets':[{'kind':'software-package','url':f'https://github.com/ignaciojuarez/cofre/releases/download/{tag}/Cofre.ipa'}],'metadata':{'bundle-identifier':'com.ignacio.cofre','bundle-version':tag[1:], 'kind':'software','title':'Cofre'}}]}
Path('manifest.plist').write_bytes(plistlib.dumps(plist))
PY
NOTES=".work/release-notes-$TAG.md"; printf 'Cofre %s\n' "$TAG" > "$NOTES"
echo "gh release create $TAG Cofre.ipa manifest.plist --notes-file $NOTES"
if (( PUBLISH )); then gh release create "$TAG" Cofre.ipa manifest.plist --notes-file "$NOTES"; fi
