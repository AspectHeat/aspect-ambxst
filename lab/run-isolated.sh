#!/usr/bin/env bash
# Launch Ambxst from this checkout inside a sandboxed HOME.
#
# There is no fallback shell: exiting leaves bare Hyprland, where SUPER+Return
# still opens a terminal. Noctalia used to be stopped on entry and restarted on
# every exit path; see lab/autostart-shell.sh for why that was removed.
#
# A sandbox HOME is used rather than XDG_* alone because Ambxst hard-codes
# several $HOME/.cache/ambxst and $HOME/.local/share/ambxst paths that XDG
# variables do not redirect.
#
# This script deliberately never calls install.sh, `ambxst update`,
# `ambxst goodbye`, or `ambxst install hyprland`. Those mutate the real system
# and one of them runs `git reset --hard origin/main`.
set -uo pipefail

# --- capture the REAL environment before anything is redirected ------------
# The sandbox and the logs must land in the user's real data/state dirs, not
# inside the sandbox they define.
REAL_HOME="${HOME}"
REAL_XDG_DATA_HOME="${XDG_DATA_HOME:-$REAL_HOME/.local/share}"
REAL_XDG_STATE_HOME="${XDG_STATE_HOME:-$REAL_HOME/.local/state}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LAB_HOME="$REAL_XDG_DATA_HOME/ambxst-lab/home"
LOG_DIR="$REAL_XDG_STATE_HOME/ambxst-lab"
LOG_FILE="$LOG_DIR/latest.log"

# --- take Ambxst down with us on every exit path ---------------------------
stop_ambxst() {
    local rc=$?
    trap - EXIT INT TERM HUP

    # Without this, signalling only this script (rather than the whole process
    # group, as Ctrl+C does) would leave Ambxst orphaned and still drawing.
    if [[ -n "${AMBXST_PID:-}" ]] && kill -0 "$AMBXST_PID" 2>/dev/null; then
        printf '[lab] stopping ambxst (pid %s)...\n' "$AMBXST_PID"
        kill -TERM "$AMBXST_PID" 2>/dev/null || true
        for _ in $(seq 1 25); do
            kill -0 "$AMBXST_PID" 2>/dev/null || break
            sleep 0.2
        done
        kill -0 "$AMBXST_PID" 2>/dev/null && kill -KILL "$AMBXST_PID" 2>/dev/null || true
    fi

    printf '[lab] no shell running; SUPER+Return for a terminal\n'
    exit "$rc"
}
trap stop_ambxst EXIT INT TERM HUP

# --- preflight -------------------------------------------------------------
if [[ ! -f "$REPO_DIR/shell.qml" || ! -f "$REPO_DIR/cli.sh" ]]; then
    printf '[lab] ERROR: %s does not look like an Ambxst checkout\n' "$REPO_DIR" >&2
    exit 1
fi
for var in XDG_RUNTIME_DIR WAYLAND_DISPLAY; do
    if [[ -z "${!var:-}" ]]; then
        printf '[lab] ERROR: %s is unset; run from the graphical session\n' "$var" >&2
        exit 1
    fi
done

mkdir -p "$LAB_HOME"/{.config,.cache} \
         "$LAB_HOME/.local"/{share,state} \
         "$LOG_DIR"

printf '[lab] repo:      %s\n' "$REPO_DIR"
printf '[lab] sandbox:   %s\n' "$LAB_HOME"
printf '[lab] log:       %s\n' "$LOG_FILE"

# --- redirect HOME into the sandbox ----------------------------------------
# XDG_RUNTIME_DIR, WAYLAND_DISPLAY, DBUS_SESSION_BUS_ADDRESS, HYPRLAND_* and
# the UWSM variables are intentionally inherited unchanged: they address the
# live compositor session, not user state.
export HOME="$LAB_HOME"
export XDG_CONFIG_HOME="$LAB_HOME/.config"
export XDG_DATA_HOME="$LAB_HOME/.local/share"
export XDG_CACHE_HOME="$LAB_HOME/.cache"
export XDG_STATE_HOME="$LAB_HOME/.local/state"

printf '[lab] launching ambxst at %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
printf '=== lab run %s ===\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>"$LOG_FILE"

# Run in the background and wait, so $AMBXST_PID is known to the trap.
# cli.sh ends in `exec qs`, so this PID becomes the Quickshell process itself.
bash "$REPO_DIR/cli.sh" > >(tee -a "$LOG_FILE") 2>&1 &
AMBXST_PID=$!
printf '[lab] ambxst pid %s\n' "$AMBXST_PID"
wait "$AMBXST_PID"

# trap handles stopping Ambxst from here
