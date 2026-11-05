#!/usr/bin/env bash
# Builds tests/engine/thread_qos_harness.c against a desktop JDK 25 and checks the QoS each named thread ends up with.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.."; pwd)
JAVA_HOME=${JAVA_HOME_25:-/opt/homebrew/opt/openjdk@25/libexec/openjdk.jdk/Contents/Home}
if [[ ! -f "$JAVA_HOME/include/jvmti.h" ]]; then
    echo "skipped: no JDK 25 at $JAVA_HOME (set JAVA_HOME_25)"
    exit 0
fi
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun clang -std=c11 -Wall -Werror -I "$ROOT/app/Glue/AirBridge" -I "$JAVA_HOME/include" -I "$JAVA_HOME/include/darwin" \
    "$ROOT/tests/engine/thread_qos_harness.c" -L "$JAVA_HOME/lib/server" -ljvm -Wl,-rpath,"$JAVA_HOME/lib/server" \
    -o "$OUT/harness"
"$OUT/harness" > "$OUT/log.txt"
expect() { grep -qx "$1" "$OUT/log.txt" || { echo "missing: $1"; cat "$OUT/log.txt"; exit 1; }; }
expect "qos Worker-Main-1 requested=0x11 now=0x11"
expect "qos IO-Worker-3 requested=0x11 now=0x11"
expect "qos Server thread requested=0x19 now=0x19"
expect "qos Chunk Render Task Executor #2 requested=0x11 now=0x11"
if grep -q "qos Other" "$OUT/log.txt"; then echo "unexpected QoS change for Other"; exit 1; fi
echo "thread QoS: $(wc -l < "$OUT/log.txt" | tr -d ' ') threads set"
