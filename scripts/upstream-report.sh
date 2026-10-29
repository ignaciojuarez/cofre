#!/usr/bin/env bash
set -u -o pipefail
ROOT=$(cd "$(dirname "$0")/.." || exit; pwd)
cd "$ROOT" || exit
REPORT="$ROOT/artifacts/upstream-report.md"
JSON=0
[[ ${1:-} == --json ]] && JSON=1
mkdir -p "$ROOT/artifacts" "$ROOT/.work/watch"

age_days() {
  python3 - "$1" <<'PY'
import datetime, sys
try:
    d = datetime.date.fromisoformat(sys.argv[1])
    print((datetime.date.today() - d).days)
except (ValueError, IndexError):
    print(9999)
PY
}

watch_matches() {
  local name=$1 old=$2 new=$3 file pattern out=''
  [[ "$old" == "$new" ]] && { printf '%s' ''; return; }
  while IFS= read -r file; do
    while IFS= read -r pattern; do
      [[ -z "$pattern" || "$pattern" == \#* ]] && continue
      # shellcheck disable=SC2053
      if [[ "$file" == $pattern ]]; then out+="${file}, "; break; fi
    done < "$ROOT/scripts/watch/$name.txt"
  done < <(git -C "$ROOT/upstream/$name" diff --name-only "$old..$new")
  printf '%s' "${out%, }"
}

license_changes() {
  local name=$1 old=$2 new=$3
  [[ "$old" == "$new" ]] && return 1
  git -C "$ROOT/upstream/$name" diff --name-only "$old..$new" | grep -Eiq '(^|/)(LICENSE|NOTICE)(\.|$)'
}

new_tags() {
  local name=$1 old=$2 new=$3 tag out=''
  [[ "$old" == "$new" ]] && { printf '%s' ''; return; }
  while IFS= read -r tag; do
    [[ -z "$tag" ]] && continue
    if ! git -C "$ROOT/upstream/$name" merge-base --is-ancestor "$tag" "$old" 2>/dev/null; then out+="$tag, "; fi
  done < <(git -C "$ROOT/upstream/$name" tag --merged "$new")
  printf '%s' "${out%, }"
}

printf '# Weekly upstream report (%s)\n\n' "$(date -u +%Y-%m-%d)" > "$REPORT"
printf '| Upstream | Commits | Date range | Watched paths | License/NOTICE | Tags/releases | Dry-run | Verdict |\n|---|---:|---|---|---|---|---|---|\n' >> "$REPORT"
json_rows=()
NOTES=$(mktemp)
for name in air stikjit stikdebug; do
  sub="$ROOT/upstream/$name"
  old=$(awk -F '\t' -v n="$name" '$1 == n {print $5}' UPSTREAM.lock)
  url=$(awk -F '\t' -v n="$name" '$1 == n {print $2}' UPSTREAM.lock)
  track=$(awk -F '\t' -v n="$name" '$1 == n {print $3}' UPSTREAM.lock)
  fetch_ok=1
  if [[ "$track" == tags ]]; then
    git -C "$sub" fetch --tags "$url" >/dev/null 2>&1 || fetch_ok=0
    ref=$(git -C "$sub" tag -l | grep -E '^v?[0-9]+(\.[0-9]+)+$' | sort -V | tail -1)
  else
    git -C "$sub" fetch --no-tags "$url" '+refs/heads/main:refs/remotes/report/main' >/dev/null 2>&1 || fetch_ok=0
    ref=refs/remotes/report/main
  fi
  new=$(git -C "$sub" rev-parse "$ref^{commit}" 2>/dev/null || printf '%s' "$old")
  [[ "$name" == air ]] && air_tracked=$new
  compare_old=$old; compare_new=$new
  if ! git -C "$sub" merge-base --is-ancestor "$old" "$new" 2>/dev/null; then compare_new=$old; fi
  count=$(git -C "$sub" rev-list --count "$compare_old..$compare_new" 2>/dev/null || printf '0')
  first=$(git -C "$sub" log -1 --format=%cs "$compare_old" 2>/dev/null || printf '?')
  last=$(git -C "$sub" log -1 --format=%cs "$compare_new" 2>/dev/null || printf '?')
  watched=$(watch_matches "$name" "$compare_old" "$compare_new")
  license=no; license_changes "$name" "$compare_old" "$compare_new" && license=yes
  tags=$(new_tags "$name" "$compare_old" "$compare_new")
  dry=patches\ apply\ cleanly
  if ! scripts/update-upstream.sh "$name" --dry-run >/dev/null 2>&1; then
    dry=conflict
  fi
  human=0; worth=0
  [[ "$license" == yes || "$dry" == conflict ]] && human=1
  [[ -n "$watched" || -n "$tags" ]] && worth=1
  if [[ "$count" -gt 0 && $(age_days "$first") -gt 30 ]]; then worth=1; fi
  if [[ "$watched" =~ (UniversalJIT|JIT|entitlement|Authenticator|authenticator|sign-in|sign_in) ]]; then human=1; fi
  verdict=no\ action; (( worth )) && verdict=worth\ pulling; (( human )) && verdict=needs\ a\ human
  subjects=$(git -C "$sub" log --format='%s' "$compare_old..$compare_new" 2>/dev/null | head -15 | paste -sd '<' - | sed 's/</<br>/g')
  [[ -z "$subjects" ]] && subjects=none
  printf '| %s | %s | %s → %s | %s | %s | %s | %s | %s |\n' "$name" "$count" "$first" "$last" "${watched:-none}" "$license" "${tags:-none}" "$dry" "$verdict" >> "$REPORT"
  printf -- '- **%s:** %s\n' "$name" "${subjects:-no new commits}" >> "$NOTES"
  json_rows+=("{\"name\":\"$name\",\"commits\":$count,\"verdict\":\"$verdict\"}")
  [[ $fetch_ok == 0 ]] && printf -- '- **%s fetch:** failed\n' "$name" >> "$NOTES"
done

am="$ROOT/.work/watch/amethyst.git"
if [[ ! -d "$am" ]]; then git init --bare "$am" >/dev/null 2>&1 || true; fi
am_ok=1
git --git-dir="$am" fetch --no-tags https://github.com/AngelAuraMC/Amethyst-iOS '+refs/heads/*:refs/remotes/origin/*' >/dev/null 2>&1 || am_ok=0
am_head=$(git --git-dir="$am" rev-parse refs/remotes/origin/main 2>/dev/null || git --git-dir="$am" rev-parse refs/remotes/origin/master 2>/dev/null || true)
am_count=0; am_watched=none
if [[ -n "$am_head" && -n "${air_tracked:-}" ]] && git --git-dir="$am" merge-base --is-ancestor "$air_tracked" "$am_head" 2>/dev/null; then
  am_count=$(git --git-dir="$am" rev-list --count "$air_tracked..$am_head")
  am_watched=$(watch_matches amethyst "$air_tracked" "$am_head")
fi
am_note=''; [[ $am_ok == 0 ]] && am_note=' Fetch failed.'
printf '\n' >> "$REPORT"
cat "$NOTES" >> "$REPORT"
rm -f "$NOTES"
printf -- '- **Amethyst-iOS watch:** %s commits beyond Air; watched paths: %s.%s\n' "$am_count" "$am_watched" "$am_note" >> "$REPORT"
air_last=$(git -C "$ROOT/upstream/air" log -1 --format=%cs "${air_tracked:-HEAD}" 2>/dev/null || printf '?')
if [[ "$air_last" != '?' && $(age_days "$air_last") -ge 90 ]]; then
  printf -- '- **Activity:** Air quiet ≥ 90 days → consider re-basing on Amethyst.\n' >> "$REPORT"
fi
printf '\n' >> "$REPORT"
cat "$REPORT"
if (( JSON )); then printf '[%s]\n' "$(IFS=,; echo "${json_rows[*]}")"; fi
exit 0
