#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.."; pwd); cd "$ROOT"
which=all; to=; dry=0
for a in "$@"; do case $a in all|air|stikjit|stikdebug) which=$a;; --to=*) to=${a#*=};; --dry-run) dry=1;; *) echo "unknown option: $a" >&2; exit 1;; esac; done
[[ -f UPSTREAM.lock ]] || { echo 'missing UPSTREAM.lock' >&2; exit 1; }
for n in air stikjit stikdebug; do [[ $which == all || $which == $n ]] || continue
  sub=upstream/$n; old=$(awk -F'\t' -v n=$n '$1==n{print $5}' UPSTREAM.lock); url=$(awk -F'\t' -v n=$n '$1==n{print $2}' UPSTREAM.lock); track=$(awk -F'\t' -v n=$n '$1==n{print $3}' UPSTREAM.lock)
  git -C "$sub" fetch --tags "$url" -q || { echo "fetch failed: $n" >&2; exit 1; }
  ref=${to:-$( [[ $track == tags ]] && git -C "$sub" tag -l | grep -E '^v?[0-9]+(\.[0-9]+)+$' | sort -V | tail -1 || echo main )}
  new=$(git -C "$sub" rev-parse "$ref^{commit}"); [[ $new == "$old" ]] && { echo "= $n $old"; continue; }
  if ! git -C "$sub" merge-base --is-ancestor "$old" "$new"; then
    echo "! $n is not a fast-forward (manual review)" >&2
    ((dry)) && continue
    exit 5
  fi
  echo "→ $n ${old:0:9} → ${new:0:9} ($ref)"
  ((dry)) && continue
  tmp=$(mktemp); awk -F'\t' -v OFS='\t' -v n=$n -v r=$ref -v s=$new '$1==n{$4=r;$5=s;$8=strftime("%Y-%m-%d")}1' UPSTREAM.lock > "$tmp"; mv "$tmp" UPSTREAM.lock
 done
if (( ! dry )); then git add UPSTREAM.lock; git commit -qm "[CHORE] Update upstream pins"; fi
