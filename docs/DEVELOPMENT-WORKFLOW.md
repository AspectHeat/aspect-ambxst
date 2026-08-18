# Aspect Ambxst development workflow

This is the canonical development workflow for every coding agent and editor.
Provider-specific instruction files must point here rather than inventing a
different Git or test procedure.

## Non-negotiable repository roles

| Role | Path or remote | Purpose |
|---|---|---|
| Live runtime checkout | `~/.local/src/ambxst` | The code launched by `/usr/local/bin/ambxst`, autostart, and every Ambxst hotkey |
| Feature worktrees | `~/.local/src/ambxst-worktrees/<topic>` | Isolated editing and testing; create one per feature |
| `origin` | `AspectHeat/aspect-ambxst` | Jayr's fork; push branches and fork `main` here |
| `upstream` | `Axenide/Ambxst` | Original project; fetch only, never push |

Do not develop from `~/Projects/aspect-ambxst`. It is a temporary duplicate
retained only until the live migration and rollback window are closed.

Keep the live checkout clean and on a reviewed branch. Editing files there can
hot-reload the production shell immediately, so an isolated runner does not make
direct live edits safe.

## Before starting any feature

Agents must inspect state rather than assuming `main` is ready:

```bash
cd ~/.local/src/ambxst
git status --short --branch
git fetch origin --prune
git fetch upstream --prune
```

If the live checkout is dirty, diverged unexpectedly, or still awaiting
validation on another feature branch, stop and report it. Never discard, stash,
switch, reset, merge, or clean someone else's work merely to start a task.

Create the feature from the fork's reviewed `main` in a sibling worktree:

```bash
mkdir -p ~/.local/src/ambxst-worktrees
git worktree add -b feature/<topic> \
  ~/.local/src/ambxst-worktrees/<topic> origin/main
cd ~/.local/src/ambxst-worktrees/<topic>
```

If that branch already exists, inspect it and resume deliberately; do not create
a suffixed replacement branch without understanding the existing work.

## Build features in separable layers

For integrations such as an AI-provider usage widget:

1. Put provider-specific collection and normalization in `scripts/`.
2. Expose one stable, non-secret JSON contract.
3. Read it through a service under `modules/services/`.
4. Render it in a widget under the appropriate `modules/widgets/` or `modules/bar/` area.
5. Keep tokens and credentials in existing user config or provider CLIs; never
   commit them or write them into logs and fixtures.

Prefer additive files and thin integration edits. This minimizes conflicts when
`upstream/main` is merged later.

## Verification loop

Run checks from the feature worktree, not the live checkout:

```bash
./lab/check-prereqs.sh
./lab/check-qml-syntax.sh       # changed and untracked QML
./lab/check-qml-syntax.sh --all # required before handoff or merge
./lab/run-isolated.sh           # sandboxed HOME; Ctrl+C exits
```

The isolated shell uses the worktree's QML while the production shell continues
to run from `~/.local/src/ambxst`. For hardware or network controls, distinguish
configuration isolation from system isolation: the test shell can still reach
the laptop's real NetworkManager, rfkill, Tailscale, brightness, and provider
CLIs. Do not exercise destructive actions without explicit approval.

Commit small, coherent milestones and publish the feature branch:

```bash
git status
git add <intentional-paths>
git commit -m "feat(<area>): <change>"
git push -u origin feature/<topic>
```

Never use `git add -A` without reviewing every path first. This is a public
repository; check staged changes for tokens, credentials, personal data, and
hardcoded home paths before every commit.

## Live-use gate and merge

An agent may prepare and publish a feature branch autonomously when requested,
but must not move the production checkout to it, restart the production shell,
merge it into `main`, or delete its worktree unless the user authorizes that
step.

After approval, the live-use gate is:

```bash
cd ~/.local/src/ambxst
git status --short --branch
git switch feature/<topic>
# restart the production shell through its normal UWSM/session mechanism
```

After the user validates the real UI and controls:

```bash
git switch main
git pull --ff-only origin main
git merge --no-ff feature/<topic>
git push origin main
```

Then return the live checkout to `main`, restart the shell if the merge changed
runtime files, and remove the worktree only after confirming it is clean:

```bash
git worktree remove ~/.local/src/ambxst-worktrees/<topic>
git branch -d feature/<topic>
```

Deleting the remote feature branch is optional and requires explicit user intent.

## Taking updates from Axenide

Never run `ambxst update`, `./cli.sh update`, `install.sh`, the upstream installer,
or a hard reset. Use the reviewed merge procedure in `docs/UPSTREAM-SYNC.md`:

```bash
git fetch upstream
git switch -c sync/upstream-$(date +%Y%m%d) main
git merge upstream/main
```

Resolve and verify in the sync branch, then fast-forward fork `main` to the
verified result and push only to `origin`.

## Agent handoff checklist

Every implementation closeout must state:

- worktree path and branch;
- commits created and whether they were pushed;
- checks run and their results;
- whether the production checkout or shell was changed;
- remaining live-use, merge, cleanup, or upstream-sync work.
