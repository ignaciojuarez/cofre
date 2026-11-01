#!/usr/bin/env bash
# Runs every device-free check. Set COFRE_SIM_UDID to a shared simulator to include the iOS UI tests.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
failed=()

check() {
    local name=$1
    shift
    echo "==> $name"
    if "$@"; then
        echo "    ok"
    else
        echo "    FAILED"
        failed+=("$name")
    fi
}

check "smoke" "$ROOT/scripts/smoke.sh"
check "lint" "$ROOT/scripts/lint.sh"
check "renderer handoff" python3 "$ROOT/tests/renderer/check.py"
check "Metallum agent repair" python3 "$ROOT/tests/renderer/metallum_agent.py"
check "server join" bash -c "cd '$ROOT/app/ServerJoin' && swift test"
check "server-card" bash -c "cd '$ROOT/tools/server-card' && swift build"
check "CofreUI (macOS)" bash -c "cd '$ROOT/app/UI' && swift test"
check "pairing engine" bash -c "cd '$ROOT/tools/llave/core' && cargo test"
check "Llave dry run" sh "$ROOT/tools/llave/test-pair.sh"
check "JIT script" bash -c "for t in '$ROOT'/tests/jit/*.test.js; do node \"\$t\" || exit 1; done"
check "server cards" bash -c "cd '$ROOT/plan/server-join' && python3 validate_examples.py"
check "known mods docs" python3 "$ROOT/scripts/check-known-mods.py"
if [[ -n "${COFRE_SIM_UDID:-}" ]]; then
    check "CofreUI (iOS)" bash -c "cd '$ROOT/app/UI' && xcodebuild test -scheme CofreUI -destination 'platform=iOS Simulator,id=$COFRE_SIM_UDID' -quiet"
fi

if ((${#failed[@]})); then
    echo "Failed: ${failed[*]}"
    exit 1
fi
echo "All checks passed."
