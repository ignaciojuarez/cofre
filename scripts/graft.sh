#!/usr/bin/env bash
# Build Cofre's iOS port of Graft (LGPL-3.0 Fabric Metal renderer) for Minecraft 1.21.11.
#   scripts/graft.sh          clone/pin .work/graft, apply patches/graft, build, copy the jar to $GRAFT_OUT
#   scripts/graft.sh serve    serve $GRAFT_OUT on this Mac's LAN address and write a device-ready scenario there
# The source and jar stay out of git; the patch is the reproducible Cofre change.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.."; pwd)
SRC="$ROOT/.work/graft"
OUT=${GRAFT_OUT:-/tmp/graft-build}
REPO=https://github.com/kkorenn/Graft.git
REF=v1.1.1
PIN=4386b98945178da071ba0ffe0b7a1e7e57eddb97  # v1.1.1 (same commit as v1.1.0 upstream)
VERSION=1.1.1-cofre.1
JAR="graft-ios-1.21.11-$VERSION.jar"

if [[ "${1:-}" == serve ]]; then
  port=${2:-8765}
  host=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)
  [[ -n "$host" && -f "$OUT/$JAR" ]] || { echo "need a LAN address and $OUT/$JAR (run scripts/graft.sh first)" >&2; exit 2; }
  sed "s#http://GRAFT_HOST:8765#http://$host:$port#" "$ROOT/scripts/scenarios/fabric-1.21.11-graft.json" > "$OUT/fabric-1.21.11-graft.json"
  echo "Scenario: $OUT/fabric-1.21.11-graft.json  (run: scripts/scenario.sh $OUT/fabric-1.21.11-graft.json)"
  echo "Serving $OUT at http://$host:$port/ until Ctrl-C"
  exec python3 -m http.server "$port" --bind "$host" --directory "$OUT"
fi

if [[ ! -d "$SRC/.git" ]]; then
  mkdir -p "${SRC%/*}"
  git clone --filter=blob:none "$REPO" "$SRC"
fi
git -C "$SRC" fetch --tags --quiet origin
[[ "$(git -C "$SRC" rev-parse "$REF^{commit}")" == "$PIN" ]] || { echo "Graft $REF no longer points at $PIN; review upstream" >&2; exit 1; }

patches=("$ROOT"/patches/graft/*.patch)
stamp="$PIN $(cat "${patches[@]}" | shasum | cut -d' ' -f1)"
if [[ "$(cat "$SRC/.cofre-patches" 2>/dev/null || true)" != "$stamp" ]]; then
  # Our own clone: discard earlier patch output (tracked edits and added files), keep ignored build caches.
  git -C "$SRC" checkout --quiet --force --detach "$PIN"
  git -C "$SRC" clean -fdq
  for patch in "${patches[@]}"; do
    git -C "$SRC" apply --whitespace=nowarn "$patch" || { echo "Graft patch does not apply: $(basename "$patch")" >&2; exit 1; }
  done
  printf '%s\n' "$stamp" > "$SRC/.cofre-patches"
fi

# JDK 25 (Graft's toolchain): $JAVA_HOME, Homebrew, else a private copy under .work/ (no sudo).
is25() { [[ -x "$1/bin/java" ]] && "$1/bin/java" -version 2>&1 | grep -q 'version "25'; }
if ! is25 "${JAVA_HOME:-/nonexistent}"; then
  JAVA_HOME=/opt/homebrew/opt/openjdk@25/libexec/openjdk.jdk/Contents/Home
  if ! is25 "$JAVA_HOME"; then
    JAVA_HOME="$ROOT/.work/jdk-25/Contents/Home"
    if ! is25 "$JAVA_HOME"; then
      rm -rf "$ROOT/.work/jdk-25" && mkdir -p "$ROOT/.work/jdk-25"
      curl -fsSL https://api.adoptium.net/v3/binary/latest/25/ga/mac/aarch64/jdk/hotspot/normal/eclipse \
        | tar -xz -C "$ROOT/.work/jdk-25" --strip-components 1
    fi
  fi
fi
export JAVA_HOME
is25 "$JAVA_HOME" || { echo "Graft needs JDK 25" >&2; exit 2; }

(cd "$SRC" && PATH="$JAVA_HOME/bin:$PATH" ./gradlew --no-daemon -q -Pversion="$VERSION" :mc1_21_11:build)
mkdir -p "$OUT"
cp "$SRC/mc1_21_11/build/libs/$JAR" "$OUT/$JAR"
(cd "$OUT" && shasum -a 256 "$JAR" | tee "$JAR.sha256")
echo "Graft iOS jar: $OUT/$JAR"
