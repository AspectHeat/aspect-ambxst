#!/usr/bin/env bash
# Syntax-check QML by shipping it to Bostrom and running qmllint there.
#
# Why remote: the authoring container has no Qt tooling. Bostrom has qmllint at
# /usr/lib/qt6/bin/qmllint (part of qt6-declarative, not on PATH).
#
# Scope and honest limits:
#   - This catches SYNTAX errors only. qmllint cannot resolve Quickshell's `qs.*`
#     modules, so unresolved-import and unknown-type warnings are expected noise and
#     are filtered out. A file passing here can still fail at runtime on a bad property
#     name or a missing singleton.
#   - Nothing is written to Bostrom's checkout. Files go to a temp dir and are removed.
#
#   ./lab/check-qml-syntax.sh                  # all QML changed vs HEAD
#   ./lab/check-qml-syntax.sh path/a.qml ...   # specific files
#   ./lab/check-qml-syntax.sh --all            # every .qml in the repo

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root" || exit 1

REMOTE="${QML_LINT_HOST:-bostrom}"
REMOTE_QMLLINT="/usr/lib/qt6/bin/qmllint"
REMOTE_DIR="/tmp/qml-syntax-check.$$"

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

if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE" true 2>/dev/null; then
    echo "check-qml-syntax: cannot reach '$REMOTE' over ssh - SKIPPED (not a pass)" >&2
    exit 2
fi

printf 'checking %d file(s) on %s\n' "${#files[@]}" "$REMOTE"

# Ship only the files under test, preserving paths so error output is navigable.
tar -cf - "${files[@]}" | ssh -o BatchMode=yes "$REMOTE" \
    "mkdir -p '$REMOTE_DIR' && tar -xf - -C '$REMOTE_DIR'" || {
        echo "check-qml-syntax: transfer failed" >&2; exit 1; }

# shellcheck disable=SC2029
output=$(ssh -o BatchMode=yes "$REMOTE" bash -s <<EOF
cd '$REMOTE_DIR' || exit 1
rc=0
for f in $(printf '%q ' "${files[@]}"); do
    out=\$('$REMOTE_QMLLINT' "\$f" 2>&1)
    # Keep syntax diagnostics only; qs.* imports are unresolvable here by design.
    syn=\$(printf '%s\n' "\$out" | grep -F '[syntax]')
    if [ -n "\$syn" ]; then
        printf '%s\n' "\$syn"
        rc=1
    fi
done
exit \$rc
EOF
)
status=$?

ssh -o BatchMode=yes "$REMOTE" "rm -rf '$REMOTE_DIR'" 2>/dev/null

if [ $status -eq 0 ]; then
    echo "no syntax errors"
else
    echo "SYNTAX ERRORS:"
    printf '%s\n' "$output"
fi
exit $status
