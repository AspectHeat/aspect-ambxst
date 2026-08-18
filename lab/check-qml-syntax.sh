#!/usr/bin/env bash
# Syntax-check QML with qmllint, locally.
#
# History: this used to tar the files under test to Bostrom and lint them there,
# because the authoring machine had no Qt tooling. Bostrom is gone, and zephyrus
# has qt6-declarative installed, so it now runs in-place. No ssh, no temp dir.
#
# qmllint ships with qt6-declarative and is NOT on PATH on Arch/CachyOS - it
# lives in /usr/lib/qt6/bin/. Override with QMLLINT=/path/to/qmllint.
#
# Scope and honest limits:
#   - This catches SYNTAX errors only. qmllint cannot resolve Quickshell's `qs.*`
#     modules, so unresolved-import and unknown-type warnings are expected noise and
#     are filtered out. A file passing here can still fail at runtime on a bad property
#     name or a missing singleton.
#
#   ./lab/check-qml-syntax.sh                  # all QML changed vs HEAD
#   ./lab/check-qml-syntax.sh path/a.qml ...   # specific files
#   ./lab/check-qml-syntax.sh --all            # every .qml in the repo
#
# Exit: 0 = no syntax errors, 1 = syntax errors found, 2 = qmllint unavailable
#       (2 is SKIPPED, not a pass - don't gate on it silently)

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root" || exit 1

# Locate qmllint: explicit override, then PATH, then the usual Arch/CachyOS spot.
if [ -n "${QMLLINT:-}" ]; then
    qmllint="$QMLLINT"
elif command -v qmllint >/dev/null 2>&1; then
    qmllint="$(command -v qmllint)"
else
    for candidate in /usr/lib/qt6/bin/qmllint /usr/lib/qt6/qmllint /usr/bin/qmllint-qt6; do
        [ -x "$candidate" ] && { qmllint="$candidate"; break; }
    done
fi

if [ -z "${qmllint:-}" ] || [ ! -x "$qmllint" ]; then
    echo "check-qml-syntax: qmllint not found - SKIPPED (not a pass)" >&2
    echo "  install it with: sudo pacman -S qt6-declarative" >&2
    echo "  or point at it with: QMLLINT=/path/to/qmllint $0" >&2
    exit 2
fi

case "${1:-}" in
    --all) mapfile -t files < <(git ls-files '*.qml') ;;
    "")    mapfile -t files < <(git diff --name-only --diff-filter=ACM HEAD -- '*.qml'
                                git ls-files --others --exclude-standard -- '*.qml') ;;
    *)     files=("$@") ;;
esac

# de-duplicate, keep only files that exist
mapfile -t files < <(printf '%s\n' "${files[@]}" | awk 'NF' | sort -u)
existing=()
for f in "${files[@]}"; do [ -f "$f" ] && existing+=("$f"); done
files=("${existing[@]}")

if [ ${#files[@]} -eq 0 ]; then
    echo "check-qml-syntax: no QML files to check"
    exit 0
fi

printf 'checking %d file(s) with %s\n' "${#files[@]}" "$qmllint"

status=0
output=""
for f in "${files[@]}"; do
    out=$("$qmllint" "$f" 2>&1)
    # Keep syntax diagnostics only; qs.* imports are unresolvable by design.
    syn=$(printf '%s\n' "$out" | grep -F '[syntax]')
    if [ -n "$syn" ]; then
        output+="$syn"$'\n'
        status=1
    fi
done

if [ $status -eq 0 ]; then
    echo "no syntax errors"
else
    echo "SYNTAX ERRORS:"
    printf '%s' "$output"
fi
exit $status
