#!/bin/sh
set -eu
ROOT=$(cd -- "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build.sh"
(cd "$ROOT/build" && ditto -c -k --keepParent Llave.app Llave.app.zip)
shasum -a 256 "$ROOT/build/Llave.app.zip" > "$ROOT/SHA256SUMS"
HASH=$(awk 'NR==1{print $1}' "$ROOT/SHA256SUMS")
python3 - "$ROOT/pair.sh" "$HASH" <<'PY'
from pathlib import Path
import re,sys
p=Path(sys.argv[1]); s=p.read_text(); out,n=re.subn(r'RELEASE_SHA256="[0-9a-f]+"', 'RELEASE_SHA256="'+sys.argv[2]+'"', s)
if n != 1: raise SystemExit(f'expected exactly one RELEASE_SHA256 replacement, got {n}')
p.write_text(out)
PY
EXPECTED=$(shasum -a 256 "$ROOT/build/Llave.app.zip" | awk '{print $1}')
[ "$EXPECTED" = "$HASH" ] || { echo 'checksum self-verification failed' >&2; exit 4; }
echo "Built signed zip: $ROOT/build/Llave.app.zip"; cat "$ROOT/SHA256SUMS"
