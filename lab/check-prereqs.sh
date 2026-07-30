#!/usr/bin/env bash
# Read-only prerequisite check for the Bostrom Aspect Ambxst lab.
#
# Reports what is missing and exits nonzero. It never installs, and never
# changes system state.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_HOME="${HOME}"
LAB_HOME="${XDG_DATA_HOME:-$REAL_HOME/.local/share}/ambxst-lab/home"

missing=()
warnings=()

say()  { printf '%s\n' "$*"; }
ok()   { printf '  ok      %s\n' "$*"; }
bad()  { printf '  MISSING %s\n' "$*"; missing+=("$1"); }
warn() { printf '  warn    %s\n' "$*"; warnings+=("$1"); }

say '=== commands ==='
for cmd in qs git jq python3 axctl; do
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "$cmd -> $(command -v "$cmd")"
    else
        bad "$cmd"
    fi
done

say
say '=== Qt/QML modules ==='
# quickshell needs these at runtime; pacman is the source of truth on Arch.
for pkg in quickshell qt6-declarative qt6-wayland qt6-svg; do
    if pacman -Q "$pkg" >/dev/null 2>&1; then
        ok "$(pacman -Q "$pkg")"
    else
        bad "$pkg"
    fi
done

say
say '=== graphical session ==='
for var in XDG_RUNTIME_DIR WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE; do
    if [[ -n "${!var:-}" ]]; then
        ok "$var=${!var}"
    else
        bad "$var (export it, or run from a graphical terminal)"
    fi
done

if [[ -n "${XDG_RUNTIME_DIR:-}" && -n "${WAYLAND_DISPLAY:-}" ]]; then
    if [[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]]; then
        ok "wayland socket $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
    else
        bad "wayland socket $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
    fi
fi

if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    ok 'DBUS_SESSION_BUS_ADDRESS set'
else
    warn 'DBUS_SESSION_BUS_ADDRESS unset (some Ambxst services may degrade)'
fi

say
say '=== lab directories ==='
for dir in "$LAB_HOME" "${XDG_STATE_HOME:-$REAL_HOME/.local/state}/ambxst-lab"; do
    if mkdir -p "$dir" 2>/dev/null && [[ -w "$dir" ]]; then
        ok "writable $dir"
    else
        bad "writable $dir"
    fi
done

say
say '=== repository ==='
if [[ -f "$REPO_DIR/shell.qml" ]]; then
    ok "entry point $REPO_DIR/shell.qml"
else
    bad "$REPO_DIR/shell.qml"
fi
if [[ -f "$REPO_DIR/cli.sh" ]]; then
    ok "launcher $REPO_DIR/cli.sh"
else
    bad "$REPO_DIR/cli.sh"
fi

say
say '=== keybind plumbing ==='
# Every hotkey in ~/.config/hypr/config/binds.lua and in the keybind table
# Ambxst writes to axctl.toml calls bare `ambxst`. Upstream's installer provides
# it; we never run the installer, so lab/ambxst-shim.sh stands in.
if command -v ambxst >/dev/null 2>&1; then
    ok "ambxst on PATH -> $(command -v ambxst)"
    if [[ "$(readlink -f "$(command -v ambxst)")" == "$(readlink -f "$REPO_DIR/lab/ambxst-shim.sh")" ]]; then
        ok 'ambxst resolves to this checkout'
    else
        warn "ambxst does NOT point at $REPO_DIR/lab/ambxst-shim.sh; hotkeys may drive another install"
    fi
else
    bad 'ambxst on PATH (every hotkey is a silent no-op without it; see lab/ambxst-shim.sh)'
fi

say
say '=== recovery path ==='
# There is no fallback shell by design. Bare Hyprland must still get a terminal.
BINDS_LUA="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/config/binds.lua"
if grep -qE '^\s*hl\.bind\(mainMod \.\. " \+ Return"' "$BINDS_LUA" 2>/dev/null; then
    ok 'SUPER+Return terminal bind present (recovery with no shell running)'
else
    warn "no SUPER+Return terminal bind found in $BINDS_LUA; recovery would need SSH"
fi
if grep -qi noctalia "$BINDS_LUA" 2>/dev/null; then
    warn "$BINDS_LUA still references noctalia; those hotkeys are dead"
fi

say
if (( ${#missing[@]} )); then
    say "FAIL: ${#missing[@]} missing prerequisite(s): ${missing[*]}"
    exit 1
fi
if (( ${#warnings[@]} )); then
    say "PASS with ${#warnings[@]} warning(s)."
else
    say 'PASS: all prerequisites satisfied.'
fi
