#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.."; pwd)
files=()
while IFS= read -r f; do files+=("$ROOT/$f"); done < <(git -C "$ROOT" ls-files 'scripts/*.sh' 'tools/llave/*.sh' 'tools/llave/scripts/*.sh')
if ((${#files[@]})); then
    pipx run shellcheck-py --severity=warning "${files[@]}"
fi
if command -v xcrun >/dev/null 2>&1; then
    xcrun swift-format lint --configuration "$ROOT/.swift-format" -r "$ROOT/app/UI" "$ROOT/app/Glue" "$ROOT/app/Shell" || true
    xcrun clang-format --dry-run -Werror "$ROOT"/app/Glue/AirBridge/*.{h,m} || true
fi
