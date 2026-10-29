#!/bin/sh
set -eu
RELEASE_URL="https://github.com/ignaciojuarez/cofre/releases/latest/download/Llave.app.zip"
RELEASE_SHA256="3c0fe0a29b283056fcd08361c57ca410cc57cbcc88614edec020bcdd7c717383"
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
[ "$(uname -s)" = Darwin ] || { echo "Llave requires macOS." >&2; exit 1; }
case "$(uname -m)" in arm64|x86_64) ;; *) echo "Llave requires an arm64 or x86_64 Mac." >&2; exit 1;; esac
TMP=$(mktemp -d "${TMPDIR:-/tmp}/llave.XXXXXX"); trap 'rm -rf "$TMP"' EXIT INT TERM
if [ "$DRY" -eq 1 ]; then
  APP="${LLAVE_APP_PATH:-$(dirname "$0")/build/Llave.app}"
  [ -d "$APP" ] || { echo "Dry-run app not found; run scripts/build.sh first." >&2; exit 1; }
  echo "Launching Llave simulation…"; LLAVE_SIMULATE=1 open -W "$APP"; echo "Dry run complete."; exit 0
fi
ZIP="$TMP/Llave.app.zip"
curl -fsSL "$RELEASE_URL" -o "$ZIP" || { echo "Could not download Llave; check your network." >&2; exit 1; }
ACTUAL=$(shasum -a 256 "$ZIP" | awk '{print $1}')
[ "$ACTUAL" = "$RELEASE_SHA256" ] || { echo "Llave download checksum mismatch." >&2; exit 1; }
unzip -q "$ZIP" -d "$TMP" || { echo "Could not unpack Llave." >&2; exit 1; }
APP="$TMP/Llave.app"
[ -d "$APP" ] || { echo "Downloaded Llave.app is missing." >&2; exit 1; }
echo "Plug in your iPhone; the window will guide you."
open -W "$APP"
echo "Llave closed."
