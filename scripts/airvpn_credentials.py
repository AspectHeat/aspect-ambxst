#!/usr/bin/env python3
"""Atomically update Goldcrest credentials from a single JSON line on stdin."""

import json
import os
import pwd
import sys
import tempfile
from pathlib import Path


def fail(message: str) -> None:
    print(json.dumps({"error": message}), file=sys.stderr, flush=True)
    raise SystemExit(1)


def main() -> None:
    # Goldcrest resolves the invoking user's home through getpwuid(), not $HOME. That distinction
    # is observable when Ambxst runs with a sandboxed HOME: writing $HOME/.config/goldcrest.rc
    # succeeds but Goldcrest reads the login user's real home and prompts again. Use the same
    # lookup here so the writer and CLI cannot disagree.
    account_home = Path(pwd.getpwuid(os.getuid()).pw_dir)
    path = account_home / ".config" / "goldcrest.rc"

    if len(sys.argv) == 2 and sys.argv[1] == "--path":
        print(path, flush=True)
        return
    if len(sys.argv) == 3 and sys.argv[1] == "--target":
        # Explicit target exists for isolated tests only; the QML service never uses it.
        path = Path(sys.argv[2]).expanduser()
    elif len(sys.argv) != 1:
        fail("usage: airvpn_credentials.py [--path | --target PATH]")

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
