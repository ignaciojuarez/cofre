#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.."; pwd)
cd "$ROOT"
which=all; to=; dry=0
for arg in "$@"; do
  case "$arg" in
    all|air|stikjit|stikdebug) which=$arg ;;
    --to=*) to=${arg#*=} ;;
    --dry-run) dry=1 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done
[[ -f UPSTREAM.lock ]] || { echo "missing UPSTREAM.lock" >&2; exit 1; }
mkdir -p .work
changed=0
for name in air stikjit stikdebug; do
  [[ "$which" == all || "$which" == "$name" ]] || continue
  sub="$ROOT/upstream/$name"
  old=$(awk -F '\t' -v n="$name" '$1 == n { print $5 }' UPSTREAM.lock)
  url=$(awk -F '\t' -v n="$name" '$1 == n { print $2 }' UPSTREAM.lock)
  track=$(awk -F '\t' -v n="$name" '$1 == n { print $3 }' UPSTREAM.lock)
  if [[ -n "$to" ]]; then
    git -C "$sub" fetch --tags "$url"
    ref=$to
    target=$to
  elif [[ "$track" == tags ]]; then
    git -C "$sub" fetch --tags "$url"
    ref=$(git -C "$sub" tag -l | grep -E '^v?[0-9]+(\.[0-9]+)+$' | sort -V | tail -1)
    target=$ref
  else
    # Fetch the remote branch itself; the submodule's local "main" never moves.
    git -C "$sub" fetch --tags "$url" main
    ref=main
    target=FETCH_HEAD
  fi
  new=$(git -C "$sub" rev-parse "$target^{commit}")
  if [[ "$new" == "$old" ]]; then echo "= $name $old"; continue; fi
  # Never move a pin backwards (e.g. the newest tag is older than the commit we pinned).
  if git -C "$sub" merge-base --is-ancestor "$new" "$old"; then
    echo "= $name ${old:0:9} is already newer than $ref"
    continue
  fi
  changed=1; echo "→ $name ${old:0:9} → ${new:0:9} ($ref)"
  # Never use .work/<name>: that is the build tree scripts/run.sh compiles in.
  work="$ROOT/.work/update-$name"
  git -C "$sub" worktree prune
  git -C "$sub" worktree remove --force "$work" >/dev/null 2>&1 || true
  rm -rf "$work" "$work.status" "$work.conflict"
  GIT_LFS_SKIP_SMUDGE=1 git -C "$sub" worktree add --detach "$work" "$new"
  shopt -s nullglob
  for patch in "$ROOT/patches/$name"/*.patch; do
    if ! git -C "$work" am --3way "$patch"; then
      git -C "$work" am --abort || true
      git -C "$work" status --short > "$work.conflict"
      git -C "$sub" worktree remove --force "$work" >/dev/null 2>&1 || true
      echo "patch conflict: $patch" >&2; exit 2
    fi
  done
  git -C "$work" diff --check
  git -C "$work" status --short > "$work.status"
  git -C "$sub" worktree remove --force "$work" >/dev/null 2>&1 || true
  if (( ! dry )); then
    tmp=$(mktemp)
    awk -F '\t' -v OFS='\t' -v n="$name" -v r="$ref" -v s="$new" -v d="$(date -u +%Y-%m-%dT%H:%M:%SZ)" '$1 == n { $4 = r; $5 = s; $8 = d } 1' UPSTREAM.lock > "$tmp"
    mv "$tmp" UPSTREAM.lock
  fi
done
if (( changed && ! dry )); then
  { printf '%s\n' "- Updated upstream worktrees and reapplied patches ($(date -u +%Y-%m-%d))."; cat CHANGELOG.md; } > CHANGELOG.tmp
  mv CHANGELOG.tmp CHANGELOG.md
  git add UPSTREAM.lock CHANGELOG.md
  git commit -m '[CHORE] Update upstream pins'
fi
echo "update-upstream: success"
