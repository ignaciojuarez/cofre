#!/usr/bin/env bash
# Build Cofre Metallum: Cofre's iOS build of Metallum (MIT Fabric Metal renderer) for Minecraft 26.2 and 26.3.
#   scripts/metallum.sh              build both jars
#   scripts/metallum.sh 26.3         build one (26.2 or 26.3)
# Upstream has no 26.2 branch, so each Minecraft version is its own pinned commit in its own clone
# (.work/metallum-<mc>). Patches named *-mcX.Y-* apply only to that version; the others apply to both.
# Pure FFM (metal-jvm, nested): no native dylib, nothing to sign. Jars land in $METALLUM_OUT (default /tmp/metallum-build).
# Source and jars stay out of git; the patches are the reproducible Cofre change.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.."; pwd)
OUT=${METALLUM_OUT:-/tmp/metallum-build}
REPO=https://github.com/kokodio/metallum.git
VERSION=0.0.25-cofre.1
# Minecraft version → upstream commit (tags only mark releases; 26.2's last commit was never tagged).
pin() {
  case "$1" in
    26.3) echo 467d312b8bc68ee3210697f01855244e8f2831a2 ;;  # master: v0.0.25 (4da72f5) + 5bee03e getOrCompileFunction lock
    26.2) echo a12ffb346c79d580de2e9565501205ec81c60025 ;;  # "MRT": last 26.2 commit, already on metal-jvm
    *) echo "Unknown Minecraft version $1 (expected 26.2 or 26.3)" >&2; return 1 ;;
  esac
}
versions=("$@")
((${#versions[@]})) || versions=(26.2 26.3)

# JDK 25 (Metallum's toolchain): $JAVA_HOME, Homebrew, else a private copy under .work/ (no sudo).
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
is25 "$JAVA_HOME" || { echo "Metallum needs JDK 25" >&2; exit 2; }

mkdir -p "$OUT"
for mc in "${versions[@]}"; do
  commit=$(pin "$mc")
  src="$ROOT/.work/metallum-$mc"
  if [[ ! -d "$src/.git" ]]; then
    mkdir -p "${src%/*}"
    git clone --filter=blob:none --no-checkout "$REPO" "$src"
  fi
  git -C "$src" cat-file -e "$commit^{commit}" 2>/dev/null || git -C "$src" fetch --quiet origin
  git -C "$src" cat-file -e "$commit^{commit}" || { echo "Metallum $commit not found upstream; review the pin" >&2; exit 1; }

  patches=()
  for patch in "$ROOT"/patches/metallum/*.patch; do
    case "$(basename "$patch")" in
      *-mc"$mc"-*) patches+=("$patch") ;;
      *-mc[0-9]*) ;;
      *) patches+=("$patch") ;;
    esac
  done
  stamp="$commit $(cat "${patches[@]}" | shasum | cut -d' ' -f1)"
  if [[ "$(cat "$src/.cofre-patches" 2>/dev/null || true)" != "$stamp" ]]; then
    # Our own clone: discard earlier patch output (tracked edits and added files), keep ignored build caches.
    git -C "$src" checkout --quiet --force --detach "$commit"
    git -C "$src" clean -fdq
    for patch in "${patches[@]}"; do
      git -C "$src" apply --whitespace=nowarn "$patch" || { echo "Metallum $mc patch does not apply: $(basename "$patch")" >&2; exit 1; }
    done
    printf '%s\n' "$stamp" > "$src/.cofre-patches"
  fi

  jar="metallum-cofre-mc$mc-$VERSION.jar"
  rm -f "$src/build/libs/$jar"
  (cd "$src" && PATH="$JAVA_HOME/bin:$PATH" ./gradlew --no-daemon -q -Pmod_version="$VERSION" build)
  # Gradle stamps the nested metal-jvm jar with the build time; fixed timestamps make the jar hash pinnable.
  python3 -I - "$src/build/libs/$jar" "$OUT/$jar" <<'PY'
import io, sys, zipfile
def normalized(data):
    out = io.BytesIO()
    with zipfile.ZipFile(io.BytesIO(data)) as source, zipfile.ZipFile(out, "w") as target:
        for entry in source.infolist():
            body = source.read(entry)
            if entry.filename.endswith(".jar"):
                body = normalized(body)
            info = zipfile.ZipInfo(entry.filename, date_time=(1980, 2, 1, 0, 0, 0))
            info.compress_type, info.external_attr = entry.compress_type, entry.external_attr
            target.writestr(info, body)
    return out.getvalue()
with open(sys.argv[1], "rb") as source, open(sys.argv[2], "wb") as target:
    target.write(normalized(source.read()))
PY
  (cd "$OUT" && shasum -a 256 "$jar" | tee "$jar.sha256")
  echo "Cofre Metallum $mc jar: $OUT/$jar"
done
