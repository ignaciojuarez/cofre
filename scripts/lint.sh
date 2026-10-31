#!/usr/bin/env bash
# Formatter findings fail only for files added since main. Older files keep their
# compact style; reformatting them would bury real changes in diffs.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.."; pwd)
files=()
while IFS= read -r f; do files+=("$ROOT/$f"); done < <(git -C "$ROOT" ls-files 'scripts/*.sh' 'tools/llave/*.sh' 'tools/llave/scripts/*.sh')
files+=("$ROOT/scripts/upstream-report.sh")
if ((${#files[@]})); then
    pipx run shellcheck-py --severity=warning "${files[@]}"
fi
if command -v xcrun >/dev/null 2>&1; then
    swift_files=()
    objc_files=()
    while IFS= read -r path; do
        [ -f "$ROOT/$path" ] || continue
        case "$path" in
            *.swift) swift_files+=("$ROOT/$path") ;;
            *.h|*.m) objc_files+=("$ROOT/$path") ;;
        esac
    done < <(
        {
            git -C "$ROOT" diff --name-only --diff-filter=A main
            git -C "$ROOT" ls-files --others --exclude-standard
        } | sort -u
    )
    if ((${#swift_files[@]})); then
        xcrun swift-format lint --strict --configuration "$ROOT/.swift-format" "${swift_files[@]}"
    fi
    if ((${#objc_files[@]})); then
        xcrun clang-format --dry-run -Werror "${objc_files[@]}"
    fi
fi
# Keep the weekly report script in ShellCheck's explicit file set.
