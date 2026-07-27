# CLAUDE.md — Aspect Ambxst fork

Fork-specific instructions. **Read the upstream `AGENTS.md` files first** — they are
good and still authoritative for QML architecture, conventions, and anti-patterns.
This file only records what differs because this is a fork, plus corrections where
upstream's instructions describe the maintainer's machine rather than ours.

Do not edit `AGENTS.md` or any `modules/**/AGENTS.md`. Upstream changes them roughly
monthly (7 commits in the last 6 months); editing them here would cause a merge
conflict on nearly every sync. Fork-specific guidance goes in this file instead.

## What this repo is

Public fork of `Axenide/Ambxst`, renamed **Aspect Ambxst**.

| Remote | Target | Push |
|---|---|---|
| `origin` | `AspectHeat/aspect-ambxst` | yes |
| `upstream` | `Axenide/Ambxst` | **disabled** (`DISABLED_read_only_upstream`) |

Branches: `main` tracks upstream; `lab/bootstrap` holds lab tooling;
`archive/zephyrus-local-2026-07-25` preserves pre-fork local customizations to
cherry-pick from; `feature/<topic>` for one experiment each.

The repo is **public**. Before committing, check for credentials, tokens, absolute
home paths, and personal data. This has already bitten once — a helper script
hardcoded a personal vault path and timezone and had to be made portable before
publishing.

## Corrections to upstream AGENTS.md

Upstream's root `AGENTS.md` was written on the maintainer's machine. These parts do
not apply here:

- **`/home/adriano/Repos/Axenide/axctl/`** (lines 9–12, 130) does not exist for us.
  `axctl` is installed as a prebuilt release binary at `/usr/local/bin/axctl`
  (currently v0.0.19, from `github.com/Axenide/axctl` releases). We do not build it
  from source, so the "rebuild axctl after changes" instruction is inapplicable.
- **`/home/adriano/Repos/Axenide/web/`** (line 131) does not exist. We do not
  maintain Axenide's changelog website. Ignore all changelog instructions.
- **`curl -L get.axeni.de/ambxst | sh`** (line 121) must never be run — see below.

## Never run

These mutate the real system, and one of them destroys uncommitted work:

- `install.sh` — its update path runs `git reset --hard origin/main`
- `./cli.sh update`, `ambxst update`
- `ambxst goodbye`, `ambxst install hyprland`
- `curl -L get.axeni.de/ambxst | sh`

Install dependencies explicitly with `pacman -S --needed` instead. When a tool is
only distributed via a `curl | sh` installer, read the script first and replicate
its steps by hand — that is how `axctl` was installed.

## Where work happens

Development and testing happen on **Bostrom** (Acer Nitro AN515-54, CachyOS,
Hyprland/UWSM), reachable as `ssh bostrom` (Tailnet) or `ssh bostrom-lan`, with
passwordless sudo and a repo-scoped deploy key (`github-aspect-ambxst`).

Zephyrus keeps a separate production checkout at `~/.local/src/ambxst`. **Never
touch it** — it has uncommitted customizations and its installer can hard-reset.

Bostrom clone: `~/Projects/aspect-ambxst`. Ambxst runs under a sandboxed `HOME` at
`~/.local/share/ambxst-lab/home`, because Ambxst hard-codes several
`$HOME/.cache/ambxst` and `$HOME/.local/share/ambxst` paths that `XDG_*` alone does
not redirect. Live config therefore lives under the sandbox, not the real home.

```bash
./lab/check-prereqs.sh   # read-only; lists what is missing, installs nothing
./lab/run-isolated.sh    # sandboxed run; restores the fallback shell on exit
```

Logs: `~/.local/state/ambxst-lab/latest.log` (runs) and `boot.log` (boot).

## Ambxst is Bostrom's primary shell

Set via `~/.config/hypr/config/autostart.lua` → `lab/autostart-shell.sh`. **A bad
change costs the desktop on next boot.** Layers of protection, in order:

1. `autostart-shell.sh` falls back to native Noctalia if Ambxst fails to start.
2. `run-isolated.sh`'s trap restores Noctalia if Ambxst exits mid-session.
3. SSH over Tailscale, independent of the graphical session.
4. Sunshine/Moonlight for visual access.
5. Revert: `cp ~/Backups/autostart.lua.before-ambxst ~/.config/hypr/config/autostart.lua`

Noctalia is not wanted as a daily shell, but it is currently the only *automatic*
recovery path. Keep it installed unless a replacement failsafe exists.

Test risky changes with `./lab/run-isolated.sh` before they can affect boot.

## Hardware: what Bostrom can and cannot validate

Bostrom is an **Acer** (Intel UHD 630 + GTX 1050 Max-Q). Zephyrus is an **ASUS ROG
G14** (AMD + NVIDIA). Upstream Ambxst contains **zero** references to `asusctl` or
`supergfxctl`, so any vendor-control widget is new development.

| | Zephyrus (ASUS) | Bostrom (Acer) |
|---|---|---|
| `supergfxctl` | `Integrated, Hybrid, AsusMuxDgpu` | `Integrated, Hybrid` |
| `asus-nb-wmi` | present | **absent** (`acer-wmi`) |
| ACPI `platform_profile` | `quiet balanced performance` | **absent** |
| `power-profiles-daemon` | yes | yes (`intel_pstate`) |

- `supergfxctl` mostly transfers; Integrated ↔ Hybrid is testable. `AsusMuxDgpu` is
  not. iGPU vendor differs, so driver-name-sensitive code still needs Zephyrus.
  `supergfxd` is installed but **not enabled at boot** on Bostrom.
- `asusctl` does **not** transfer — fan curves, Aura/RGB, battery limit and ASUS
  throttle profiles all bind to firmware Bostrom lacks. Build against a mock here,
  validate on Zephyrus.
- Generic power profiles do transfer.

## Upstream sync

```bash
git fetch upstream
git switch main && git merge --ff-only upstream/main && git push origin main
git switch feature/<topic> && git rebase main
```

Never `git push upstream`. Never use Ambxst's own `update` command in this clone.

## Environment gotchas

1. **`pkill -f '<pattern>'` over SSH can kill your own session** — the remote shell's
   command line contains the pattern. Bracket a character: `pkill -f '[q]s ...'`.
2. **Signal-killing Quickshell leaves a stale `pid: -1` layer** in `hyprctl layers`
   even when `qs list --all` reports none. Cosmetic; clears on session restart.
   Prefer `qs kill`. Does not occur in normal operation.
3. **`grim` hangs** over SSH against this session. Verify surfaces with
   `hyprctl layers` instead.
4. **Driving the session over SSH** needs the environment exported explicitly:
   ```bash
   export XDG_RUNTIME_DIR=/run/user/1000
   export WAYLAND_DISPLAY=wayland-1
   export HYPRLAND_INSTANCE_SIGNATURE="$(ls -1t /run/user/1000/hypr | head -1)"
   export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
   ```
5. **`axctl` socket race at boot** — Ambxst may log
   `dial unix /tmp/axctl-1000.sock: no such file or directory` once during startup,
   before the daemon creates the socket. Transient; self-resolves.
6. **`mpvpaper` is not installed** — it needs a `luajit` build no longer on any
   mirror, so it requires a full `pacman -Syu` plus reboot. Only affects video
   wallpapers; Ambxst logs a killed-mpvpaper line and continues.
7. Three krfoss CachyOS mirrors are commented out after repeated signature 404s
   (backups at `/etc/pacman.d/*.bak-20260726`).

## Conventions worth restating

From upstream, most frequently violated:

- 4-space QML indent.
- Never hardcode colors or sizes — use `Config.*`, `Colors.*`, `Styling.*`.
- Never create a raw `Rectangle` container — use `StyledRect` with a variant.
- Any new config key needs an entry in **both** `config/defaults/*.js` and
  `config/Config.qml`.
- `Qt.callLater()` when modifying lists inside process handlers.
- Null-check nested properties.
