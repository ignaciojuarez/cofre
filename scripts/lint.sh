#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.."; pwd)
files=()
while IFS= read -r f; do files+=("$ROOT/$f"); done < <(git -C "$ROOT" ls-files 'scripts/*.sh' 'tools/llave/*.sh' 'tools/llave/scripts/*.sh' | grep -v '^upstream/' || true)
((${#files[@]})) || exit 0
pipx run shellcheck-py --severity=warning "${files[@]}"
