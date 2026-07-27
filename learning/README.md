# Quickshell learning probe

Minimal Quickshell surface used to validate the QML runtime on Bostrom
independently of Ambxst. Nothing here imports Ambxst modules or touches
Hyprland configuration.

## Environment (verified 2026-07-26)

| Item | Value |
|---|---|
| Host | Bostrom (Acer Nitro AN515-54), CachyOS, kernel `7.1.4-1-cachyos` |
| Compositor | Hyprland 0.56.0 via UWSM |
| Runtime | `quickshell 0.3.0-2.1` (`/usr/bin/qs`), reports `Quickshell 0.3.0 (distributed by Arch Linux)` |
| Qt | `qt6-declarative 6.11.1-3.1`, `qt6-wayland 6.11.1-1.1`, `qt6-svg`, `qt6-tools` |
| Baseline shell | native `noctalia 5.0.0_beta.5-1`, left running throughout |

Imported modules: `Quickshell` (for `PanelWindow`) and `QtQuick` (for `Text`).

## Start

```bash
cd ~/Projects/aspect-ambxst
qs -p learning/hello-shell.qml
```

Over SSH the graphical session must be addressed explicitly:

```bash
export XDG_RUNTIME_DIR=/run/user/1000
export WAYLAND_DISPLAY=wayland-1
export HYPRLAND_INSTANCE_SIGNATURE="$(ls /run/user/1000/hypr | head -1)"
```

## Stop

```bash
qs kill -p learning/hello-shell.qml     # graceful; preferred
```

## Verified result

The probe registers its own layer surface alongside Noctalia's, rather than
replacing them:

```text
namespace: noctalia-wallpaper,  pid: 914
namespace: noctalia-bar-default, pid: 914
namespace: quickshell,           pid: 21134   <- the probe, 1280x30
```

Noctalia kept the same PID (914) before, during, and after the probe. No QML
warnings or errors were emitted; the log showed only `Configuration Loaded`.

## Warnings and gotchas

1. **Abruptly killing the probe leaves a stale layer in Hyprland.** After
   terminating by signal, `hyprctl layers` still lists
   `namespace: quickshell, pid: -1` even though `qs list --all` reports
   "No running instances". It is compositor bookkeeping, not a live surface,
   and it clears on session restart — but prefer `qs kill` over signals so it
   does not accumulate during a long lab session.

2. **`pkill -f '<pattern>'` over SSH can kill your own session.** The pattern
   matches the remote shell's own command line, which contains the pattern.
   This killed a live SSH connection during setup. Use a pattern that cannot
   self-match:

   ```bash
   pkill -f '[q]s -p learning/hello-shell.qml'
   ```

3. **`grim` hung** when invoked over SSH against this session and had to be
   killed. Screenshot capture is unresolved; verify surfaces with
   `hyprctl layers` instead, which is reliable and scriptable.
