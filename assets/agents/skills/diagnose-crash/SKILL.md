---
name: diagnose-crash
description: Diagnose a local Linux process crash from a systemd-coredump record. Use for an Ambxst “Process crashed” notification, `ambxst agent crash PID`, coredumpctl records, segfaults, SIGSEGV, SIGABRT, SIGBUS, unexplained application exits, repeated crashes, and backtrace symbolization.
---

# Diagnose a Crash

Investigate from recorded evidence. Separate facts from inferences and leave the
machine unchanged.

## Establish the event

Start with the PID supplied in the prompt:

```bash
coredumpctl info <pid> --no-pager
coredumpctl list --no-pager
```

Record the executable, command line, signal, timestamp, package/build ID, storage
state, and the supplied backtrace. Check whether the same executable is crashing
repeatedly or whether several processes failed together.

## Correlate causes

Rule out system pressure before attributing a software defect:

```bash
free -h
journalctl --no-pager --since '<shortly before crash>' --until '<shortly after crash>'
journalctl -k --no-pager | rg -i 'oom|out of memory|killed process|gpu|amdgpu|nvidia'
```

Compare the crash time with package upgrades, relevant file modification times,
GPU/driver events, plugins, and the work implied by the command line. Treat
coincidence as a lead, not proof.

## Inspect the full backtrace

Read every thread available in `coredumpctl info`. Worker-thread stacks often
reveal the active subsystem even when the crashing frame has no symbols. Note
third-party libraries and extensions, but do not blame them without a stack or
timeline connection.

If more symbols are necessary and `gdb` is available, extract the core privately:

```bash
core=$(mktemp -t ambxst-crash-XXXXXX.core)
trap 'rm -f -- "$core"' EXIT
coredumpctl dump <pid> --output="$core"
DEBUGINFOD_URLS="https://debuginfod.archlinux.org" \
  gdb -q <executable> "$core" -batch \
  -ex 'set debuginfod enabled on' -ex 'thread apply all bt full'
```

A core contains raw process memory and may include credentials, messages, and
documents. Never upload it, paste it into chat, store it in the project, or leave
the extracted copy behind. If symbols remain unavailable, report that limitation
instead of inventing function names.

## Report the diagnosis

Return:

1. What crashed and what it was doing.
2. Facts directly supported by the record.
3. The most likely mechanism, explicitly labelled as inference.
4. Recurrence evidence and practical avoidance, if known.
5. Whether the evidence is strong enough for an upstream report.

Do not apply fixes, alter configuration, install debug packages, or file an issue
without a separate user request. Read
[references/reporting.md](references/reporting.md) before recommending an Ambxst
issue.
