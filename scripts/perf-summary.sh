#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "usage: $0 <latestlog>" >&2
  exit 2
fi

awk '
/\[Cofre\] perf / {
  fps = min = footprint = ""
  for (i = 1; i <= NF; i++) {
    if ($i ~ /^fps=/) { split($i, a, "="); fps = a[2] }
    if ($i ~ /^min=/) { split($i, a, "="); min = a[2] }
    if ($i ~ /^footprintMB=/) { split($i, a, "="); footprint = a[2] }
  }
  if (fps != "") { n++; values[n] = fps; sum += fps }
  if (min != "" && (low == "" || min < low)) low = min
  if (footprint != "" && footprint > peak) peak = footprint
}
END {
  if (n == 0) { print "No Cofre perf lines found" > "/dev/stderr"; exit 1 }
  for (i = 1; i <= n; i++) {
    for (j = i + 1; j <= n; j++) {
      if (values[j] < values[i]) { tmp = values[i]; values[i] = values[j]; values[j] = tmp }
    }
  }
  if (n % 2) median = values[(n + 1) / 2]
  else median = (values[n / 2] + values[n / 2 + 1]) / 2
  printf "samples=%d avg fps=%.1f median fps=%.1f 1%%-low proxy fps=%.1f peak footprintMB=%.0f\n", n, sum / n, median, low, peak
}
' "$1"
