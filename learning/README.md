# Learning notes

One note per Ambxst/QML API or pattern that was learned by doing, per plan
Task 12. Notes are atomic: a single claim, the evidence, and the file(s) it
touched. Write one whenever an experiment teaches something that would hurt
to forget.

## Index

- [[quickshell-probe-baseline]] — verified QML runtime environment, the
  `hello-shell.qml` probe, and SSH gotchas (stale layers, pkill self-match,
  grim hangs)
- [[shell-launcher-recovery-trap]] — a recovery trap must stop the child
  shell before restoring the fallback, or two shells fight the compositor
- [[hyprland-uwsm-autologin]] — SDDM autologin must name the UWSM session
  desktop file, not the plain `hyprland` one
- [[tailscale-operator-prerequisite]] — Tailscale mutations require a
  one-time per-host operator assignment for unprivileged shell controls

Conventions:

- Experiment branches start from updated `main` (`git merge --ff-only
  upstream/main`), one behavior per branch.
- Four-space QML indentation; use `StyledRect`, `Colors`, `Styling`, and
  config defaults; null-check nested values.
- New settings go in both `config/defaults/*.js` and `config/Config.qml`.
- Verify with `bash -n lab/*.sh`, `git diff --check`,
  `./lab/check-prereqs.sh`, then `./lab/run-isolated.sh` before committing.
