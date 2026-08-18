#!/usr/bin/env bash
# `ambxst` entry point for keybinds and interactive use.
#
# Ambxst upstream expects an `ambxst` command on PATH; its installer provides
# one, and we never run the installer (it hard-resets the checkout). Your
# Hyprland keybind config and the keybind table Ambxst writes to axctl.toml both
# call bare `ambxst` (`ambxst run launcher`, `run dashboard`, …), so without it
# every hotkey is a silent no-op.
#
# NOT needed on zephyrus, where a real install already provides
# /usr/local/bin/ambxst -> ~/.local/src/ambxst/cli.sh. This shim is the fallback
# for a machine with no install, where you want hotkeys to drive a checkout.
#
# Install as a symlink so edits here take effect without reinstalling:
#   sudo ln -sfn "$PWD/lab/ambxst-shim.sh" /usr/local/bin/ambxst
#
# The shim also refuses the subcommands that mutate the real system. `ambxst
# update` runs `curl | sh` and `git reset --hard origin/main`, which would
# destroy uncommitted work in this checkout; putting an `ambxst` on PATH makes
# that one typo away, so it is blocked here rather than merely documented.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"

case "${1:-}" in
update | refresh | install | remove | goodbye)
    printf 'ambxst: refusing to run `%s` from the lab checkout.\n' "$1" >&2
    printf '        It mutates the real system (update hard-resets this repo).\n' >&2
    printf '        See CLAUDE.md "Never run". Install deps with pacman instead.\n' >&2
    exit 64
    ;;
esac

exec bash "$REPO_DIR/cli.sh" "$@"
