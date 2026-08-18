# Reporting an Ambxst crash

Most coredumps belong to the crashed application or one of its linked libraries.
Treat a crash as an Ambxst issue only when evidence connects it to shell code,
generated configuration, or a process Ambxst directly launches and controls.

Before recommending a report:

- reproduce on the current fork revision when practical;
- identify whether the fault belongs to Aspect Ambxst, upstream Ambxst,
  Quickshell, Hyprland, Qt, a driver, or another application;
- include versions, signal, executable, minimal reproduction, and a redacted
  symbolic backtrace;
- remove usernames, home paths, tokens, document names, environment secrets,
  and unrelated process details;
- never attach the core file itself.

Use the fork issue tracker for fork-specific behavior. Recommend upstream only
when the same failure is present without the fork's changes and the evidence
points to upstream-owned code.
