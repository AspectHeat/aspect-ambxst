# CLAUDE.md — Aspect Ambxst fork

Fork-specific instructions. **Read the upstream `AGENTS.md` files first** — they are
good and still authoritative for QML architecture, conventions, and anti-patterns.
This file only records what differs because this is a fork, plus corrections where
upstream's instructions describe the maintainer's machine rather than ours.

**Canonical Git and development procedure:** `docs/DEVELOPMENT-WORKFLOW.md`.
Follow it for branch creation, worktrees, testing, production gates, merges, and
handoffs. It is provider-neutral and overrides older examples elsewhere.

Do not edit the upstream-generated body of `AGENTS.md` or any
`modules/**/AGENTS.md`. The short fork-override header at the top of root
`AGENTS.md` is intentionally maintained here for providers that do not read
`CLAUDE.md`; all detailed workflow remains canonical in
`docs/DEVELOPMENT-WORKFLOW.md`.

## What this repo is

Public fork of `Axenide/Ambxst`, renamed **Aspect Ambxst**.

| Remote | Target | Push |
|---|---|---|
| `origin` | `AspectHeat/aspect-ambxst` | yes |
| `upstream` | `Axenide/Ambxst` | **disabled** (`DISABLED_read_only_upstream`) |

**`main` is the fork's own trunk — not an upstream mirror.** Jay's customizations
live on `main`. Upstream is merged *into* it periodically. Do not try to keep
`main` byte-identical to upstream, and do not use `merge --ff-only` for syncing;
that only worked while `main` was still pristine, and it no longer is.

Branches: `main` is the trunk; `archive/zephyrus-local-2026-07-25` preserves
pre-fork customizations to cherry-pick from; `feature/<topic>` for one experiment
each, cut from `main`. (`lab/bootstrap` was merged into `main` and deleted.)

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

## Where work happens — one machine, one live checkout

Bostrom is gone (it did not survive the 2026-08 move to the UK). There is no
remote test target and no push/pull loop. Everything happens on zephyrus.

**The authoritative runtime checkout is `~/.local/src/ambxst`.** Three things hardcode
that path and you do not want to fight any of them:

| Thing | Hardcodes |
|---|---|
| `/usr/local/bin/ambxst` | `exec "$HOME/.local/src/ambxst/cli.sh" "$@"` |
| Autostart | `exec-once = ambxst` in `~/.config/hypr/hyprland.conf` |
| **Every hotkey** | `ambxst run launcher`, `run dashboard`, … in `~/.local/share/ambxst/hyprland.lua` |

So whichever checkout sits at `~/.local/src/ambxst` is the one the desktop runs
and the one the keybinds drive.

The migration completed on 2026-08-18: this checkout now uses
`AspectHeat/aspect-ambxst` as `origin` and fetch-only `Axenide/Ambxst` as
`upstream`. `~/Projects/aspect-ambxst` is a temporary duplicate, not a development
path.

Feature development uses sibling Git worktrees under
`~/.local/src/ambxst-worktrees/<topic>`. This keeps edits away from the live
Quickshell watcher until the user approves a production test. See the canonical
workflow rather than creating branches or editing files directly in this live
checkout.

`lab/run-isolated.sh` runs a checkout under a sandboxed `HOME` at
`~/.local/share/ambxst-lab/home`, because Ambxst hard-codes several
`$HOME/.cache/ambxst` and `$HOME/.local/share/ambxst` paths that `XDG_*` alone
does not redirect. It runs *beside* the live shell, so the live desktop is
unaffected by anything the sandbox instance does.

```bash
./lab/check-prereqs.sh   # read-only; lists what is missing, installs nothing
./lab/check-qml-syntax.sh # local qmllint (/usr/lib/qt6/bin/qmllint)
./lab/run-isolated.sh    # sandboxed run beside the live shell; Ctrl+C to exit
```

Logs: `~/.local/state/ambxst-lab/latest.log`.

## Ambxst is zephyrus's primary shell

Autostarted by `exec-once = ambxst` in `~/.config/hypr/hyprland.conf`, which runs
`/usr/local/bin/ambxst` → `~/.local/src/ambxst/cli.sh`. This is a normal upstream
install, not a lab arrangement.

Because Quickshell hot-reloads on save, **editing the live checkout changes the
running desktop immediately.** Normal feature work therefore happens in a sibling
worktree; direct live edits are reserved for an explicitly approved live-use gate.
Layers of protection, in order:

1. `git checkout -- <file>` — the fastest undo. Commit early and often.
2. `lab/run-isolated.sh` — try risky changes in a sandbox beside the live shell,
   so the live one never sees them.
3. `SUPER+Return` opens a terminal from bare Hyprland with no shell running at
   all — the compositor's own bind, independent of Ambxst.
4. SSH over Tailscale, independent of the graphical session.
5. `~/.config/hypr` is a git repo, so compositor config mistakes are revertible.

**There is no fallback shell, by design.** Noctalia was removed on 2026-07-29 —
package and all — because it caused more breakage than it prevented: a second
shell drew behind Ambxst, and a resurrection race restarted it on every
compositor restart. Do not reintroduce an automatic fallback that launches a
*competing* shell into the same session; if a failsafe is wanted again, it has to
be one that cannot run concurrently with Ambxst.

### Keybinds go through `/usr/local/bin/ambxst`

Every hotkey calls bare `ambxst` (`ambxst run launcher`, `run dashboard`,
`run clipboard`, … in `~/.local/share/ambxst/hyprland.lua`), so without that
command on PATH **every hotkey is a silent no-op**.

On zephyrus the normal installer provides it:

```bash
cat /usr/local/bin/ambxst
#!/usr/bin/env bash
export PATH="$HOME/.local/bin:$PATH"
export QML2_IMPORT_PATH="$HOME/.local/lib/qml:$QML2_IMPORT_PATH"
exec "$HOME/.local/src/ambxst/cli.sh" "$@"
```

`/usr/local/bin` is used because the graphical session's PATH does not include
`~/.local/bin`.

`lab/ambxst-shim.sh` is the **fallback** for a machine where Ambxst is not
installed but you still want hotkeys to drive a checkout. It refuses
`update`/`install`/`remove`/`goodbye`/`refresh`, which are exactly the "Never run"
commands above. It is not needed on zephyrus.

```bash
# only on a machine with no real install:
sudo ln -sfn "$PWD/lab/ambxst-shim.sh" /usr/local/bin/ambxst
```

Note that axctl's own keybind table never reaches Hyprland — `hyprctl binds` shows
only `__lua` binds. `~/.config/hypr/hyprland.lua` plus the ambxst-generated
`~/.local/share/ambxst/hyprland.lua` it `dofile`s are the source of truth for
hotkeys.

## Hardware

**ASUS ROG Zephyrus G14 GA403WR** — AMD Strix (Radeon 880M/890M iGPU) plus an
NVIDIA dGPU at `0000:64:00.0` `[10de:2f58]`.

Upstream Ambxst contains **zero** references to `asusctl` or `supergfxctl`, so any
vendor-control widget is new development.

- **The dGPU is deliberately EC-disabled for battery** via ROG Control Center
  (`asusctl`/`asusd`): `dgpu_disable = 1`. The iGPU is therefore the only DRM
  device and enumerates as `/dev/dri/card1`. **Never hardcode card numbers** —
  numbering is not stable across Hybrid and Integrated boots.
- **`supergfxctl` is deprecated and not installed.** `asusd` owns dGPU power
  state. `docs/supergfxctl-widget-plan.html` is dead work.
- A phantom `nvidia_wmi_ec_backlight` exists even with the dGPU off, which is why
  `Brightness.qml` matches the backlight to the shell screen's DRM connector
  instead of calling `brightnessctl --class backlight` bare.
- `asusctl` targets available here: fan curves, Aura/RGB, battery charge limit,
  ACPI `platform_profile` (`quiet balanced performance`), `power-profiles-daemon`.
- `nordvpn` is **not installed**; the NordVPN panel shows its setup card. AirVPN
  is the active provider thread.

## Upstream sync

See `docs/UPSTREAM-SYNC.md` for the full workflow, conflict hotspots, and why
`rerere`/`zdiff3` are configured.

```bash
git fetch upstream
git log --oneline main..upstream/main         # what landed
git switch -c sync/upstream-$(date +%Y%m%d) main
git merge upstream/main        # a real merge — NOT --ff-only; main has diverged
# resolve conflicts, then verify before adopting:
./lab/check-qml-syntax.sh
./lab/run-isolated.sh
git switch main && git merge --ff-only sync/upstream-YYYYMMDD
git push origin main
```

Upstream ships in bursts (0 commits in June 2026, 64 in July), so sync
deliberately after a burst rather than continuously.

Expect conflicts in exactly two places, both ours by design:

- **`AGENTS.md`** — our fork-override header sits above upstream's content.
  Upstream rewrites that file wholesale roughly twice a year. Resolution: keep our
  header block, take theirs for everything below it.
- Any upstream file we have customized.

`CLAUDE.md`, `lab/`, `docs/LAB.md` and `learning/` are ours alone and will never
conflict.

Never `git push upstream` (its push URL is already disabled). Never use Ambxst's
own `update` command in this clone. After any sync, re-run the shell under
`lab/run-isolated.sh` before letting the change reach boot.

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
   A *stale* socket is the dangerous variant: Ambxst spawns `axctl daemon` but the
   daemon does not unlink its socket when it dies with the shell, so the next
   daemon refuses to bind and `axctl subscribe` fails in a loop — the bar comes up
   with no workspace or window data and only `JSON.parse: Parse error` in the log.
   `run-isolated.sh` now clears an unanswered socket on both entry and exit; if you
   kill the shell some other way, `rm -f /tmp/axctl-1000.sock` before restarting.
6. **`mpvpaper` is not installed** — it needs a `luajit` build no longer on any
   mirror, so it requires a full `pacman -Syu` plus reboot. Only affects video
   wallpapers; Ambxst logs a killed-mpvpaper line and continues.
8. **Adding a new `.qml` file needs a shell restart, not a hot reload.** Quickshell
   hot-reloads edits to existing files fine, but a newly *added* type is not
   registered into the directory's implicit module by a reload. The symptom is
   misleading: `Failed to load configuration ... <NewType> is not a type`, pointing
   at the file that *uses* it rather than the new file itself. The config is fine — a
   fresh start picks it up. Verify with an offscreen load before restarting the
   primary shell:
   ```bash
   QT_QPA_PLATFORM=offscreen qs -p /path/to/clone/shell.qml   # exercises QML type
                                                              # resolution, creates
                                                              # no real surfaces
   ```
   Quickshell rejects a bad reload and keeps the previous scene, so a failed reload
   does not cost the desktop — but it does leave the checkout on a config that will
   not load on the *next* cold start. Revert the checkout or fix it before walking away.
9. **`qmllint` cannot resolve `qs.*` imports**, so it catches syntax errors only.
   `lab/check-qml-syntax.sh` wraps it and filters the unresolvable-import noise. For
   real type and binding checks, instantiate the component under
   `QT_QPA_PLATFORM=offscreen` as above — that surfaces `ReferenceError`s and bad
   property names that `qmllint` silently passes.

10. **`hyprctl dispatch` does not work here.** Re-verified on zephyrus 2026-08-18:
    `hyprctl dispatch exec true` returns
    `error: [string "return hl.dispatch(exec true)"]:1: ')' expected near 'true'`.
    This is **not** a bostrom quirk — it is a property of the CachyOS Lua config,
    which zephyrus also uses. The Lua config wraps every
    command as `hl.dispatch(<args>)`, so `hyprctl dispatch dpms on` fails with
    `')' expected near 'on'` — a Lua syntax error, not a Hyprland error. Writing to
    Hyprland's IPC socket directly fails the same way, because the wrapper sits under
    that too; the socket's own hint is that it wants `hl.dsp.*` style dispatchers.
    Use `axctl` instead, or the `ambxst` verbs that wrap it:
    ```bash
    ambxst screen on          # works: goes through axctl, no Lua layer
    axctl monitor list        # JSON, useful for scripting
    hyprctl monitors -j       # QUERIES are fine; only `dispatch` is wrapped
    ```
    This matters most in an emergency, when `hyprctl dispatch` is the reflex.
11. **A blank screen is usually DPMS, not a broken shell.** Check
    `hyprctl monitors -j` for `"dpmsStatus": false` before suspecting a QML change —
    Ambxst's own idle listeners power the display down. Also check `"scale"` before
    reading anything into layer geometry: at scale 1.5 a correct full-screen layer
    reads `1280x720` on a 1920x1080 monitor, which looks alarming and is not.
    zephyrus's live listeners are in `~/.config/ambxst/config/system.json` and are
    **active** (dim via `brightnessctl -d amdgpu_bl1` at 150 s, lock at 300 s) —
    correct for a laptop you sit in front of. Note the explicit `-d amdgpu_bl1`:
    same reasoning as `Brightness.qml`, name the backlight rather than letting
    brightnessctl guess.
12. **A `Terminal=true` desktop file cannot be launched here at all.** GLib only
    launches terminal applications through a terminal it recognizes, and its built-in
    list (`xdg-terminal-exec`, `gnome-terminal`, `xterm`, …) matches nothing on this
    machine — zephyrus has kitty and ghostty, and `$TERMINAL` is unset (re-verified
    2026-08-18). `gio launch` fails with
    *"Unable to find terminal required for application"*.

    This bit NordVPN login, and the failure is silent in the worst way: browser login
    ends by handing `nordvpn://login?…&exchange_token=…` back to the desktop for
    `nordvpn click`, and `/usr/share/applications/nordvpn.desktop` ships
    `Terminal=true`. The browser shows its "open this link" prompt, reports success, and
    the user stays logged out with nothing in any log. Fixed with `Terminal=false`
    overrides in **both** data homes — the real one and the lab sandbox's, because
    `run-isolated.sh` repoints `XDG_DATA_HOME` and a browser the shell spawns inherits
    it:
    ```bash
    for d in ~/.local/share ~/.local/share/ambxst-lab/home/.local/share; do
        mkdir -p "$d/applications"
        sed 's/^Terminal=true/Terminal=false/' /usr/share/applications/nordvpn.desktop \
            > "$d/applications/nordvpn.desktop"
        update-desktop-database "$d/applications"
    done
    ```
    `lab/check-prereqs.sh` now checks both homes for this. A package update to
    `nordvpn` will not clobber the overrides, but suspect them first if login regresses.
    Generalize the lesson: any URI-handler hand-off we rely on needs `gio launch`
    tested explicitly, because every layer above it reports success.

## Conventions worth restating

From upstream, most frequently violated:

- 4-space QML indent.
- Never hardcode colors or sizes — use `Config.*`, `Colors.*`, `Styling.*`.
- Never create a raw `Rectangle` container — use `StyledRect` with a variant.
- Any new config key needs an entry in **both** `config/defaults/*.js` and
  `config/Config.qml`.
- `Qt.callLater()` when modifying lists inside process handlers.
- Null-check nested properties.
