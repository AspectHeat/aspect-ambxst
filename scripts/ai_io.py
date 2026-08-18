#!/usr/bin/env python3
"""Stdin-based IO helpers for ambxst AI with no shell interpolation."""
from __future__ import annotations

import pathlib
import re
import signal
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
from html import unescape
from html.parser import HTMLParser


def write_file(path: str) -> None:
    target = pathlib.Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(sys.stdin.buffer.read())


def copy_clipboard() -> None:
    data = sys.stdin.buffer.read()
    subprocess.run(["wl-copy"], input=data, check=True)


def run_codex(model: str, reasoning_effort: str, cwd: str, sandbox: str, approval: str) -> None:
    codex_bin = shutil.which("codex")
    if not codex_bin:
        print("codex executable not found on PATH", file=sys.stderr)
        sys.exit(127)

    workdir = pathlib.Path(cwd).expanduser()
    if not workdir.exists():
        workdir = pathlib.Path.home()

    prompt = sys.stdin.read()
    with tempfile.NamedTemporaryFile(prefix="ambxst-codex-", suffix=".txt", delete=False) as handle:
        output_path = pathlib.Path(handle.name)

    command = [
        codex_bin,
        "exec",
        "--color",
        "never",
        "--skip-git-repo-check",
        "-m",
        model or "gpt-5.5",
        "-c",
        f'model_reasoning_effort="{reasoning_effort or "high"}"',
        "--sandbox",
        sandbox or "workspace-write",
        "--ask-for-approval",
        approval or "never",
        "-C",
        str(workdir),
        "--output-last-message",
        str(output_path),
        "-",
    ]

    result = subprocess.run(command, input=prompt, text=True, capture_output=True)
    output = ""
    try:
        output = output_path.read_text(encoding="utf-8").strip()
    finally:
        output_path.unlink(missing_ok=True)

    if not output:
        output = result.stdout.strip()

    if result.returncode != 0:
        error = result.stderr.strip() or result.stdout.strip() or f"codex exited with {result.returncode}"
        print(error, file=sys.stderr)
        sys.exit(result.returncode)

    print(output)


class DuckDuckGoHTMLParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.results: list[dict[str, str]] = []
        self._current: dict[str, str] | None = None
        self._capture: str | None = None
        self._parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attr = {name: value or "" for name, value in attrs}
        classes = attr.get("class", "")

        if tag == "a" and "result__a" in classes:
            self._current = {"title": "", "url": self._clean_url(attr.get("href", "")), "snippet": ""}
            self._capture = "title"
            self._parts = []
        elif self._current is not None and "result__snippet" in classes:
            self._capture = "snippet"
            self._parts = []

    def handle_endtag(self, tag: str) -> None:
        if self._capture == "title" and tag == "a" and self._current is not None:
            self._current["title"] = self._clean_text(" ".join(self._parts))
            self._capture = None
            self._parts = []
        elif self._capture == "snippet" and tag in ("a", "div") and self._current is not None:
            self._current["snippet"] = self._clean_text(" ".join(self._parts))
            if self._current.get("title") and self._current.get("url"):
                self.results.append(self._current)
            self._current = None
            self._capture = None
            self._parts = []

    def handle_data(self, data: str) -> None:
        if self._capture:
            self._parts.append(data)

    @staticmethod
    def _clean_text(text: str) -> str:
        return re.sub(r"\s+", " ", unescape(text)).strip()

    @staticmethod
    def _clean_url(url: str) -> str:
        url = unescape(url)
        if url.startswith("//duckduckgo.com/l/?"):
            parsed = urllib.parse.urlparse("https:" + url)
            query = urllib.parse.parse_qs(parsed.query)
            if query.get("uddg"):
                return query["uddg"][0]
        return url


def web_search(query: str, limit: int = 3) -> None:
    query = query.strip()
    if not query:
        print("No search query provided.", file=sys.stderr)
        sys.exit(2)

    url = "https://html.duckduckgo.com/html/?" + urllib.parse.urlencode({"q": query})
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) Ambxst/1.0",
            "Accept-Language": "en-US,en;q=0.9",
        },
    )

    def timeout_handler(signum, frame):
        raise TimeoutError("web search timed out")

    previous_handler = signal.signal(signal.SIGALRM, timeout_handler)
    signal.alarm(20)

    try:
        with urllib.request.urlopen(request, timeout=12) as response:
            html = response.read(1_000_000).decode("utf-8", errors="replace")
    except Exception as exc:
        print(f"Web search failed: {exc}", file=sys.stderr)
        sys.exit(1)
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, previous_handler)

    parser = DuckDuckGoHTMLParser()
    parser.feed(html)

    seen: set[str] = set()
    results: list[dict[str, str]] = []
    for result in parser.results:
        result_url = result.get("url", "")
        if not result_url or result_url in seen:
            continue
        seen.add(result_url)
        results.append(result)
        if len(results) >= limit:
            break

    if not results:
        print(f"No web results found for: {query}")
        return

    lines = [f"Web search results for: {query}", ""]
    for index, result in enumerate(results, start=1):
        lines.append(f"{index}. {result['title']}")
        lines.append(f"   URL: {result['url']}")
        if result.get("snippet"):
            snippet = result["snippet"][:500]
            lines.append(f"   Snippet: {snippet}")
        lines.append("")

    print("\n".join(lines).strip())


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(2)

    mode = sys.argv[1]
    if mode == "write":
        if len(sys.argv) < 3:
            sys.exit(2)
        write_file(sys.argv[2])
    elif mode == "clipboard":
        copy_clipboard()
    elif mode == "codex":
        if len(sys.argv) < 7:
            sys.exit(2)
        run_codex(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6])
    elif mode == "web_search":
        if len(sys.argv) < 3:
            sys.exit(2)
        web_search(" ".join(sys.argv[2:]))
    else:
        sys.exit(2)


if __name__ == "__main__":
    main()
