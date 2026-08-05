# AirVPN provider widget — recon findings (2026-08-04)

Recon run 2026-08-04 against Bostrom (AirVPN Suite 2.1.0, `bluetit.service` active,
`bostrom ∈ airvpn`, **not logged in**). These findings correct or extend
`docs/airvpn-provider-widget-plan.html` v1.1, which marked much of this "assumed".

## 1. CRITICAL — an ungated credentialed call can OOM the desktop

Without credentials, `goldcrest --air-user-info` and `--air-key-list` do **not** error.
They prompt on stdin:

```
AirVPN Username:
```

and block forever. `timeout` reports exit **124**.

Worse: with **stdin at EOF** (`< /dev/null`) goldcrest enters a tight loop re-printing the
prompt. Measured: **3.97 GB of stdout in 12 seconds.** Bostrom's `/tmp` is a 3.8 G tmpfs, so
the capture file consumed essentially all of it — RAM-backed.

This matters because Quickshell's `Process` gives its child **EOF on stdin** unless
`stdinEnabled` is set. So a naive

```qml
CliRead { command: ["goldcrest", "--air-user-info"] }
```

on a logged-out machine would flood `cli.buffer` at multi-GB/s and OOM-kill the shell —
taking the desktop with it, since Ambxst is Bostrom's primary shell.

Three independent mitigations, all required:

1. **Never invoke a credential-requiring subcommand unless `credentialsConfigured` is
   already true.** `credentialsConfigured` is derived by *reading the rc file*, not by
   probing the CLI.
2. **Every** goldcrest invocation is wrapped in `timeout` (`GOLDCREST_TIMEOUT` in the
   service). Defense in depth for a subcommand that turns out to prompt unexpectedly.
3. `CliRead` enforces an **output byte ceiling** and kills the process when exceeded, so a
   prompt loop is capped at kilobytes rather than gigabytes.

The plan's §3 suggested "successful `--air-user-info`" as the credentials probe. That probe
is the exact hazard above and must not be used as the primary signal.

## 2. Country browse works with NO credentials — plan §3 is wrong

`goldcrest --air-list --air-country all` returns the full AirVPN footprint while the rc file
is entirely commented out:

```
** AirVPN Country List (23) **
ISO Code Name                           Servers Users Bandwidth    Max BW    Load
-------- ------------------------------ ------- ----- ------------ ---------- ----
AT       Austria                              3   487  3.87 Gbit/s 6.00 Gbit/s  64%
```

The plan's data matrix lists countries as "Needs credentials" and "Blocking for
browse/connect". Both wrong. Consequence, and the agreed UX: the country list is populated
and searchable **before** login; only *connect* is gated. `air-list-countries.txt` is
therefore a real committed fixture rather than a Phase-02 deferral.

`--air-list` needs a literal pattern; `all` works, `*` does not (`ERROR: AirVPN country not
found`, exit 1 — captured as `air-list-country-notfound.txt`).

## 3. `--air-list` mutates daemon state; `--bluetit-status` does not

Every `--air-list` invocation prints:

```
Bluetit options successfully reset
```

`--bluetit-status` does **not**. So the poll path (status) is safe to run every 20 s, but the
browse path resets Bluetit's staged options and must be fetched **once**, never on a poll
tick. Not mentioned in the plan.

## 4. Output grammar

- Line 1 is an untimestamped banner; line 2 blank.
- Every subsequent line is prefixed `YYYY-MM-DD HH:MM:SS `. The parser strips this first —
  otherwise no label or table row matches.
- The country table is **fixed-width**, and the widths are recoverable from the `---- ----`
  rule line, which is the robust way to slice it. Caveat: the `Bandwidth` / `Max BW` values
  *overflow* their declared columns (`6.00 Gbit/s` in a 10-wide field), so those two columns
  are not sliced. v1 does not need them; `Load` is taken with a trailing `(\d+)%` match.
- Names contain spaces and parentheses (`Republic of China (Taiwan)`), so whitespace
  splitting is not an option — another reason for column slicing.

## 5. State vocabulary

Verified disconnected form:

```
Network filter and lock is disabled
Bluetit is not connected
```

The **connected** form is still unverified (needs login). Per the NordVPN lesson, an
unrecognized status resolves to `error` with `unknownStatus`, never to `disconnected`.

## 6. Confirmed environment facts

- `goldcrest` and `hummingbird` at `/usr/local/bin`; **no** `airvpn`/`eddie` binary — the
  plan's "call goldcrest only" is naturally enforced.
- `bluetit.service` enabled + active; `bluetit-suspend`/`bluetit-resume` also enabled.
- `bostrom` is in group `airvpn`; `/etc/airvpn` is `root:airvpn` 0750.
- Network lock currently **disabled** — leave it that way (enabling it can drop Tailscale and
  SSH on this host, which is our only remote access).
- Appendix A of the plan is already done. Gate 01 is effectively complete.

## 7. Fixtures captured

All home paths redacted to `$HOME` before commit (public repo).

| File | Verified |
|---|---|
| `bluetit-status-disconnected.txt` | yes |
| `air-list-countries.txt` | yes (23 countries) |
| `air-list-country-notfound.txt` | yes (exit 1) |
| `air-list-servers-nl.txt` | yes — grammar reference for a later gate, no v1 parser |
| `credential-prompt.txt` | yes (exit 124, truncated at the prompt) |
| `help.txt` | yes |
| `bluetit-status-connected.txt` | **absent — Phase 02, needs login** |
| `air-key-list.txt` | **absent — Phase 02, needs login** |
