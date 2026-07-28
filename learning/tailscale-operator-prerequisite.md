# Tailscale controls need an operator

**Claim:** read-only Tailscale CLI commands work as the session user, but
connection, exit-node, and profile mutations require a one-time operator
assignment on each host.

**Evidence (2026-07-27, Bostrom):** `tailscale status --json` and
`tailscale debug prefs` worked unprivileged. `tailscale set` and
`tailscale switch --list` returned access-denied errors until this was run:

```bash
sudo tailscale set --operator=$USER
```

Afterward, `tailscale switch --list` succeeded as the session user and
`OperatorUser` in `tailscale debug prefs` matched that user. The setting
survives daemon restarts, but it is host state and does not travel with the
repository.

**Implementation consequence:** the shell never invokes `sudo`. It detects an
access-denied mutation, disables controls, and shows a copyable setup command
while preserving read-only status and peer browsing.

**Touches:** `modules/services/TailscaleService.qml`,
`modules/widgets/dashboard/controls/TailscalePanel.qml`.
