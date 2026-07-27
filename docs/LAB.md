# Bostrom Aspect Ambxst lab

Isolated Quickshell/QML test environment. Native Noctalia stays the known-good
desktop; Ambxst runs beside it from this checkout under a sandboxed `HOME`, and
Noctalia is restored whenever the lab exits.

## Layout

| Purpose | Path |
|---|---|
| This checkout | `/home/bostrom/Projects/aspect-ambxst` |
| Sandbox `HOME` | `/home/bostrom/.local/share/ambxst-lab/home` |
| Run log | `/home/bostrom/.local/state/ambxst-lab/latest.log` |
| Baseline snapshot | `/home/bostrom/Backups/noctalia-baseline-2026-07-26.tar.zst` |
| Autostart backup | `/home/bostrom/Backups/autostart.lua.before-ambxst` |

Remote access from Zephyrus: `ssh bostrom` (Tailnet) or `ssh bostrom-lan` (LAN).
Git remote uses the repo-scoped deploy key alias `github-aspect-ambxst`.

## Run

From a graphical terminal on Bostrom:

```bash
cd ~/Projects/aspect-ambxst
./lab/check-prereqs.sh     # read-only; exits nonzero and lists what is missing
./lab/run-isolated.sh      # Ctrl+C to exit and restore Noctalia
```

Over SSH the graphical session must be addressed explicitly first:

```bash
export XDG_RUNTIME_DIR=/run/user/1000
export WAYLAND_DISPLAY=wayland-1
export HYPRLAND_INSTANCE_SIGNATURE="$(ls /run/user/1000/hypr | head -1)"
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
```

## Recovery

The launcher restores Noctalia on `EXIT`, `INT`, `TERM`, and `HUP`, stopping
Ambxst first. If something escapes it:

```bash
pkill -f '[q]s -p .*aspect-ambxst'   # note the [q] — see gotcha 2
noctalia -d
```

To restore the whole desktop configuration from the baseline:

```bash
cd ~ && tar --zstd -xf ~/Backups/noctalia-baseline-2026-07-26.tar.zst
```

Bostrom's Hyprland autostart is deliberately **not** modified — Ambxst is never
imported permanently during the lab phase. `autostart.lua` is verified identical
to its backup after every run.

## Isolation

Ambxst hard-codes several `$HOME/.cache/ambxst` and `$HOME/.local/share/ambxst`
paths, so `XDG_*` alone is insufficient — the launcher redirects `HOME` itself.
`XDG_RUNTIME_DIR`, `WAYLAND_DISPLAY`, `DBUS_SESSION_BUS_ADDRESS` and the
`HYPRLAND_*`/UWSM variables are inherited unchanged, since they address the live
compositor rather than user state.

Verified after a full run: `~/.config/ambxst`, `~/.local/share/ambxst` and
`~/.cache/ambxst` in the real home were all still absent, with 5.7 MB of state
in the sandbox instead.

Known escapes, all in `/tmp` and all transient:

```text
/tmp/ambxst_ipc.pipe
/tmp/ambxst_loginlock.lock
/tmp/ambxst.pid
/tmp/ambxst_sleep_monitor.lock
```

The launcher never calls `install.sh`, `ambxst update`, `ambxst goodbye`, or
`ambxst install hyprland`. One of those runs `git reset --hard origin/main`.

## Installed dependency delta (2026-07-26)

Base system already provided 37 of Ambxst's listed packages. Added:

```text
quickshell qt6-declarative qt6-wayland qt6-svg qt6-tools jq git      # Task 6
tmux fuzzel network-manager-applet blueman easyeffects playerctl
qt6-imageformats libavif ddcutil wlsunset wtype python-pipx zenity
tesseract tesseract-data-eng ttf-roboto ttf-roboto-mono
ttf-nerd-fonts-symbols matugen gpu-screen-recorder wl-clip-persist
supergfxctl unzip
```

Plus, outside pacman:

- `axctl v0.0.19` → `/usr/local/bin/axctl`. Installed by downloading the release
  binary from `Axenide/axctl` and `install -m 755`, replicating what
  `get.axeni.de/axctl` does, rather than piping a remote script into a shell.
- Phosphor icon fonts v2.1.2 → `<sandbox>/.local/share/fonts/phosphor` (6 TTFs),
  mirroring `install.sh`'s `install_phosphor_fonts()`. Kept inside the sandbox so
  isolation holds.

**Deliberately not installed:**

- `mpvpaper` — needs `luajit-2.1.1784902473+346ab58-1.1`, which no longer exists
  on any mirror; the local sync DB references a superseded build. Needs a full
  `pacman -Syu` (and a reboot) to resolve. Only affects video wallpapers; Ambxst
  logs `Killed mpvpaper processes ... exit code: 1` and continues.
- `gradia`, `ttf-league-gothic`, `python312` — AUR-only, all optional. No AUR
  helper is installed on Bostrom and none is required.

Three CachyOS mirrors (`mirror5.krfoss.org`, `mirror.krfoss.org`) were commented
out of `cachyos-{,v3-,v4-}mirrorlist` after repeated 404s on package signatures.
Backups: `/etc/pacman.d/*.bak-20260726`.

## Hardware transfer: what Bostrom can and cannot test

Bostrom is an **Acer Nitro AN515-54** (Intel UHD 630 + NVIDIA GTX 1050 Max-Q).
Zephyrus is an **ASUS ROG Zephyrus G14 GA403WR** (AMD + NVIDIA). This matters for
any shell work touching vendor control tooling.

| | Zephyrus (ASUS) | Bostrom (Acer) |
|---|---|---|
| `supergfxctl` modes | `Integrated, Hybrid, AsusMuxDgpu` | `Integrated, Hybrid` |
| `asus-nb-wmi` platform device | present (`ASUS2018:00`, `ASUS9001:00`) | **absent** (`acer-wmi` only) |
| ACPI `platform_profile` | `quiet balanced performance` | **absent** |
| `power-profiles-daemon` | yes | yes (`intel_pstate`: power-saver/balanced/performance) |

- **`supergfxctl` — mostly transfers.** `supergfxd` runs correctly on Bostrom,
  detects the dGPU (`10DE:1C91`), and manages nvidia module loading and runtime
  PM. Integrated ↔ Hybrid switching — the common path — is genuinely testable
  here. `AsusMuxDgpu` (the hardware MUX) is ASUS-only and cannot be. Note the
  iGPU vendor differs (Intel vs AMD), so anything keying off driver names or GPU
  enumeration still needs validating on Zephyrus.
- **`asusctl` — does not transfer at all.** Fan curves, Aura/RGB keyboard,
  battery charge limit and ASUS throttle profiles are all backed by ASUS firmware
  interfaces Bostrom does not have; `asusd` has nothing to bind to. Build against
  a mock here, validate on Zephyrus.
- **Generic power profiles do transfer.** Ambxst's `PowerProfile` service came up
  clean on Bostrom and enumerated all three profiles via `powerprofilesctl`.

`supergfxd` is started but **not enabled at boot** on Bostrom. Switching graphics
mode restarts the display session, so do it deliberately, not mid-test.

## Verified run (2026-07-26)

Full shell launched from a clean sandbox. Ambxst registered eight layer surfaces
(`ambxst:wallpaper`, `ambxst`, `ambxst:screenCorners`, `ambxst:osd`, and four
`ambxst:reservation:*`), ran Matugen against the bundled wallpaper, generated 10
thumbnails in 3.2 s, and detected power profiles. Recovery was tested twice —
signalling the process group, and signalling only the launcher — and both
restored Noctalia with no orphaned Ambxst process. Hyprland kept PID 874 the
whole time and never restarted.

Benign first-run warnings: missing `binds.json`/`general.json`/`ai.json` etc.
(created on demand), absent `.face.icon`, and `WeatherService` failing GeoIP with
no location configured.

## Gotchas

1. **Signal-killing leaves a stale Hyprland layer.** After termination,
   `hyprctl layers` still lists a `pid: -1` entry even though `qs list --all`
   reports no instances. Seen with both the minimal probe and the full shell.
   Cosmetic; clears on session restart.
2. **`pkill -f '<pattern>'` over SSH can kill your own session,** because the
   remote shell's command line contains the pattern. This killed a live SSH
   connection during setup. Always bracket a character: `'[q]s ...'`.
3. **`grim` hangs** when invoked over SSH against this session. Use
   `hyprctl layers` to verify surfaces instead.
