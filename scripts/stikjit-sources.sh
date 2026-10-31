#!/usr/bin/env bash
# Copy StikJIT's sources to .work/stikjit and apply patches/stikjit in order; the PacketTunnel target builds the copy.
# Redone only when the upstream commit or the patch set changes.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.."; pwd)
OUT="$ROOT/.work/stikjit"
patches=("$ROOT"/patches/stikjit/*.patch)
[[ -e "${patches[0]}" ]] || patches=()
stamp="$(git -C "$ROOT/upstream/stikjit" rev-parse HEAD) $(cat "${patches[@]}" /dev/null | shasum | cut -d' ' -f1)"
[[ -d "$OUT/Sources" && "$(cat "$OUT/.cofre-patches" 2>/dev/null)" == "$stamp" ]] && exit 0
rm -rf "$OUT" && mkdir -p "$OUT"
cp -R "$ROOT/upstream/stikjit/Sources" "$OUT/Sources"
for patch in "${patches[@]}"; do
  patch -s -p1 -d "$OUT" --forward < "$patch" || { echo "StikJIT patch does not apply: $(basename "$patch")" >&2; exit 1; }
done
echo "$stamp" > "$OUT/.cofre-patches"
