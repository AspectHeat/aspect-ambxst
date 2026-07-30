#!/usr/bin/env bash
# Boot entry point: start Ambxst as Bostrom's primary shell.
#
# Called from ~/.config/hypr/config/autostart.lua on hyprland.start.
#
# There is deliberately NO fallback shell. Noctalia used to be spawned on every
# failure path, but the recovery it bought was worth less than the two failure
# modes it caused: a second shell drawing behind Ambxst, and a resurrection race
# where a dying session's belt-and-braces check (`sleep 1; pgrep noctalia ||
# start it`) fired *after* the next session had already started Ambxst, so every
# compositor restart left two shells running. Recovery now rests on bare
# Hyprland: SUPER+Return still opens a terminal with no shell running at all,
# and SSH over Tailscale plus Sunshine/Moonlight are independent of this script.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ambxst-lab"
BOOT_LOG="$LOG_DIR/boot.log"
mkdir -p "$LOG_DIR"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$BOOT_LOG"; }

# No shell could be started. Log it and say so on screen if a notification
# daemon happens to be up; never start a competing shell.
give_up() {
    log "NOT starting a shell: $1"
    notify-send -u critical 'Ambxst did not start' "$1"$'\n''SUPER+Return for a terminal; see boot.log.' \
        >/dev/null 2>&1 || true
}

log "=== boot: starting primary shell ==="

# --- derive session environment if the compositor has not exported it yet ---
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    for _ in $(seq 1 30); do
        candidate="$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'wayland-*' ! -name '*.lock' \
                     -printf '%f\n' 2>/dev/null | sort | head -1)"
        [[ -n "$candidate" ]] && { export WAYLAND_DISPLAY="$candidate"; break; }
        sleep 0.5
    done
fi

if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" && -d "$XDG_RUNTIME_DIR/hypr" ]]; then
    sig="$(ls -1t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)"
    [[ -n "$sig" ]] && export HYPRLAND_INSTANCE_SIGNATURE="$sig"
fi

export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"

log "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset} HIS=${HYPRLAND_INSTANCE_SIGNATURE:-unset}"

if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    give_up 'no wayland socket appeared within 15s'
    exit 0
fi

# --- wait for the compositor to answer before launching a shell into it -----
for _ in $(seq 1 30); do
    hyprctl monitors >/dev/null 2>&1 && break
    sleep 0.5
done
if ! hyprctl monitors >/dev/null 2>&1; then
    give_up 'hyprctl never became responsive'
    exit 0
fi

if [[ ! -x "$REPO_DIR/lab/run-isolated.sh" ]]; then
    give_up "missing $REPO_DIR/lab/run-isolated.sh"
    exit 0
fi

# Don't stomp a shell that is already running. On a compositor restart this
# script can still be alive from the previous session; without this check both
# instances race to own the same Quickshell instance ID.
if pgrep -f "[q]s -p $REPO_DIR/shell.qml" >/dev/null 2>&1; then
    log 'ambxst already running for this checkout; nothing to do'
    exit 0
fi

log 'launching ambxst via lab/run-isolated.sh'
"$REPO_DIR/lab/run-isolated.sh" >>"$BOOT_LOG" 2>&1
rc=$?
log "run-isolated.sh exited rc=$rc"
