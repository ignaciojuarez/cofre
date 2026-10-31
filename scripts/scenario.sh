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
# Stop only the app by PID: terminating by bundle ID also kills the VPN extension (com.ignacio.cofre.tunnel),
# and the next launch then finds a dead tunnel.
stop_app() {
  for pid in $(xcrun devicectl device info processes --device "$device" 2>/dev/null | awk '/Cofre\.app\/AngelAuraAmethyst[[:space:]]*$/ {print $1}'); do
    # A running JVM ignores SIGTERM.
    xcrun devicectl device process signal --device "$device" --pid "$pid" --signal SIGKILL >/dev/null 2>&1 || true
  done
  # Launching before the killed process is gone fails with "process identifier could not be determined".
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    xcrun devicectl device info processes --device "$device" 2>/dev/null | grep -qE 'Cofre\.app/AngelAuraAmethyst[[:space:]]*$' || break
    sleep 1
  done
}
launch_scenario() {
  xcrun devicectl device process launch --device "$device" "$bundle" -cofreScenario "$file" ${COFRE_LAUNCH_ARGS:-} >/dev/null \
    || { sleep 3; xcrun devicectl device process launch --device "$device" "$bundle" -cofreScenario "$file" ${COFRE_LAUNCH_ARGS:-} >/dev/null; }
}
stop_app
since=$(date -v-5S "+%Y-%m-%d %H:%M:%S")  # ignore the previous run's log until the app rotates it
launch_scenario
log="$out/latestlog.txt"; verdict="FAIL timeout"
restarted=0
for ((i=0; i<timeout; i++)); do
  xcrun devicectl device copy from --device "$device" --domain-type appDataContainer --domain-identifier "$bundle" --source Documents/latestlog.txt --destination "$log" >/dev/null 2>&1 || true
  first=$(grep -m1 -oE '^20[0-9]{2}-[0-9]{2}-[0-9]{2} [0-9:]{8}' "$log" 2>/dev/null || true)
  if [[ -s "$log" && ! "$first" < "$since" ]]; then
    clean=$(sed -E 's/(accessToken|uuid|xuid)([[:space:]]*[:=][[:space:]]*)[^,}]*/\1\2<redacted>/Ig' "$log")
    printf '%s\n' "$clean" > "$log"
    if grep -q 'launch state=inGame' "$log"; then verdict="PASS in-game"; break; fi
    if grep -q 'scenario .*result=restart' "$log"; then
      if ((restarted)); then verdict="FAIL scenario step"; break; fi
      restarted=1
      stop_app
      rm -f "$log"
      since=$(date -v-5S "+%Y-%m-%d %H:%M:%S")
      launch_scenario
      continue
    fi
    if grep -q 'scenario .*result=fail' "$log"; then verdict="FAIL scenario step"; break; fi
    if grep -qE 'game exit code|launch state=failed' "$log"; then verdict="FAIL game exit"; break; fi
  fi
  sleep 1
done
xcrun devicectl device copy from --device "$device" --domain-type appDataContainer --domain-identifier "$bundle" --source Documents/latestlog.old.txt --destination "$out/latestlog.old.txt" >/dev/null 2>&1 || true
echo "$verdict · logs: $out"
