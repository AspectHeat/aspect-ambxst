# Hyprland UWSM autologin

**Claim:** on a UWSM-managed Hyprland system, SDDM autologin must set
`Session=hyprland-uwsm` (the `hyprland-uwsm.desktop` entry); the plain
`Session=hyprland` starts a non-UWSM session and silently drops the UWSM
environment management (`wayland-wm@hyprland.desktop.service`, environment
preloader, `systemctl --user` slice integration).

**Evidence (2026-07-26, Bostrom):** `/etc/sddm.conf` had `[Autologin]`
with `Session=hyprland` and **no `User=` line** — autologin was not even
functional. SDDM's own state file recorded the last real session as
`hyprland-uwsm.desktop`. Setting both `User=bostrom` and
`Session=hyprland-uwsm` booted straight into the UWSM session; verified by
`systemctl --user` showing `wayland-wm@hyprland.desktop.service` active.

**Touches:** `/etc/sddm.conf` (host config, not this repo).
