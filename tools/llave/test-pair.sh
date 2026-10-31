#!/bin/sh
set -eu
ROOT=$(cd -- "$(dirname "$0")" && pwd)

if [ -n "${LLAVE_APP_PATH:-}" ] || [ -d "$ROOT/build/Llave.app" ]; then
    cd "$ROOT"
    ./pair.sh --dry-run
    exit 0
fi

# A clean checkout has no signed GUI app yet. Exercise the same simulated
# pairing core directly, then require that it produced a pairing file.
TMP=$(mktemp -d "${TMPDIR:-/tmp}/llave-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM
COFRE_PAIRING_DIR="$TMP" cargo run --quiet --manifest-path "$ROOT/core/Cargo.toml" -- \
    --simulate pair --out pairing.plist >/dev/null
[ -s "$TMP/pairing.plist" ]
