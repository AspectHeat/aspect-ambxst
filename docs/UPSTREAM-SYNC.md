# Keeping aspect-ambxst in sync with upstream Ambxst

## Remotes

| Remote | URL | Purpose |
|---|---|---|
| `origin` | `git@github.com:AspectHeat/aspect-ambxst.git` | your fork — push here |
| `upstream` | `https://github.com/Axenide/Ambxst.git` | Axenide's Ambxst — **fetch only** |

`upstream`'s push URL is set to `DISABLED`, so `git push upstream` cannot fire by accident.

## Why merges here are cheap

Measured against `upstream/main` (2026-07-23, `c5c943dd`):

```
87 files changed, 10524 insertions(+), 73 deletions(-)
  72 files ADDED by us      <- new files never conflict
  15 files MODIFIED         <- the only real conflict surface
```

**73 deletions against 10,524 insertions — the fork is ~99% additive.** That is the single
reason upstream merges stay easy, and it is worth protecting.

### Conflict hotspots, worst first

| File | Churn | Note |
|---|---|---|
| `modules/components/SegmentedSwitch.qml` | +132 / **-58** | the one genuine rewrite of an upstream component — expect conflicts here |
| `modules/widgets/dashboard/controls/SettingsTab.qml` | +95 / -7 | |
| `modules/widgets/dashboard/controls/PanelTitlebar.qml` | +48 / -1 | |
| `modules/widgets/dashboard/controls/SettingsIndex.qml` | +20 / -1 | |
| `modules/bar/systray/SysTrayItem.qml` | +16 / -1 | |
| `modules/bar/systray/SysTray.qml` | +15 / -2 | |
| `modules/widgets/dashboard/widgets/QuickControls.qml` | +9 / -2 | |
| `config/Config.qml`, `config/defaults/system.js`, `shell.qml` | additive only | safe |

**The rule that keeps this working: add files, don't edit them.** When a feature needs upstream
behaviour changed, prefer a new component that wraps or replaces the original over editing it in
place. `SegmentedSwitch.qml` is the counterexample — 58 deleted lines that will need
re-resolving every time Axenide touches that file. If it were `SegmentedSwitchExt.qml`, the
conflict surface would be near zero.

## The sync workflow

Upstream ships in bursts (0 commits in June 2026, 64 in July), so sync deliberately after a
burst rather than continuously.

```bash
cd ~/.local/src/ambxst

# 1. See what landed upstream
git fetch upstream
git log --oneline main..upstream/main

# 2. Merge onto a scratch branch first - never straight onto main
git switch -c sync/upstream-$(date +%Y%m%d) main
git merge upstream/main

# 3. Resolve conflicts. zdiff3 shows the common ancestor in each block,
#    which makes QML merges much easier to reason about.

# 4. Verify before adopting
./lab/check-qml-syntax.sh
./lab/run-isolated.sh          # runs under a sandboxed HOME, Ctrl+C to exit

# 5. Adopt
git switch main && git merge --ff-only sync/upstream-YYYYMMDD
git push origin main
```

### Why this repo is configured the way it is

```
rerere.enabled       true      # records how you resolved a conflict...
rerere.autoupdate    true      # ...and replays it automatically next time
merge.conflictstyle  zdiff3    # shows the common ancestor inside conflict blocks
pull.rebase          false     # merge, don't rebase - keeps feature history intact
```

`rerere` matters most here. A long-lived fork hits *the same* conflicts in
`SegmentedSwitch.qml` and `SettingsTab.qml` every sync. With rerere on, you solve each one
once and git replays the resolution forever after.

Do **not** rebase your work onto upstream. Rebasing rewrites 55+ commits of feature history and
throws away the merge resolutions rerere has learned.

## Never run these in a checkout you care about

`ambxst update`, `install.sh`, `ambxst goodbye`, `ambxst install hyprland` — at least one does
`git reset --hard origin/main` and will destroy uncommitted work. See `docs/LAB.md`.

## Status as of 2026-08-18

- `main` is **0 commits behind** `upstream/main` and **55 ahead**. Already fully current.
- Unmerged feature branches: `feature/airvpn-provider-widget` (18), `feature/ai-widget-stability-hermes` (23).
- `feature/nordvpn-live-widget` and `feature/tailscale-panel` are merged into `main` (0 ahead) and can be deleted.
- `docs/supergfxctl-widget-plan.html` is **dead work** — supergfxctl is deprecated and no longer
  installed on zephyrus; `asusd`/ROG Control Center owns dGPU power state now.
