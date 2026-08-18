#!/usr/bin/env python3
"""Launch the selected coding agent against a retained systemd-coredump PID."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

from agent_common import PROVIDER_NAMES, ROOT, default_agent, launch_agent


def coredump_record(pid: int) -> dict[str, Any]:
    process = subprocess.run(
        ["coredumpctl", "info", str(pid), "--json=short", "--no-pager"],
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    if process.returncode != 0:
        raise RuntimeError(f"No retained coredump was found for PID {pid}")
    try:
        value = json.loads(process.stdout)
    except ValueError as error:
        raise RuntimeError("coredumpctl returned an unreadable record") from error
    if not isinstance(value, dict):
        raise RuntimeError("coredumpctl returned an unreadable record")
    owner = value.get("OwnerUID", value.get("UID"))
    if owner is not None and int(owner) != os.getuid():
        raise RuntimeError("That coredump belongs to another user")
    return value


def record_time(record: dict[str, Any]) -> str:
    try:
        timestamp = float(record.get("Timestamp") or 0) / 1_000_000
        return dt.datetime.fromtimestamp(timestamp, dt.timezone.utc).astimezone().isoformat(timespec="seconds")
    except (OSError, OverflowError, TypeError, ValueError):
        return "unknown"


def diagnostic_prompt(pid: int, record: dict[str, Any], supplied: argparse.Namespace) -> str:
    executable = str(supplied.exe or record.get("Executable") or "unknown")
    process_name = str(supplied.comm or (Path(executable).name if executable != "unknown" else record.get("Command") or "unknown"))
    signal = str(supplied.signal or record.get("SignalName") or record.get("Signal") or "unknown")
    happened_at = str(supplied.time or record_time(record))
    skill = ROOT / "assets" / "agents" / "skills" / "diagnose-crash" / "SKILL.md"
    return f"""A process crashed on this Aspect Ambxst machine. Diagnose it without changing the system.

systemd-coredump record:
  process: {process_name}
  PID: {pid}
  executable: {executable}
  signal: {signal}
  time: {happened_at}

Use the diagnose-crash skill. If this harness did not discover the skill, read and follow it directly:
  {skill}

Establish facts from coredumpctl and the journal, distinguish evidence from inference, assess recurrence, and say whether an upstream report is justified. Do not apply fixes or upload the core."""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pid", type=int)
    parser.add_argument("--comm", default="")
    parser.add_argument("--exe", default="")
    parser.add_argument("--signal", default="")
    parser.add_argument("--time", default="")
    parser.add_argument("--dry-run", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.pid <= 0:
        parser.error("PID must be positive")
    provider = default_agent()
    if not provider:
        print("No default coding agent is selected. Choose one in Dashboard → Agents.", file=sys.stderr)
        return 2
    try:
        record = coredump_record(args.pid)
        prompt = diagnostic_prompt(args.pid, record, args)
        if args.dry_run:
            print(json.dumps({"provider": provider, "providerName": PROVIDER_NAMES[provider], "pid": args.pid}))
            return 0
        launch_agent(provider, prompt)
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"ambxst agent crash: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
