#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.."; pwd); cd "$ROOT"
which=all; to=; dry=0
for a in "$@"; do case "$a" in all|air|stikjit|stikdebug) which=$a;; --to=*) to=${a#*=};; --dry-run) dry=1;; *) echo "unknown option: $a" >&2; exit 1;; esac; done
[[ -f UPSTREAM.lock ]] || { echo 'missing UPSTREAM.lock' >&2; exit 1; }
changed=0
for n in air stikjit stikdebug; do [[ "$which" == all || "$which" == "$n" ]] || continue
  sub="$ROOT/upstream/$n"; old=$(awk -F'\t' -v n="$n" '$1==n{print $5}' UPSTREAM.lock); url=$(awk -F'\t' -v n="$n" '$1==n{print $2}' UPSTREAM.lock); track=$(awk -F'\t' -v n="$n" '$1==n{print $3}' UPSTREAM.lock)
  git -C "$sub" fetch --tags "$url" || { echo "fetch failed: $n" >&2; exit 1; }
  ref=${to:-$( [[ "$track" == tags ]] && git -C "$sub" tag -l | grep -E '^v?[0-9]+(\.[0-9]+)+$' | sort -V | tail -1 || echo main )}; new=$(git -C "$sub" rev-parse "$ref^{commit}")
  [[ "$new" == "$old" ]] && { echo "= $n $old"; continue; }; changed=1; echo "→ $n ${old:0:9} → ${new:0:9} ($ref)"
  work="$ROOT/.work/$n"; rm -rf "$work" "$ROOT/.work/$n.failed"; mkdir -p "$ROOT/.work"; git -C "$sub" worktree add --detach "$work" "$new" || { echo "worktree failed" >&2; exit 2; }
  trap 'git -C "$sub" worktree remove --force "$work" >/dev/null 2>&1 || true' EXIT
  shopt -s nullglob; patches=("$ROOT/patches/$n"/*.patch); for patch in "${patches[@]}"; do git -C "$work" am --3way "$patch" || { git -C "$work" am --abort || true; echo "patch conflict: $patch" >&2; exit 2; }; done
  git -C "$work" diff --check; git -C "$work" status --short > "$ROOT/.work/$n.status"
  if (( ! dry )); then tmp=$(mktemp); awk -F'\t' -v OFS='\t' -v n="$n" -v r="$ref" -v s="$new" '$1==n{$4=r;$5=s;$8=strftime("%Y-%m-%d")}1' UPSTREAM.lock > "$tmp"; mv "$tmp" UPSTREAM.lock; fi
done
if (( changed && ! dry )); then printf '%s\n' "- Updated upstream worktrees and reapplied patches ($(date +%F))." | cat - CHANGELOG.md > CHANGELOG.tmp && mv CHANGELOG.tmp CHANGELOG.md; git add UPSTREAM.lock CHANGELOG.md; git commit -m '[CHORE] Update upstream pins'; fi
echo "update-upstream: success"
