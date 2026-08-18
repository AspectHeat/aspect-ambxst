#!/usr/bin/env python3
"""Install, inspect, and toggle Ambxst crash capture and shared agent skills."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

from agent_common import (
    PROVIDER_NAMES,
    ROOT,
    agent_home,
    agent_state_path,
    capture_disabled_path,
    config_home,
    default_agent,
    provider_executable,
)


SKILL_NAMES = ("ambxst", "diagnose-crash")
UNIT_MARKER = "# Managed by Aspect Ambxst crash diagnostics"
SKILL_MARKER = ".ambxst-managed"


def isolated_session() -> bool:
    """Return true when the shell is running with the development lab HOME."""
    return bool(os.environ.get("AMBXST_AGENT_DATA_HOME"))


def skill_directories() -> list[Path]:
    home = agent_home()
    return [
        home / ".agents" / "skills",
        home / ".claude" / "skills",
        home / ".codex" / "skills",
        home / ".cursor" / "skills",
        config_home() / "opencode" / "skills",
    ]


def unit_source() -> Path:
    return ROOT / "assets" / "systemd" / "user" / "ambxst-crash-watch.service"


def unit_target() -> Path:
    override = os.environ.get("AMBXST_CRASH_UNIT_PATH")
    return Path(override) if override else config_home() / "systemd" / "user" / unit_source().name


def safe_symlink(source: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.is_symlink():
        if target.resolve(strict=False) == source.resolve():
            return
        previous_source = target.resolve(strict=False)
        if not ((previous_source / SKILL_MARKER).is_file() and (source / SKILL_MARKER).is_file()):
            raise RuntimeError(f"Refusing to replace existing symlink: {target}")
        target.unlink()
    elif target.exists():
        raise RuntimeError(f"Refusing to replace existing path: {target}")
    target.symlink_to(source)


def systemd_quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def rendered_unit() -> str:
    python = shutil.which("python3") or sys.executable
    watcher = ROOT / "scripts" / "crash_watch.py"
    content = unit_source().read_text(encoding="utf-8")
    command = f"ExecStart={systemd_quote(python)} {systemd_quote(str(watcher))}"
    return content.replace("ExecStart=/usr/bin/env ambxst crash-watch", command)


def install_unit() -> None:
    target = unit_target()
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.is_symlink():
        if target.resolve(strict=False) != unit_source().resolve():
            raise RuntimeError(f"Refusing to replace existing symlink: {target}")
        target.unlink()
    elif target.exists():
        existing = target.read_text(encoding="utf-8", errors="replace")
        if UNIT_MARKER not in existing:
            raise RuntimeError(f"Refusing to replace existing unit: {target}")
    content = rendered_unit()
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{target.name}.", dir=target.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as temporary:
            temporary.write(content)
        os.replace(temporary_name, target)
    finally:
        try:
            Path(temporary_name).unlink()
        except FileNotFoundError:
            pass


def run_systemctl(*arguments: str, check: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["systemctl", "--user", *arguments],
        capture_output=True,
        text=True,
        check=check,
    )


def install_skills() -> None:
    source_root = ROOT / "assets" / "agents" / "skills"
    for directory in skill_directories():
        for name in SKILL_NAMES:
            source = source_root / name
            if not (source / "SKILL.md").is_file():
                raise RuntimeError(f"Missing shipped skill: {name}")
            safe_symlink(source, directory / name)


def set_capture(enabled: bool) -> None:
    flag = capture_disabled_path()
    if enabled:
        flag.unlink(missing_ok=True)
        result = run_systemctl("start", unit_source().name)
    else:
        flag.parent.mkdir(parents=True, exist_ok=True)
        flag.touch(mode=0o600, exist_ok=True)
        result = run_systemctl("stop", unit_source().name)
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or "systemctl failed"
        raise RuntimeError(detail)


def write_default_agent(provider: str) -> None:
    path = agent_state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as temporary:
            json.dump({"defaultAgent": provider}, temporary, indent=2)
            temporary.write("\n")
        os.replace(temporary_name, path)
    finally:
        try:
            Path(temporary_name).unlink()
        except FileNotFoundError:
            pass


def install(provider_override: str = "") -> None:
    provider = provider_override or default_agent()
    if not provider:
        raise RuntimeError("Choose a default coding agent in Dashboard → Agents before setup")
    if provider not in PROVIDER_NAMES:
        raise RuntimeError(f"Unsupported coding agent: {provider}")
    if not provider_executable(provider):
        raise RuntimeError(f"{PROVIDER_NAMES[provider]} is not installed")
    if provider_override:
        write_default_agent(provider)
    install_skills()
    install_unit()
    capture_disabled_path().unlink(missing_ok=True)
    run_systemctl("daemon-reload", check=True)
    run_systemctl("enable", "--now", unit_source().name, check=True)


def status() -> dict[str, Any]:
    target = unit_target()
    try:
        unit_installed = target.is_file() and target.read_text(encoding="utf-8") == rendered_unit()
    except OSError:
        unit_installed = False
    skills = 0
    total = len(skill_directories()) * len(SKILL_NAMES)
    source_root = ROOT / "assets" / "agents" / "skills"
    for directory in skill_directories():
        for name in SKILL_NAMES:
            target_skill = directory / name
            if target_skill.is_symlink() and target_skill.resolve(strict=False) == (source_root / name).resolve():
                skills += 1
    active = run_systemctl("is-active", "--quiet", unit_source().name).returncode == 0 if unit_installed else False
    enabled = not capture_disabled_path().exists()
    return {
        "available": bool(shutil.which("coredumpctl")),
        "installed": unit_installed,
        "enabled": enabled,
        "running": active,
        "skillsInstalled": skills == total,
        "skillLinks": skills,
        "skillLinksExpected": total,
        "defaultAgent": default_agent(),
        "isolated": isolated_session(),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("status")
    install_parser = subparsers.add_parser("install")
    install_parser.add_argument("--provider", choices=tuple(PROVIDER_NAMES))
    toggle = subparsers.add_parser("toggle")
    toggle.add_argument("state", choices=("on", "off"))
    subparsers.add_parser("install-skills")
    args = parser.parse_args()
    try:
        if args.command == "install":
            install(args.provider or "")
        elif args.command == "toggle":
            if not status()["installed"]:
                raise RuntimeError("Agent integration is not installed")
            set_capture(args.state == "on")
        elif args.command == "install-skills":
            install_skills()
        print(json.dumps(status(), separators=(",", ":")))
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"agent integration: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
