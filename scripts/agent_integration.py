#!/usr/bin/env python3
"""Install, inspect, and toggle Ambxst crash capture and shared agent skills."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

from agent_common import (
    PROVIDER_NAMES,
    ROOT,
    capture_disabled_path,
    config_home,
    default_agent,
    provider_executable,
)


SKILL_NAMES = ("ambxst", "diagnose-crash")


def isolated_session() -> bool:
    """Return true when the shell is running with the development lab HOME."""
    return bool(os.environ.get("AMBXST_AGENT_DATA_HOME"))


def require_live_session() -> None:
    if isolated_session():
        raise RuntimeError("Run 'ambxst agent setup' from a normal terminal, outside the isolated lab")


def skill_directories() -> list[Path]:
    home = Path.home()
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
        raise RuntimeError(f"Refusing to replace existing symlink: {target}")
    elif target.exists():
        raise RuntimeError(f"Refusing to replace existing path: {target}")
    target.symlink_to(source)


def run_systemctl(*arguments: str, check: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["systemctl", "--user", *arguments],
        capture_output=True,
        text=True,
        check=check,
    )


def install_skills() -> None:
    require_live_session()
    source_root = ROOT / "assets" / "agents" / "skills"
    for directory in skill_directories():
        for name in SKILL_NAMES:
            source = source_root / name
            if not (source / "SKILL.md").is_file():
                raise RuntimeError(f"Missing shipped skill: {name}")
            safe_symlink(source, directory / name)


def set_capture(enabled: bool) -> None:
    require_live_session()
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


def install() -> None:
    provider = default_agent()
    if not provider:
        raise RuntimeError("Choose a default coding agent in Dashboard → Agents before setup")
    if not provider_executable(provider):
        raise RuntimeError(f"{PROVIDER_NAMES[provider]} is not installed")
    install_skills()
    safe_symlink(unit_source(), unit_target())
    capture_disabled_path().unlink(missing_ok=True)
    run_systemctl("daemon-reload", check=True)
    run_systemctl("enable", "--now", unit_source().name, check=True)


def status() -> dict[str, Any]:
    target = unit_target()
    source = unit_source().resolve()
    unit_installed = target.is_symlink() and target.resolve(strict=False) == source
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
    subparsers.add_parser("install")
    toggle = subparsers.add_parser("toggle")
    toggle.add_argument("state", choices=("on", "off"))
    subparsers.add_parser("install-skills")
    args = parser.parse_args()
    try:
        if args.command == "install":
            install()
        elif args.command == "toggle":
            if not unit_target().is_symlink():
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
