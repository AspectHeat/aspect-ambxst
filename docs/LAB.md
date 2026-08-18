# Ambxst dev loop on zephyrus

Ambxst is QML running in Quickshell. It hot-reloads, there is no build step, and
a bad edit kills a shell instance rather than a machine. That makes on-machine
development the right default — and on zephyrus it is the *only* option that
actually works, because most of this fork's features need real hardware and real
daemons that no VM provides.

## Which checkout am I working from?

**Answer: `~/.local/src/ambxst` should be the one and only checkout, and it
should track this fork.**

Not `~/Projects/aspect-ambxst`. The install path is baked into three places you
do not want to fight:

| Thing | Hardcodes the path |
|---|---|
| `/usr/local/bin/ambxst` | `exec "$HOME/.local/src/ambxst/cli.sh" "$@"` |
| Autostart | `exec-once = ambxst` in `~/.config/hypr/hyprland.conf` |
| **Every hotkey** | `ambxst run launcher`, `run dashboard`, `run clipboard`, … in `~/.local/share/ambxst/hyprland.lua` |

So whichever checkout lives at `~/.local/src/ambxst` is the one your desktop
runs and the one your keybinds drive. Point that path at your fork and there is
a single source of truth. Move the shell to `~/Projects/` instead and you are
rewriting a root-owned wrapper and re-fighting it after every `install.sh`.

`lab/check-prereqs.sh` tells you which checkout is live:

```
warn  ambxst drives a DIFFERENT checkout (/home/jayr/.local/src/ambxst/cli.sh),
      not /home/jayr/Projects/aspect-ambxst -- hotkeys will exercise that
      install, not your edits
```

### Current state (2026-08-18): mid-transition

There are still **two** checkouts, which is the confusing part:

| Path | Remote | Contents |
|---|---|---|
| `~/.local/src/ambxst` | `Axenide/Ambxst` | upstream `c5c943dd` + 13 uncommitted local files. **This is what runs.** |
| `~/Projects/aspect-ambxst` | `AspectHeat/aspect-ambxst` | the fork: upstream + 55 commits of features |

The target is one checkout at `~/.local/src/ambxst` with `origin` = the fork and
`upstream` = `Axenide/Ambxst`. See `docs/UPSTREAM-SYNC.md` for the remote setup
and merge workflow.

## The loop

```bash
cd ~/.local/src/ambxst          # once it tracks the fork

git switch -c feature/my-thing  # branch per change

# edit QML...

./lab/check-qml-syntax.sh       # local qmllint, seconds, catches syntax
./lab/run-isolated.sh           # run this checkout beside the live shell
                                # Ctrl+C to exit; live shell is untouched

git add -p && git commit        # when it survives real use
```

Quickshell hot-reloads on save, so the live shell picks up edits immediately.
That is the fast path. `run-isolated.sh` is for when you want to try something
without the live shell reacting at all.

`git checkout -- <file>` is your undo. Commit early; the whole reason this fork
exists is that uncommitted work in `~/.local/src/ambxst` is one `ambxst update`
away from gone.

## Why not a VM

A VM cannot exercise most of what this fork does:

| Feature | Needs |
|---|---|
| `Brightness.qml` backlight matching | real sysfs backlight + DRM connector, *and* a phantom NVIDIA backlight to disambiguate from |
| Airplane mode | real rfkill / NetworkManager |
| NordVPN / AirVPN panels | real provider daemons |
| Tailscale panel | real `tailscaled` |
| Power / battery widgets | real EC and battery |

The brightness fix is the clearest case: its entire purpose is picking the
correct backlight when `nvidia_wmi_ec_backlight` also exists. That bug does not
reproduce anywhere but this laptop.

**Use a VM for exactly one class of work:** anything that can leave you without a
desktop — `install.sh`, SDDM themes and greeters, boot/kernel changes,
packaging. That is what the bostrom-era rescue scripts were all cleaning up
after, and it is not widget work. A GPU-accelerated `omarchy-quattro` VM already
exists in libvirt for that.

## Isolation

`run-isolated.sh` redirects `HOME`, not just `XDG_*`, because Ambxst hard-codes
several `$HOME/.cache/ambxst` and `$HOME/.local/share/ambxst` paths that the XDG
variables do not cover.

| Purpose | Path |
|---|---|
| Sandbox `HOME` | `~/.local/share/ambxst-lab/home` |
| Run log | `~/.local/state/ambxst-lab/latest.log` |

`XDG_RUNTIME_DIR`, `WAYLAND_DISPLAY`, `DBUS_SESSION_BUS_ADDRESS` and the
`HYPRLAND_*`/UWSM variables are inherited unchanged, since they address the live
compositor rather than user state.

Known escapes, all in `/tmp` and all transient:

```text
/tmp/ambxst_ipc.pipe
/tmp/ambxst_loginlock.lock
/tmp/ambxst.pid
/tmp/ambxst_sleep_monitor.lock
```

## Recovery

The live shell is unaffected by `run-isolated.sh` exiting. If the sandbox
instance wedges:

```bash
pkill -f '[q]s -p .*aspect-ambxst'   # note the [q] - see gotcha 2
```

If the *live* shell dies, bare Hyprland still gives you `SUPER+Return` for a
terminal, and `ambxst` restarts it. `~/.config/hypr` is a git repo, so config
mistakes are revertible.

## Never run these in a checkout you care about

`ambxst update`, `install.sh`, `ambxst goodbye`, `ambxst install hyprland`.

At least one runs `git reset --hard origin/main`. `run-isolated.sh` deliberately
calls none of them.

## Gotchas

1. **Signal-killing leaves a stale Hyprland layer.** After termination,
   `hyprctl layers` still lists a `pid: -1` entry even though `qs list --all`
   reports no instances. Cosmetic; clears on session restart.
2. **`pkill -f '<pattern>'` can kill your own shell,** because the invoking
   shell's command line contains the pattern. Always bracket a character:
   `'[q]s ...'`.
3. **`nordvpn` is not installed on zephyrus.** The NordVPN panel will show its
   "not installed" setup card, and the login hand-back check in
   `lab/check-prereqs.sh` cannot be exercised. The AirVPN work is the active
   provider thread.

## Machine facts

**ASUS ROG Zephyrus G14 GA403WR** — AMD Strix (Radeon 880M/890M iGPU) plus an
NVIDIA dGPU at `0000:64:00.0` `[10de:2f58]`.

The dGPU is deliberately EC-disabled for battery via ROG Control Center
(`asusctl`/`asusd`), so `dgpu_disable = 1` and the iGPU is the only DRM device —
it enumerates as `/dev/dri/card1`. Do not hardcode card numbers; numbering is not
stable across Hybrid and Integrated boots.

`supergfxctl` is **deprecated and not installed**. `asusd` owns dGPU power state.
Anything in this repo referencing supergfxctl is dead work.

## History

This lab was built on **bostrom**, an Acer Nitro AN515-54 that ran Ambxst
experimentally beside a native Noctalia shell. Bostrom did not survive the
2026-08 move to the UK.

What that means for this directory:

- `lab/autostart-shell.sh` — **removed.** It was bostrom's boot entry point,
  starting Ambxst as an experimental shell via `run-isolated.sh`. On zephyrus
  Ambxst is the real installed shell, autostarted by `exec-once = ambxst`.
- `lab/check-qml-syntax.sh` — **rewritten to run locally.** It used to tar QML
  over ssh to bostrom because the authoring machine had no Qt tooling, so it
  returned exit 2 (SKIPPED) on every invocation once bostrom went away.
- `lab/check-prereqs.sh` — **rewritten.** It expected `ambxst` to resolve to
  `lab/ambxst-shim.sh` (correct on bostrom, where Ambxst was not installed) and
  looked for keybinds in `~/.config/hypr/config/binds.lua` (a path that does not
  exist here). Both now handle the zephyrus layout, with the bostrom arrangement
  as the fallback.
- `lab/ambxst-shim.sh` — kept. Still the right answer for any machine where
  Ambxst is not installed but you want hotkeys to drive a checkout.
