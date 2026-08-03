#!/usr/bin/env bash

set -u

screen_width="${1:-0}"
screen_height="${2:-0}"
shift 2 2>/dev/null || true

if ! command -v zenity >/dev/null 2>&1; then
    echo "zenity is required to open the image picker" >&2
    exit 127
fi

# Ambxst may run with a sandboxed HOME while the desktop portal runs in the
# real user session. Target the account's actual dconf store so both processes
# read and write the same chooser geometry without hardcoding a home path.
gsettings_command=(gsettings)
if command -v getent >/dev/null 2>&1; then
    account_home="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)"
    if [[ -n "$account_home" && -d "$account_home" ]]; then
        gsettings_command=(env "HOME=$account_home" "XDG_CONFIG_HOME=$account_home/.config" gsettings)
    fi
fi

# GtkFileChooser persists its last window size. A chooser saved on an unscaled
# or larger display can reopen mostly off-screen after a scale/monitor change,
# and the portal ignores Zenity's --width/--height options. Repair only sizes
# that exceed 80% of the current logical screen; otherwise preserve the user's
# preferred dialog size.
if command -v gsettings >/dev/null 2>&1 \
        && [[ "$screen_width" =~ ^[0-9]+$ ]] \
        && [[ "$screen_height" =~ ^[0-9]+$ ]] \
        && (( screen_width > 0 && screen_height > 0 )); then
    for chooser_schema in org.gtk.Settings.FileChooser org.gtk.gtk4.Settings.FileChooser; do
        saved_size="$("${gsettings_command[@]}" get "$chooser_schema" window-size 2>/dev/null || true)"
        if [[ "$saved_size" =~ ^\(([0-9]+),[[:space:]]*([0-9]+)\)$ ]]; then
            saved_width="${BASH_REMATCH[1]}"
            saved_height="${BASH_REMATCH[2]}"
            if (( saved_width * 5 > screen_width * 4 || saved_height * 5 > screen_height * 4 )); then
                target_width=$((screen_width * 2 / 3))
                target_height=$((screen_height * 2 / 3))
                "${gsettings_command[@]}" set "$chooser_schema" window-size \
                    "($target_width, $target_height)" >/dev/null 2>&1 || true
                "${gsettings_command[@]}" set "$chooser_schema" window-position \
                    "(0, 0)" >/dev/null 2>&1 || true
            fi
        fi
    done
fi

exec zenity "$@"
