---
name: ambxst
description: Safely inspect, customize, and troubleshoot an installed Aspect Ambxst desktop. Use for Ambxst dashboard, bar, notch, dock, theme, wallpaper, notifications, Hyprland integration, user configuration, agent integration, and `ambxst` CLI requests. Use for end-user changes, not for contributing to the Ambxst source repository.
---

# Ambxst

Treat the running desktop as production infrastructure. Establish which checkout
the `ambxst` command launches, plan meaningful changes first, and keep every
customization reversible.

## Safety boundary

- Read the active checkout and its `CLAUDE.md`/`AGENTS.md` before changing files.
- Never run Ambxst's install, update, goodbye, or removal paths unless the user
  explicitly requests the exact operation after reviewing its effects.
- Prefer the settings UI and files under `~/.config/ambxst/` for end-user
  customization. Do not edit generated files under `~/.local/share/ambxst/`.
- Do not assume a source checkout is the live checkout. Resolve the launcher and
  compare both paths first.
- Use `./lab/run-isolated.sh` from the source checkout for risky shell changes.
- Preserve unrelated local edits and never use destructive Git recovery commands.

## Workflow

1. Identify the requested surface and the active checkout.
2. Read the relevant local instructions and existing configuration.
3. For a non-trivial change, present a short plan and rollback before editing.
4. Make the narrowest user-config change that satisfies the request.
5. Validate the affected format and check Ambxst/Hyprland logs for regressions.
6. State what changed, what was tested, and how to undo it.

Read [references/customization.md](references/customization.md) for paths,
validation commands, and the distinction between configuration and source work.
