#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
scripts/perf-summary.sh --window-seconds 20 tests/perf/growing-full.txt >"$tmp/growing" 2>"$tmp/warnings"
for row in \
  'renderer | metallum' 'graphics backend | Metal' 'JIT mode | attached dyld_bypass=on' \
  'engine flags | -Xmx4096M' 'heap | heap=4096MB requested=4096MB available=6144MB' \
  'steady start s | 120 |' 'steady observed s | 20 |' 'steady samples | 4 |' \
  'FPS avg | 50 |' 'FPS 1%-low proxy (min) | 30 |' 'frame p95 proxy ms | 30 |' \
  'footprint start MB | 1000 |' 'footprint end MB | 1280 |' 'footprint max MB | 1280 |' \
  'footprint growth MB/s | 2 |' 'thermal nominal s | 60 |' 'thermal fair s | 60 |' \
  'thermal serious s | 10 |' 'thermal critical s | 10 |' \
  'thermal timeline s | nominal 5-60; fair 60-120; serious 120-130; critical 130-140; nominal 140-145' \
  'GC pause count | 3 |' 'GC pause total ms | 18.623 |' 'GC pause max ms | 10 |' \
  'code cache peak MB | 48 |' 'dylib outside bundle count | 2 |'; do
  grep -Fq "$row" "$tmp/growing" || { echo "FAIL missing: $row"; exit 1; }
done
grep -Fq '!!! WARNING:' "$tmp/warnings"
grep -Fq 'CodeCache is full' "$tmp/growing"
scripts/perf-summary.sh --window-seconds 20 tests/perf/stable-detached.txt >"$tmp/stable"
for row in 'JIT mode | detached dyld_bypass=off' 'footprint growth MB/s | 0 |' \
  'code cache peak MB | 32 |' 'GC pause count | N/A |' 'dylib outside bundle count | 0 |'; do
  grep -Fq "$row" "$tmp/stable"
done
scripts/perf-summary.sh --window-seconds 20 tests/perf/growing-full.txt tests/perf/stable-detached.txt \
  >"$tmp/ab" 2>"$tmp/warnings"
grep -Fq '| Delta B - A |' "$tmp/ab"
grep -Fq '| FPS avg | 50 | 80 | +30 |' "$tmp/ab"
grep -Fq '| frame p95 proxy ms | 30 | 25 | -5 |' "$tmp/ab"
grep -Fq '| footprint growth MB/s | 2 | 0 | -2 |' "$tmp/ab"
scripts/perf-summary.sh --skip-seconds 0 --window-seconds 0 tests/perf/legacy.txt >"$tmp/legacy"
for row in 'graphics backend | OpenGL' 'FPS avg | 40 |' 'JIT mode | N/A |' \
  'frame p95 proxy ms | N/A |' 'thermal fair s | 10 |' 'code cache peak MB | N/A |'; do
  grep -Fq "$row" "$tmp/legacy"
done
scripts/perf-summary.sh --skip-seconds 10 --window-seconds 5 tests/perf/legacy.txt >"$tmp/skip"
grep -Fq '| FPS avg | 60 |' "$tmp/skip"
if scripts/perf-summary.sh tests/perf/no-perf.txt >"$tmp/empty" 2>"$tmp/warnings"; then
  echo 'FAIL empty log accepted'; exit 1
fi
grep -Fq 'No Cofre perf lines found' "$tmp/warnings"
if scripts/perf-summary.sh tests/perf/stable-detached.txt >"$tmp/short" 2>"$tmp/warnings"; then
  echo 'FAIL incomplete window accepted'; exit 1
fi
grep -Fq 'incomplete steady window' "$tmp/warnings"
if scripts/perf-summary.sh --skip-seconds -1 tests/perf/legacy.txt >/dev/null 2>&1; then
  echo 'FAIL negative warmup accepted'; exit 1
fi
scripts/bench.sh --dry-run --device TEST-DEVICE --timeout 1800 >"$tmp/plan"
[[ $(grep -c '^Collect latestlog' "$tmp/plan") == 4 ]]
grep -Fq -- '--timeout 3600 --device TEST-DEVICE --timeout 1800' "$tmp/plan"

# Exercise collection and scenario.sh's zero-exit FAIL verdict without a device.
for mode in pass fail missing backend exit; do
  fake="$tmp/$mode"
  mkdir -p "$fake/scripts" "$fake/logs"
  cp scripts/bench.sh scripts/perf-summary.sh "$fake/scripts/"
  mkdir -p "$fake/scripts/scenarios" && cp scripts/scenarios/bench-*.json "$fake/scripts/scenarios/"
  python3 -I - "$fake/logs/latestlog.txt" <<'PY'
from pathlib import Path
import sys
lines = ["[Cofre] scenario name=fixture step=world result=ok"]
for tick in range(5, 670, 5):
    lines.append(f"[Cofre] perf t={tick}s fps=60 min=50 frameMs.p95=20 renderer=metallum footprintMB=1000 thermal=nominal")
Path(sys.argv[1]).write_text("\n".join(lines) + "\n")
PY
  if [[ "$mode" == backend ]]; then echo 'Using graphics backend OpenGL' >>"$fake/logs/latestlog.txt"; fi
  if [[ "$mode" == exit ]]; then echo '[Cofre] game exit code=1' >>"$fake/logs/latestlog.txt"; fi
  cat >"$fake/scripts/scenario.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
case "$root" in
  */missing) echo 'FAIL no log';;
  */fail) echo "FAIL scenario step · logs: $root/logs";;
  *) echo "PASS in-world · logs: $root/logs";;
esac
SH
  chmod +x "$fake/scripts/scenario.sh"
  if "$fake/scripts/bench.sh" --device TEST-DEVICE >"$tmp/$mode.result" 2>&1; then
    [[ "$mode" == pass ]] || { echo "FAIL runner accepted $mode"; exit 1; }
  else
    [[ "$mode" != pass ]] || { cat "$tmp/$mode.result"; exit 1; }
  fi
  if [[ "$mode" != missing ]]; then
    [[ $(find "$fake/artifacts" -name 'bench-*.txt' ! -name '*.runner.txt' | wc -l | tr -d ' ') == 4 ]]
    grep -Fq '| FPS avg | 60 | 60 | +0 |' "$fake"/artifacts/bench/*/vanilla-ab.txt
  fi
done
echo 'PASS perf fixtures: windows, markers, duplicate ticks, growth, thermals, GC, code cache, A/B, legacy, errors.'
echo 'PASS benchmark runner: dry-run, collection, A/B, failed verdicts, missing logs, backend mismatch and game exit (Mac only).'
