#!/usr/bin/env python3
"""Atomically update Goldcrest credentials from a single JSON line on stdin."""

import json
import os
import sys
import tempfile
from pathlib import Path


def fail(message: str) -> None:
    print(json.dumps({"error": message}), file=sys.stderr, flush=True)
    raise SystemExit(1)


def main() -> None:
    if len(sys.argv) != 2:
        fail("expected the Goldcrest run-control path")

    try:
        payload = json.loads(sys.stdin.readline())
    except (json.JSONDecodeError, OSError) as error:
        fail(f"could not read credentials: {error}")

    username = str(payload.get("username", "")).strip()
    password = str(payload.get("password", ""))
    if not username or not password:
        fail("username and password are required")
    if any(character in username or character in password for character in "\r\n"):
        fail("credentials cannot contain line breaks")

    path = Path(sys.argv[1]).expanduser()
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)

    try:
        existing = path.read_text(encoding="utf-8") if path.exists() else ""
    except OSError as error:
        fail(f"could not read {path}: {error}")

    kept_lines = []
    for line in existing.splitlines():
        directive = line.strip().split(None, 1)[0].lower() if line.strip() else ""
        if directive not in {"air-user", "air-password"}:
            kept_lines.append(line)

    if kept_lines and kept_lines[-1] != "":
        kept_lines.append("")
    kept_lines.extend((f"air-user {username}", f"air-password {password}"))
    contents = "\n".join(kept_lines) + "\n"

    temporary_name = ""
    try:
        descriptor, temporary_name = tempfile.mkstemp(prefix=".goldcrest.rc.", dir=path.parent)
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as temporary:
            temporary.write(contents)
            temporary.flush()
            os.fsync(temporary.fileno())
        os.replace(temporary_name, path)
        temporary_name = ""
    except OSError as error:
        fail(f"could not save {path}: {error}")
    finally:
        if temporary_name:
            try:
                os.unlink(temporary_name)
            except OSError:
                pass

    print(json.dumps({"status": "ok", "username": username}), flush=True)


if __name__ == "__main__":
    main()
