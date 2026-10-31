#!/usr/bin/env bash
set -euo pipefail
scenario=${1:?usage: scripts/scenario.sh scenario.json [--device UDID] [--timeout seconds]}
device=COFRE_DEVICE_UDID; timeout=900
shift
while (($#)); do case "$1" in --device) device=$2; shift 2;; --timeout) timeout=$2; shift 2;; *) echo "unknown option: $1" >&2; exit 2;; esac; done
[[ -f "$scenario" ]] || { echo "missing scenario: $scenario" >&2; exit 2; }
name=$(basename "$scenario" .json); stamp=$(date +%Y%m%d-%H%M%S); out="/tmp/cofre-scenarios/$name-$stamp"; mkdir -p "$out"
bundle=com.ignacio.cofre; file=$(basename "$scenario")
xcrun devicectl device copy to --device "$device" --domain-type appDataContainer --domain-identifier "$bundle" --source "$scenario" --destination "Documents/$file" >/dev/null
xcrun devicectl device process terminate --device "$device" "$bundle" >/dev/null 2>&1 || true
since=$(date -v-5S "+%Y-%m-%d %H:%M:%S")  # ignore the previous run's log until the app rotates it
xcrun devicectl device process launch --device "$device" --terminate-existing "$bundle" -cofreScenario "$file" >/dev/null
log="$out/latestlog.txt"; verdict="FAIL timeout"
for ((i=0; i<timeout; i++)); do
  xcrun devicectl device copy from --device "$device" --domain-type appDataContainer --domain-identifier "$bundle" --source Documents/latestlog.txt --destination "$log" >/dev/null 2>&1 || true
  first=$(grep -m1 -oE '^20[0-9]{2}-[0-9]{2}-[0-9]{2} [0-9:]{8}' "$log" 2>/dev/null || true)
  if [[ -s "$log" && ! "$first" < "$since" ]]; then
    clean=$(sed -E 's/(accessToken|uuid|xuid)([[:space:]]*[:=][[:space:]]*)[^,}]*/\1\2<redacted>/Ig' "$log")
    printf '%s\n' "$clean" > "$log"
    if grep -q 'launch state=inGame' "$log"; then verdict="PASS in-game"; break; fi
    if grep -q 'scenario .*result=fail' "$log"; then verdict="FAIL scenario step"; break; fi
    if grep -qE 'game exit code|launch state=failed' "$log"; then verdict="FAIL game exit"; break; fi
  fi
  sleep 1
done
xcrun devicectl device copy from --device "$device" --domain-type appDataContainer --domain-identifier "$bundle" --source Documents/latestlog.old.txt --destination "$out/latestlog.old.txt" >/dev/null 2>&1 || true
echo "$verdict · logs: $out"
