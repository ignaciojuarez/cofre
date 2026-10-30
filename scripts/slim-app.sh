#!/usr/bin/env bash
# Run on the staged payload BEFORE signing. Keep external dSYMs for diagnostics.
set -euo pipefail
APP=${1:?usage: slim-app.sh /path/to/Cofre.app}
[[ -d "$APP" ]] || exit 1
before=$(du -sk "$APP" | awk '{print $1}')
while IFS= read -r -d '' binary; do
  if file -b "$binary" | grep -q 'Mach-O'; then
    xcrun strip -S "$binary"
  fi
done < <(find "$APP" -type f -print0)
after=$(du -sk "$APP" | awk '{print $1}')
echo "Payload: ${before} KiB -> ${after} KiB (saved $((before - after)) KiB)"
