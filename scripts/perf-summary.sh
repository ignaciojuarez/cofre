#!/usr/bin/env bash
set -euo pipefail

# Python's standard library keeps optional markers and A/B tables in one file.
exec python3 -I - "$@" <<'PY'
import argparse
from collections import defaultdict
import math
from pathlib import Path
import re
import statistics
import sys


def seconds(value):
    number = float(value)
    if not math.isfinite(number) or number < 0:
        raise argparse.ArgumentTypeError("seconds must be finite and nonnegative")
    return number


parser = argparse.ArgumentParser(description="Summarize one run, or compare A and B (delta = B - A).")
parser.add_argument("--skip-seconds", type=seconds, default=60,
                    help="warmup after first post-join perf sample, or t=0 without a world (default: 60)")
parser.add_argument("--window-seconds", type=seconds, default=600,
                    help="steady window length; 0 means all remaining samples (default: 600)")
parser.add_argument("logs", nargs="+", type=Path)
args = parser.parse_args()
if len(args.logs) > 2:
    parser.error("supply one log, or two logs for A/B")

NUMBER = r"[0-9]+(?:\.[0-9]+)?"


def summarize(path):
    rows = {}
    samples = {}
    joined = False
    world_start = None
    gc_present = False
    pauses = []
    gc_seen = set()
    cache = defaultdict(float)
    outside = 0
    full = False
    with path.open(encoding="utf-8", errors="replace") as source:
        for line in source:
            if re.search(r"scenario .*step=world result=ok|\]: \S+ joined the game", line):
                joined = True
            if "[Cofre] perf " in line:
                fields = dict(re.findall(r"([\w.]+)=([^\s]+)", line))
                try:
                    tick = float(fields["t"].removesuffix("s"))
                    sample = {"fps": float(fields["fps"])}
                    sample.update({key: float(fields[key]) for key in
                                   ("min", "frameMs.p95", "footprintMB") if key in fields})
                    if not all(math.isfinite(x) and x >= 0 for x in [tick, *sample.values()]):
                        continue
                except (KeyError, ValueError):
                    continue
                sample.update(t=tick, thermal=fields.get("thermal", "unknown"))
                samples[tick] = sample  # NSLog and the direct append can repeat a tick.
                if "renderer" in fields:
                    rows["renderer"] = fields["renderer"]
                if joined and world_start is None:
                    world_start = tick
            for marker, key in (("[Cofre] engine flags=", "engine flags"),
                                ("[Cofre] JIT mode=", "JIT mode"),
                                ("[Cofre] memory ", "heap")):
                if marker in line:
                    rows[key] = line.split(marker, 1)[1].strip()
            backend = re.search(r"Using graphics backend (Metal|Vulkan|OpenGL)\b", line)
            if backend:
                rows["graphics backend"] = backend[1]
            outside += "[Cofre] dylib outside bundle path=" in line
            full |= "CodeCache is full" in line
            if re.search(r"\[gc(?:,[^]]*)?\]", line):
                gc_present = True
                pause = re.search(r"GC\(\d+\) Pause .*? (" + NUMBER + r")ms\s*$", line)
                if pause and line not in gc_seen:
                    gc_seen.add(line)
                    pauses.append(float(pause[1]))
            heap = re.search(r"(CodeCache|CodeHeap\s*['\"][^'\"]+['\"]):", line)
            if heap:
                usage = re.search(r"\bmax_used=(" + NUMBER + r")([KMG]?)B?", line, re.I)
                if not usage:
                    usage = re.search(r"\bused=(" + NUMBER + r")([KMG]?)B?", line, re.I)
                if usage:
                    mb = float(usage[1]) * {"": 1 / 1048576, "K": 1 / 1024, "M": 1, "G": 1024}[usage[2].upper()]
                    cache[heap[1]] = max(cache[heap[1]], mb)

    ordered = sorted(samples.values(), key=lambda sample: sample["t"])
    start = (world_start or 0) + args.skip_seconds
    end = start + args.window_seconds if args.window_seconds else math.inf
    # Each perf row describes the preceding five seconds: exclude the warmup
    # boundary and include the row ending at the window boundary.
    steady = [s for s in ordered if start < s["t"] <= end]
    rows["window origin"] = "first post-world perf sample" if world_start is not None else "perf t=0 (no world marker)"
    rows["steady start s"] = start
    rows["steady observed s"] = sum(min(5, s["t"] - start) for s in steady)
    rows["steady samples"] = len(steady)
    for field, key, reducer in (("fps", "FPS avg", statistics.mean),
                                ("min", "FPS 1%-low proxy (min)", min),
                                ("frameMs.p95", "frame p95 proxy ms", lambda xs: sorted(xs)[math.ceil(.95 * len(xs)) - 1])):
        values = [s[field] for s in steady if field in s]
        rows[key] = reducer(values) if values else None
    footprints = [s for s in ordered if "footprintMB" in s]
    if footprints:
        first, last = footprints[0], footprints[-1]
        rows["footprint start MB"] = first["footprintMB"]
        rows["footprint end MB"] = last["footprintMB"]
        rows["footprint max MB"] = max(s["footprintMB"] for s in footprints)
        elapsed = last["t"] - first["t"]
        rows["footprint growth MB/s"] = (last["footprintMB"] - first["footprintMB"]) / elapsed if elapsed else None

    thermal = defaultdict(float)
    timeline = []
    for sample, following in zip(ordered, ordered[1:]):
        state = sample["thermal"]
        thermal[state] += following["t"] - sample["t"]
        if timeline and timeline[-1][0] == state:
            timeline[-1][2] = following["t"]
        else:
            timeline.append([state, sample["t"], following["t"]])
    rows["thermal timeline s"] = "; ".join(f"{state} {a:g}-{b:g}" for state, a, b in timeline) or None
    for state in ("nominal", "fair", "serious", "critical", "unknown"):
        rows[f"thermal {state} s"] = thermal[state] if ordered else None
    rows["GC pause count"] = len(pauses) if gc_present else None
    rows["GC pause total ms"] = sum(pauses) if gc_present else None
    rows["GC pause max ms"] = max(pauses, default=0) if gc_present else None
    rows["code cache peak MB"] = cache.get("CodeCache", sum(cache.values())) if cache else None
    rows["dylib outside bundle count"] = outside
    rows["code cache status"] = "!!! WARNING: CodeCache is full; compiler disabled !!!" if full else "no full warning"
    if not ordered:
        print(f"WARNING: {path}: No Cofre perf lines found", file=sys.stderr)
    elif not steady:
        print(f"WARNING: {path}: no samples in steady window", file=sys.stderr)
    elif args.window_seconds and rows["steady observed s"] < args.window_seconds:
        print(f"WARNING: {path}: incomplete steady window ({rows['steady observed s']:g}/{args.window_seconds:g}s)", file=sys.stderr)
    if full:
        print(f"!!! WARNING: {path}: CodeCache is full. Compiler has been disabled. !!!", file=sys.stderr)
    complete = not args.window_seconds or rows["steady observed s"] >= args.window_seconds
    return rows, any("fps" in s for s in steady) and complete


def display(value):
    if value is None:
        return "N/A"
    if isinstance(value, (int, float)):
        return f"{value:.3f}".rstrip("0").rstrip(".")
    return str(value).replace("|", "\\|")


try:
    runs = [summarize(path) for path in args.logs]
except OSError as error:
    parser.exit(2, f"{error}\n")
keys = ("renderer", "graphics backend", "JIT mode", "engine flags", "heap", "window origin",
        "steady start s", "steady observed s", "steady samples", "FPS avg", "FPS 1%-low proxy (min)",
        "frame p95 proxy ms", "footprint start MB", "footprint end MB", "footprint max MB",
        "footprint growth MB/s", "thermal timeline s", "thermal nominal s", "thermal fair s",
        "thermal serious s", "thermal critical s", "thermal unknown s", "GC pause count",
        "GC pause total ms", "GC pause max ms", "code cache peak MB", "dylib outside bundle count", "code cache status")
print("FPS/frame: steady window; footprint/thermal/GC/code cache: whole run.")
print("Frame p95 is the nearest-rank p95 of logged five-second p95 values; min is a 1%-low proxy.")
print("Code cache peak uses aggregate max_used, or the sum of per-heap peaks (an upper bound).")
headings = ["Metric", *[display(str(path)) for path in args.logs]]
if len(runs) == 2:
    headings.append("Delta B - A")
print("| " + " | ".join(headings) + " |")
print("| " + " | ".join("---" for _ in headings) + " |")
for key in keys:
    values = [run[0].get(key) for run in runs]
    cells = [key, *map(display, values)]
    if len(runs) == 2:
        a, b = values
        numeric = isinstance(a, (int, float)) and isinstance(b, (int, float))
        delta = f"{b - a:+.3f}".rstrip("0").rstrip(".") if numeric else ("same" if a == b else "—")
        cells.append(delta)
    print("| " + " | ".join(cells) + " |")
sys.exit(0 if all(run[1] for run in runs) else 1)
PY
