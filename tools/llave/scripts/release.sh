#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build.sh"
(cd "$ROOT/build" && ditto -c -k --keepParent Llave.app Llave.app.zip)
shasum -a 256 "$ROOT/build/Llave.app.zip" > "$ROOT/SHA256SUMS"
HASH=$(awk '{print $1}' "$ROOT/SHA256SUMS")
python3 - "$ROOT/pair.sh" "$HASH" <<'PY'
from pathlib import Path
import re,sys
p=Path(sys.argv[1]); s=p.read_text(); p.write_text(re.sub(r'RELEASE_SHA256="[0-9a-f]+"', 'RELEASE_SHA256="'+sys.argv[2]+'"', s))
PY
echo "Built signed zip: $ROOT/build/Llave.app.zip"; cat "$ROOT/SHA256SUMS"
