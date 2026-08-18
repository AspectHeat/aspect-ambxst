#!/usr/bin/env python3
"""Follow systemd-coredump journal events and hand them to the Ambxst shell."""

from __future__ import annotations

import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from agent_common import ROOT, capture_disabled_path, default_agent, provider_executable


COREDUMP_MESSAGE_ID = "fc2e22bc6ee647b6b90729ab34a250b1"


@dataclass(frozen=True)
class CrashEvent:
    pid: int
    uid: int
    comm: str
    executable: str
    signal: str
    happened_at: str

    @property
    def name(self) -> str:
        return Path(self.executable).name if self.executable.startswith("/") else self.comm


def event_from_journal(value: dict[str, Any]) -> CrashEvent | None:
    try:
        pid = int(value.get("COREDUMP_PID") or 0)
        uid = int(value.get("COREDUMP_UID", value.get("_UID", -1)))
    except (TypeError, ValueError):
        return None
    if pid <= 0 or uid < 0:
        return None
    raw_timestamp = value.get("__REALTIME_TIMESTAMP") or value.get("COREDUMP_TIMESTAMP") or 0
    try:
        happened_at = dt.datetime.fromtimestamp(float(raw_timestamp) / 1_000_000, dt.timezone.utc).astimezone().isoformat(timespec="seconds")
    except (OSError, OverflowError, TypeError, ValueError):
        happened_at = "unknown"
    return CrashEvent(
        pid=pid,
        uid=uid,
        comm=str(value.get("COREDUMP_COMM") or "unknown")[:128],
        executable=str(value.get("COREDUMP_EXE") or "unknown")[:4096],
        signal=str(value.get("COREDUMP_SIGNAL_NAME") or value.get("COREDUMP_SIGNAL") or "unknown")[:64],
        happened_at=happened_at,
    )


class DedupeWindow:
    def __init__(self, seconds: float = 60) -> None:
        self.seconds = seconds
        self.last_seen: dict[str, float] = {}

    def accepts(self, name: str, now: float | None = None) -> bool:
        current = time.monotonic() if now is None else now
        if current - self.last_seen.get(name, float("-inf")) < self.seconds:
            return False
        self.last_seen[name] = current
        return True


def should_announce(event: CrashEvent, ignore: re.Pattern[str] | None = None) -> bool:
    if event.uid != os.getuid() or capture_disabled_path().exists():
        return False
    if event.name.startswith(("ambxst-crash", "agent_crash", "crash_watch")):
        return False
    if ignore and ignore.search(event.name):
        return False
    provider = default_agent()
    return bool(provider and provider_executable(provider))


def deliver(event: CrashEvent) -> None:
    cli = ROOT / "cli.sh"
    attempts = int(os.environ.get("AMBXST_CRASH_DELIVERY_ATTEMPTS") or 60)
    delay = float(os.environ.get("AMBXST_CRASH_DELIVERY_DELAY") or 5)
    command = [
        str(cli),
        "crash-notify",
        str(event.pid),
        event.comm,
        event.executable,
        event.signal,
        event.happened_at,
    ]
    for _ in range(max(1, attempts)):
        result = subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        if result.returncode == 0:
            return
        time.sleep(max(0.1, delay))
    print(f"ambxst-crash-watch: shell unavailable; notification expired for {event.name} ({event.pid})", file=sys.stderr)


def main() -> int:
    if not shutil.which("journalctl") or not shutil.which("coredumpctl"):
        print("ambxst-crash-watch: systemd-coredump tools are unavailable", file=sys.stderr)
        return 1
    ignore_text = os.environ.get("AMBXST_CRASH_IGNORE") or ""
    try:
        ignore = re.compile(ignore_text) if ignore_text else None
    except re.error as error:
        print(f"ambxst-crash-watch: invalid AMBXST_CRASH_IGNORE: {error}", file=sys.stderr)
        return 2
    dedupe = DedupeWindow(float(os.environ.get("AMBXST_CRASH_DEDUPE_SECONDS") or 60))
    process = subprocess.Popen(
        ["journalctl", "--follow", "--lines=0", "--output=json", f"MESSAGE_ID={COREDUMP_MESSAGE_ID}"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    assert process.stdout is not None
    for raw in process.stdout:
        try:
            value = json.loads(raw)
        except ValueError:
            continue
        event = event_from_journal(value) if isinstance(value, dict) else None
        if not event or not should_announce(event, ignore) or not dedupe.accepts(event.name):
            continue
        threading.Thread(target=deliver, args=(event,), daemon=True).start()
    return process.wait()
if __name__ == "__main__":
    raise SystemExit(main())
