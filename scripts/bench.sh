#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
dry_run=0
engine=''
only=''
scenario_args=()
while (($#)); do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --engine) engine=${2:?--engine needs a JSON object}; shift ;;
    --only) only=${2:?--only needs a scenario name}; shift ;;
    *) scenario_args+=("$1") ;;
  esac
  shift
done
if [[ " ${scenario_args[*]:-} " == *' --help '* ]]; then
  echo 'usage: scripts/bench.sh [--dry-run] [--only NAME] [--engine JSON] [--device UDID] [--timeout seconds]'
  echo 'Device: COFRE_DEVICE_UDID; timing: COFRE_WORLD_SECONDS (default 670). No relay flag in scenario.sh.'
  echo "--engine merges EngineOptions into every scenario, e.g. '{\"detachJIT\": true}' (A/B: run with and without,"
  echo 'then scripts/perf-summary.sh A.txt B.txt).'
  exit 0
fi
scenarios=(
  bench-vanilla-26.3-metal
  bench-vanilla-26.3-vulkan
  bench-fabric-26.2-metal-sodium-30
  bench-neoforge-26.2-metal-100mods
)
out="$root/artifacts/bench/$(date -u +%Y%m%dT%H%M%SZ)"
export COFRE_WORLD_SECONDS=${COFRE_WORLD_SECONDS:-670}
export COFRE_LAUNCH_ARGS="${COFRE_LAUNCH_ARGS:-} -cofrePerfLog 1"
[[ "$COFRE_WORLD_SECONDS" =~ ^[0-9]+$ ]] || { echo 'COFRE_WORLD_SECONDS must be an integer' >&2; exit 2; }
echo "Phase 0: $out (60s warmup + 600s steady; collect ${COFRE_WORLD_SECONDS}s after world join)"
[[ -z "$only" ]] || scenarios=("$only")
[[ -z "$engine" ]] || echo "Engine experiment: $engine"
if ((!dry_run)); then
  mkdir -p "$root/artifacts/bench"
  mkdir "$out"  # Never overwrite a previous run's evidence.
fi
failed=0
logs=()
for name in "${scenarios[@]}"; do
  scenario="$root/scripts/scenarios/$name.json"
  [[ -f "$scenario" ]] || { echo "unknown scenario: $name" >&2; exit 2; }
  if [[ -n "$engine" ]]; then
    # Keep the merged scenario next to its log, so the run says which experiment it was.
    merged="${TMPDIR:-/tmp}/$name.engine.json"
    ((dry_run)) || merged="$out/$name.json"
    python3 -I -c 'import json, sys
scenario = json.load(open(sys.argv[1]))
scenario["engine"] = {**scenario.get("engine", {}), **json.loads(sys.argv[2])}
json.dump(scenario, open(sys.argv[3], "w"), indent=2)' "$scenario" "$engine" "$merged" || exit 2
    scenario=$merged
  fi
  command=("$root/scripts/scenario.sh" "$scenario" --timeout 3600)
  if ((${#scenario_args[@]})); then command+=("${scenario_args[@]}"); fi
  if ((dry_run)); then
    printf 'COFRE_WORLD_SECONDS=%q COFRE_LAUNCH_ARGS=%q ' "$COFRE_WORLD_SECONDS" "$COFRE_LAUNCH_ARGS"
    printf '%q ' "${command[@]}"
    printf '\nCollect latestlog from the runner-reported logs directory -> %s/%s.txt\n' "$out" "$name"
    printf '%q --skip-seconds 60 --window-seconds 600 %q\n' "$root/scripts/perf-summary.sh" "$out/$name.txt"
    continue
  fi
  if ! "${command[@]}" 2>&1 | tee "$out/$name.runner.txt"; then failed=1; fi
  source_dir=$(sed -n 's/^.* · logs: //p' "$out/$name.runner.txt" | tail -n 1)
  if [[ -n "$source_dir" && -s "$source_dir/latestlog.txt" ]]; then
    cp "$source_dir/latestlog.txt" "$out/$name.txt"
    logs+=("$out/$name.txt")
    if grep -qE 'game exit code|launch state=failed' "$out/$name.txt"; then
      echo "FAIL $name: game exited during collection" >&2
      failed=1
    fi
    backend=$(sed -nE 's/.*Using graphics backend (Metal|Vulkan|OpenGL).*/\1/p' "$out/$name.txt" | tail -n 1)
    expected=Metal
    [[ "$name" != *-vulkan ]] || expected=Vulkan
    if [[ -n "$backend" && "$backend" != "$expected" ]]; then
      echo "FAIL $name: expected $expected, logged $backend" >&2
      failed=1
    fi
  else
    echo "FAIL $name: no latestlog collected" >&2
    failed=1
  fi
  # scenario.sh also prints FAIL verdicts with exit status 0.
  if ! grep -q '^PASS in-world · logs: ' "$out/$name.runner.txt"; then failed=1; fi
done
if ((dry_run)); then
  if ((${#scenarios[@]} > 1)); then
    printf 'Compare vanilla Metal/Vulkan: %q %q %q\n' "$root/scripts/perf-summary.sh" \
      "$out/${scenarios[0]}.txt" "$out/${scenarios[1]}.txt"
  fi
  exit 0
fi
if ((${#logs[@]})); then
  for log in "${logs[@]}"; do
    if ! "$root/scripts/perf-summary.sh" "$log" 2>&1 | tee -a "$out/summary.txt"; then failed=1; fi
  done
fi
if ((${#scenarios[@]} > 1)) && [[ -s "$out/${scenarios[0]}.txt" && -s "$out/${scenarios[1]}.txt" ]]; then
  if ! "$root/scripts/perf-summary.sh" "$out/${scenarios[0]}.txt" "$out/${scenarios[1]}.txt" \
    2>&1 | tee "$out/vanilla-ab.txt"; then failed=1; fi
fi
echo "Phase 0 logs and summaries: $out"
exit "$failed"
