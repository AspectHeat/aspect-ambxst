#!/usr/bin/env python3
"""Shared paths and safe launch rules for Ambxst coding-agent integration."""

from __future__ import annotations

import json
import os
import shlex
import shutil
import subprocess
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
PROVIDER_NAMES = {
    "claude": "Claude Code",
    "codex": "Codex",
    "cursor": "Cursor",
    "opencode-go": "OpenCode Go",
}


def config_home() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")


def state_home() -> Path:
    return Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state")


def agent_state_path() -> Path:
    override = os.environ.get("AMBXST_AGENT_STATE_FILE")
    return Path(override) if override else config_home() / "ambxst" / "agents.json"


def capture_disabled_path() -> Path:
    override = os.environ.get("AMBXST_CRASH_CAPTURE_FLAG")
    return Path(override) if override else state_home() / "ambxst" / "crash-capture-off"


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def default_agent() -> str:
    provider = str(read_json(agent_state_path()).get("defaultAgent") or "")
    return provider if provider in PROVIDER_NAMES else ""


def provider_executable(provider: str) -> str:
    binary = "cursor-agent" if provider == "cursor" else "opencode" if provider == "opencode-go" else provider
    return shutil.which(binary) or ""


def provider_command(provider: str, prompt: str) -> list[str]:
    executable = provider_executable(provider)
    if not executable:
        raise RuntimeError(f"{PROVIDER_NAMES.get(provider, provider)} is not installed")
    if provider == "claude":
        return [executable, "--permission-mode", "plan", prompt]
    if provider == "codex":
        return [executable, "-s", "read-only", "-a", "untrusted", prompt]
    if provider == "cursor":
        return [executable, "--mode", "ask", prompt]
    if provider == "opencode-go":
        return [executable, "--prompt", prompt]
    raise RuntimeError(f"Unsupported agent: {provider}")


def working_directory() -> Path:
    configured = os.environ.get("AMBXST_AGENT_WORKDIR")
    if configured and Path(configured).is_dir():
        return Path(configured)
    for candidate in (Path.home() / "Projects", Path.home() / "Work", Path.home()):
        if candidate.is_dir():
            return candidate
    return Path.cwd()


def terminal_launch_command(agent_command: list[str]) -> list[str]:
    config = read_json(config_home() / "ambxst" / "config" / "general.json")
    terminal = str(os.environ.get("TERMINAL") or config.get("terminal") or "kitty")
    if not shutil.which(terminal):
        for fallback in ("kitty", "foot", "ghostty", "alacritty", "wezterm"):
            if shutil.which(fallback):
                terminal = fallback
                break
        else:
            raise RuntimeError("No configured terminal was found")
    if config.get("terminalAdvanced") is True:
        template = str(config.get("terminalCommand") or "$TERMINAL -e $COMMAND")
        rendered = template.replace("$TERMINAL", shlex.quote(terminal)).replace(
            "$COMMAND", shlex.join(agent_command)
        )
        return ["bash", "-lc", rendered]
    return [terminal, "-e", *agent_command]


def launch_agent(provider: str, prompt: str) -> None:
    command = terminal_launch_command(provider_command(provider, prompt))
    subprocess.Popen(
        command,
        cwd=working_directory(),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
