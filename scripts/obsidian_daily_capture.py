#!/usr/bin/env python3
"""Obsidian daily note capture helper for the Ambxst notes widget.

Usage:
  obsidian_daily_capture.py path            — print today's daily note path
  obsidian_daily_capture.py ensure          — create daily note if missing
  obsidian_daily_capture.py append <text>   — append timestamped capture
"""

import os
import re
import sys
from datetime import datetime

VAULT = os.path.expanduser(os.environ.get("OBSIDIAN_VAULT", "~/Documents/vault"))
DAILY_DIR = os.environ.get("OBSIDIAN_DAILY_DIR", "200 - Logs")
HEADING = os.environ.get("OBSIDIAN_QUICK_NOTES_HEADING", "Quick Notes")


def _now():
    """Local wall-clock time, tz-aware, without hardcoding a zone."""
    return datetime.now().astimezone()


def today_path():
    date_str = _now().strftime("%Y-%m-%d")
    return os.path.join(VAULT, DAILY_DIR, f"{date_str}.md")


def _render_frontmatter(now):
    created = now.strftime("%Y-%m-%d %H:%M")
    return (
        "---\n"
        f"created: {created}\n"
        "modified: \n"
        "type: log\n"
        "tags: []\n"
        "status:\n"
        "related: []\n"
        "log-type: daily\n"
        'mood: " "\n'
        "---\n\n"
    )


def ensure_daily(path, now):
    if os.path.exists(path):
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(_render_frontmatter(now))


def _update_modified(text, now):
    ts = now.strftime("%Y-%m-%d %H:%M")
    # Only update if frontmatter block exists (starts with ---)
    if not text.startswith("---"):
        return text
    return re.sub(r"^(modified:)[ \t]*.*$", rf"\1 {ts}", text, count=1, flags=re.MULTILINE)


def append_capture(content):
    now = _now()
    path = today_path()
    ensure_daily(path, now)

    with open(path, "r", encoding="utf-8") as f:
        text = f.read()

    timestamp = now.strftime("%H:%M")
    heading_marker = f"## {HEADING}"
    capture_block = f"### {timestamp}\n{content.rstrip()}"

    m = re.search(r"^## " + re.escape(HEADING) + r"[ \t]*$", text, re.MULTILINE)

    if m:
        after_heading = text[m.end():]
        next_sec = re.search(r"^##[^#]", after_heading, re.MULTILINE)
        if next_sec:
            insert_at = m.end() + next_sec.start()
            before = text[:insert_at].rstrip("\n")
            after = text[insert_at:]
            text = f"{before}\n\n{capture_block}\n\n{after}"
        else:
            text = text.rstrip("\n") + f"\n\n{capture_block}\n"
    else:
        text = text.rstrip("\n") + f"\n\n{heading_marker}\n\n{capture_block}\n"

    text = _update_modified(text, now)

    with open(path, "w", encoding="utf-8") as f:
        f.write(text)

    print(path)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""

    if cmd == "path":
        print(today_path())
    elif cmd == "ensure":
        now = _now()
        path = today_path()
        ensure_daily(path, now)
        print(path)
    elif cmd == "append":
        content = sys.argv[2] if len(sys.argv) > 2 else ""
        if not content.strip():
            print("error: empty content", file=sys.stderr)
            sys.exit(1)
        append_capture(content)
    else:
        print(f"Usage: {sys.argv[0]} path|ensure|append '<content>'", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
