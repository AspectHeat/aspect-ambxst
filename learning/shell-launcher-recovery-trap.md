# Shell launcher recovery trap

**Claim:** a launcher trap that restores the fallback shell must stop the
child shell first; restoring the fallback without killing the child leaves
two shells fighting over one compositor.

**Evidence (2026-07-26, Bostrom):** the first version of
`lab/run-isolated.sh` was tested by signalling the whole process group —
passed. Signalling only the *script* restored Noctalia while Ambxst kept
running. Fixed so the trap stops Ambxst, waits for exit, then starts
Noctalia; re-tested against the script-only signal path.

**Repeatable artifact:** a signal-killed Ambxst leaves a stale
`ambxst:reservation:right, pid: -1` behind (seen twice). Cosmetic, but
useful as a tell that a kill happened rather than a clean exit.

**Touches:** `lab/run-isolated.sh`, `lab/autostart-shell.sh`.
