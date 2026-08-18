#!/usr/bin/env bash
# Read-only prerequisite check for the Ambxst dev loop on zephyrus.
#
# Reports what is missing and exits nonzero. It never installs, and never
# changes system state.
#
# History: this targeted bostrom, where Ambxst was an experimental shell running
# beside Noctalia and `ambxst` was NOT installed, so lab/ambxst-shim.sh had to
# stand in for it. On zephyrus Ambxst is the real installed shell:
# /usr/local/bin/ambxst execs ~/.local/src/ambxst/cli.sh, autostart is
# `exec-once = ambxst`, and every hotkey goes through `ambxst run <thing>`.
# The keybind check below reflects that, and accepts the shim as the fallback
# rather than the expected case.
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
say '=== Qt/QML packages ==='
# quickshell may be installed as either the release or the -git package; the -git
# package is what zephyrus tracks, so accept either name.
if pacman -Q quickshell-git >/dev/null 2>&1; then
    ok "$(pacman -Q quickshell-git)"
elif pacman -Q quickshell >/dev/null 2>&1; then
    ok "$(pacman -Q quickshell)"
else
    bad 'quickshell or quickshell-git'
fi
for pkg in qt6-declarative qt6-wayland qt6-svg; do
    if pacman -Q "$pkg" >/dev/null 2>&1; then
        ok "$(pacman -Q "$pkg")"
    else
        bad "$pkg"
    fi
done

say
say '=== lint tooling ==='
# lab/check-qml-syntax.sh needs qmllint, which ships in qt6-declarative but is
# NOT on PATH on Arch/CachyOS.
qmllint_found=""
if [[ -n "${QMLLINT:-}" && -x "${QMLLINT:-}" ]]; then
    qmllint_found="$QMLLINT"
elif command -v qmllint >/dev/null 2>&1; then
    qmllint_found="$(command -v qmllint)"
else
    for c in /usr/lib/qt6/bin/qmllint /usr/lib/qt6/qmllint /usr/bin/qmllint-qt6; do
        [[ -x "$c" ]] && { qmllint_found="$c"; break; }
    done
fi
if [[ -n "$qmllint_found" ]]; then
    ok "qmllint -> $qmllint_found"
else
    warn 'qmllint not found; lab/check-qml-syntax.sh will exit 2 (SKIPPED, not a pass)'
fi

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
say '=== sandbox directories ==='
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
# Every hotkey calls bare `ambxst` (see `ambxst run launcher` etc. in
# ~/.local/share/ambxst/hyprland.lua). Two valid arrangements:
#   1. Normal install  - /usr/local/bin/ambxst execs <install>/cli.sh   (zephyrus)
#   2. Lab shim        - `ambxst` resolves to lab/ambxst-shim.sh        (bostrom)
# Either is fine. Only the absence of both is a failure.
if command -v ambxst >/dev/null 2>&1; then
    ambxst_path="$(command -v ambxst)"
    ok "ambxst on PATH -> $ambxst_path"
    shim="$(readlink -f "$REPO_DIR/lab/ambxst-shim.sh" 2>/dev/null || true)"
    if [[ -n "$shim" && "$(readlink -f "$ambxst_path")" == "$shim" ]]; then
        ok 'ambxst resolves to this checkout via lab/ambxst-shim.sh'
    elif target="$(grep -oE '/[^"]*/cli\.sh' "$ambxst_path" 2>/dev/null | head -1)" && [[ -n "$target" ]]; then
        if [[ "$(readlink -f "$target")" == "$(readlink -f "$REPO_DIR/cli.sh")" ]]; then
            ok "ambxst drives THIS checkout ($target)"
        else
            warn "ambxst drives a DIFFERENT checkout ($target), not $REPO_DIR -- \
hotkeys will exercise that install, not your edits"
        fi
    else
        warn "cannot determine which checkout $ambxst_path drives; hotkeys may not exercise your edits"
    fi
else
    bad 'ambxst on PATH (every hotkey is a silent no-op without it; see lab/ambxst-shim.sh)'
fi

say
say '=== NordVPN login hand-back ==='
# Logging in is a two-hop flow and only the first hop is ours. The widget runs
# `nordvpn login` and opens the printed URL; the BROWSER finishes by handing
# nordvpn://login?...&exchange_token=... back to the desktop, which must route it
# to `nordvpn click`. If that second hop cannot launch, the browser still shows
# its "open this link" prompt and reports success, and the user simply stays
# logged out with nothing in any log.
#
# The failure is `Terminal=true` in nordvpn.desktop: GLib refuses to launch a
# terminal application unless it recognizes an installed terminal, and its list
# does not include kitty or alacritty. Verified with `gio launch`, which answered
# "Unable to find terminal required for application".
#
# XDG_DATA_HOME matters twice over. run-isolated.sh points it into the sandbox,
# so a browser the shell spawns resolves handlers from the SANDBOX data home, not
# the real one - the override has to exist in both to cover a cold start.
nordvpn_handler_check() {
    local data_home="$1" label="$2" dir found=""
    for dir in "$data_home" /usr/local/share /usr/share; do
        if [[ -f "$dir/applications/nordvpn.desktop" ]]; then
            found="$dir/applications/nordvpn.desktop"
            break
        fi
    done

    if [[ -z "$found" ]]; then
        warn "no nordvpn.desktop resolvable from $label; the browser hand-back has nowhere to go"
        return
    fi

    if grep -qiE '^\s*Terminal\s*=\s*true\s*$' "$found"; then
        warn "$label resolves nordvpn:// to $found, which declares Terminal=true -- \
GLib cannot launch it, so browser login silently fails. Remedy: install a \
Terminal=false override with
            mkdir -p '$data_home/applications'
            sed 's/^Terminal=true/Terminal=false/' /usr/share/applications/nordvpn.desktop \\
                > '$data_home/applications/nordvpn.desktop'
            update-desktop-database '$data_home/applications'
          The widget's \"Browser didn't bring you back?\" paste field works regardless."
    else
        ok "$label resolves nordvpn:// to a launchable handler ($found)"
    fi
}

if command -v nordvpn >/dev/null 2>&1; then
    ok "nordvpn -> $(command -v nordvpn) ($(nordvpn --version 2>/dev/null || echo 'version unknown'))"
    nordvpn_handler_check "${XDG_DATA_HOME:-$REAL_HOME/.local/share}" 'real data home'
    nordvpn_handler_check "$LAB_HOME/.local/share" 'lab sandbox data home'
else
    # Not a failure: the panel's setup card explains the install, and every other
    # part of the shell works without it.
    warn 'nordvpn CLI absent; the NordVPN panel will show its "not installed" setup card'
fi

say
say '=== recovery path ==='
# If run-isolated.sh exits, or the live shell dies, bare Hyprland must still get
# a terminal. Config layout differs per machine, so check the known locations:
#   zephyrus: ~/.config/hypr/hyprland.lua   (single Lua config)
#   bostrom:  ~/.config/hypr/config/binds.lua
HYPR_CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
bind_found=""
for candidate in "$HYPR_CONF_DIR/hyprland.lua" "$HYPR_CONF_DIR/config/binds.lua"; do
    [[ -f "$candidate" ]] || continue
    if grep -qE 'hl\.bind\(\s*mainMod \.\. " \+ Return"' "$candidate" 2>/dev/null; then
        bind_found="$candidate"
        break
    fi
done
if [[ -n "$bind_found" ]]; then
    ok "SUPER+Return terminal bind present in $bind_found (recovery with no shell running)"
else
    warn "no SUPER+Return terminal bind found under $HYPR_CONF_DIR; recovery would need SSH"
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
