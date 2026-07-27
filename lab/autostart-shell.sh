#!/usr/bin/env bash
# Boot entry point: start Ambxst as Bostrom's primary shell, with native
# Noctalia as an automatic fallback.
#
# Called from ~/.config/hypr/config/autostart.lua on hyprland.start. It is
# deliberately defensive: this runs before there is any desktop to report
# errors into, so every failure path must still end with a usable shell.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ambxst-lab"
BOOT_LOG="$LOG_DIR/boot.log"
mkdir -p "$LOG_DIR"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$BOOT_LOG"; }

fallback_to_noctalia() {
    log "falling back to native noctalia: $1"
    pgrep -x noctalia >/dev/null 2>&1 && { log 'noctalia already running'; return; }
    setsid noctalia -d >/dev/null 2>&1 &
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
    fallback_to_noctalia 'no wayland socket appeared within 15s'
    exit 0
fi

# --- wait for the compositor to answer before launching a shell into it -----
for _ in $(seq 1 30); do
    hyprctl monitors >/dev/null 2>&1 && break
    sleep 0.5
done
if ! hyprctl monitors >/dev/null 2>&1; then
    fallback_to_noctalia 'hyprctl never became responsive'
    exit 0
fi

if [[ ! -x "$REPO_DIR/lab/run-isolated.sh" ]]; then
    fallback_to_noctalia "missing $REPO_DIR/lab/run-isolated.sh"
    exit 0
fi

# run-isolated.sh owns the sandbox and already restores Noctalia when Ambxst
# exits for any reason, so a mid-session Ambxst crash also lands on Noctalia.
log 'launching ambxst via lab/run-isolated.sh'
"$REPO_DIR/lab/run-isolated.sh" >>"$BOOT_LOG" 2>&1
rc=$?
log "run-isolated.sh exited rc=$rc"

# Belt and braces: if the launcher died before its own trap could run.
sleep 1
pgrep -x noctalia >/dev/null 2>&1 || fallback_to_noctalia "launcher exited rc=$rc"
