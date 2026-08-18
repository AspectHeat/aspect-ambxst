#!/usr/bin/env python3
"""Collect coding-agent subscription limits and local usage as JSON.

The QML panel deliberately knows nothing about credential files, provider APIs,
or agent transcript formats.  This process reads those details locally and
prints a display-safe, provider-neutral record.  Credentials never leave this
process except in the provider request they authenticate.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import os
import select
import shutil
import sqlite3
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Callable


SCHEMA_VERSION = 1
CLAUDE_USAGE_ENDPOINT = "https://api.anthropic.com/api/oauth/usage"
CURSOR_API_BASE = "https://api2.cursor.sh/aiserver.v1.DashboardService"
OPENCODE_GO_LIMITS = {"rolling": 12.0, "weekly": 30.0, "monthly": 60.0}
NORMAL_SCAN_CACHE_SECONDS = 20
LIMITS_ONLY_SCAN_CACHE_SECONDS = 900


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def utc_iso() -> str:
    return utc_now().isoformat()


def local_date(value: Any = None) -> str:
    if value is None:
        return dt.datetime.now().strftime("%Y-%m-%d")
    if isinstance(value, (int, float)):
        try:
            seconds = float(value) / 1000 if float(value) > 10_000_000_000 else float(value)
            return dt.datetime.fromtimestamp(seconds).strftime("%Y-%m-%d")
        except (OSError, OverflowError, ValueError):
            return local_date()
    try:
        parsed = dt.datetime.fromisoformat(str(value).strip().replace("Z", "+00:00"))
        if parsed.tzinfo is not None:
            parsed = parsed.astimezone()
        return parsed.strftime("%Y-%m-%d")
    except (TypeError, ValueError):
        return local_date()


def number(value: Any) -> int:
    try:
        parsed = float(value or 0)
        return round(parsed) if math.isfinite(parsed) else 0
    except (TypeError, ValueError):
        return 0


def decimal_number(value: Any) -> float:
    try:
        parsed = float(value or 0)
        return parsed if math.isfinite(parsed) else 0.0
    except (TypeError, ValueError):
        return 0.0


def recent_dates() -> list[str]:
    today = dt.datetime.now().date()
    return [(today - dt.timedelta(days=offset)).isoformat() for offset in range(6, -1, -1)]


def empty_token_bucket() -> dict[str, int]:
    return {
        "inputTokens": 0,
        "outputTokens": 0,
        "cacheReadInputTokens": 0,
        "cacheCreationInputTokens": 0,
    }


class UsageAccumulator:
    def __init__(self) -> None:
        self.today = local_date()
        self.recent = {day: {"date": day, "totalTokens": 0} for day in recent_dates()}
        self.model_usage: dict[str, dict[str, int]] = {}
        self.sessions: set[str] = set()
        self.today_sessions: set[str] = set()
        self.active_dates: set[str] = set()
        self.today_prompts = 0
        self.total_prompts = 0
        self.today_total_tokens = 0

    def add(
        self,
        day: str,
        session: str,
        model: str,
        input_tokens: int,
        output_tokens: int,
        cache_read: int = 0,
        cache_write: int = 0,
    ) -> None:
        total = input_tokens + output_tokens + cache_read + cache_write
        if total <= 0:
            return
        model = model or "unknown"
        session = session or "unknown"
        bucket = self.model_usage.setdefault(model, empty_token_bucket())
        bucket["inputTokens"] += input_tokens
        bucket["outputTokens"] += output_tokens
        bucket["cacheReadInputTokens"] += cache_read
        bucket["cacheCreationInputTokens"] += cache_write
        self.sessions.add(session)
        self.active_dates.add(day)
        self.total_prompts += 1
        if day in self.recent:
            self.recent[day]["totalTokens"] += total
        if day == self.today:
            self.today_sessions.add(session)
            self.today_prompts += 1
            self.today_total_tokens += total

    def record(self) -> dict[str, Any]:
        return {
            "todayPrompts": self.today_prompts,
            "todaySessions": len(self.today_sessions),
            "todayTotalTokens": self.today_total_tokens,
            "recentDays": list(self.recent.values()),
            "totalPrompts": self.total_prompts,
            "totalSessions": len(self.sessions),
            "activeDays": len(self.active_dates),
            "modelUsage": self.model_usage,
        }


def cache_root() -> Path:
    root = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "ambxst" / "agent-usage"
    root.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(root, 0o700)
    except OSError:
        pass
    return root


def agent_home() -> Path:
    """Real account root when the shell itself runs under an isolated HOME."""
    return Path(os.environ.get("AMBXST_AGENT_DATA_HOME") or Path.home()).expanduser()


def agent_config_home() -> Path:
    if os.environ.get("AMBXST_AGENT_DATA_HOME"):
        return agent_home() / ".config"
    return Path(os.environ.get("XDG_CONFIG_HOME") or agent_home() / ".config").expanduser()


def agent_data_home() -> Path:
    if os.environ.get("AMBXST_AGENT_DATA_HOME"):
        return agent_home() / ".local" / "share"
    return Path(os.environ.get("XDG_DATA_HOME") or agent_home() / ".local" / "share").expanduser()


def empty_stats() -> dict[str, Any]:
    return UsageAccumulator().record()


def read_json(path: Path) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else None
    except (OSError, ValueError):
        return None


def write_private_json(path: Path, payload: dict[str, Any]) -> None:
    descriptor, tmp_name = tempfile.mkstemp(dir=path.parent, prefix=path.name + ".", suffix=".tmp")
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"), sort_keys=True)
            handle.write("\n")
        os.chmod(tmp_path, 0o600)
        tmp_path.replace(path)
    except BaseException:
        tmp_path.unlink(missing_ok=True)
        raise


def cached_stats(provider: str, max_age: float, scan: Callable[[], dict[str, Any]]) -> dict[str, Any]:
    path = cache_root() / f"{provider}-stats.json"
    cached = read_json(path)
    if cached and cached.get("scanDate") == local_date() and max_age > 0:
        try:
            age = time.time() - path.stat().st_mtime
            if 0 <= age <= max_age and isinstance(cached.get("stats"), dict):
                return cached["stats"]
        except OSError:
            pass
    stats = scan()
    try:
        write_private_json(path, {"scanDate": local_date(), "stats": stats})
    except OSError as error:
        print(f"agent-usage: could not cache {provider} stats: {error}", file=os.sys.stderr)
    return stats


def normalize_reset_at(value: Any) -> str:
    if value is None or str(value).strip() == "":
        return ""
    raw = str(value).strip()
    if raw.isdigit():
        timestamp = int(raw)
        if timestamp > 10_000_000_000:
            timestamp /= 1000
        try:
            return dt.datetime.fromtimestamp(timestamp, dt.timezone.utc).isoformat()
        except (OSError, OverflowError, ValueError):
            return raw
    try:
        return dt.datetime.fromisoformat(raw.replace("Z", "+00:00")).isoformat()
    except ValueError:
        return raw


def normalize_utilization(value: Any, percentage_scale: bool) -> float:
    try:
        parsed = float(str(value).strip().replace("%", ""))
    except (TypeError, ValueError):
        return -1
    if not math.isfinite(parsed) or parsed < 0:
        return -1
    if percentage_scale or parsed > 1:
        parsed /= 100
    return min(1.0, parsed)


def utilization_number(value: Any) -> float:
    try:
        return float(str(value).strip().replace("%", ""))
    except (TypeError, ValueError):
        return float("nan")


def plan_label(tier: str, subscription: str) -> str:
    import re

    match = re.search(r"max_(\d+x)", tier or "", re.IGNORECASE)
    if match:
        return "Max " + match.group(1)
    return subscription[:1].upper() + subscription[1:] if subscription else ""


def claude_config_dir() -> Path:
    configured = os.environ.get("CLAUDE_CONFIG_DIR")
    return Path(os.path.expandvars(os.path.expanduser(configured))) if configured else agent_home() / ".claude"


def codex_home() -> Path:
    return Path(os.environ.get("CODEX_HOME") or agent_home() / ".codex").expanduser()


def claude_login() -> tuple[str, int, str]:
    credentials = read_json(claude_config_dir() / ".credentials.json") or {}
    login = credentials.get("claudeAiOauth")
    if not isinstance(login, dict):
        return "", 0, ""
    return (
        str(login.get("accessToken") or ""),
        number(login.get("expiresAt")),
        plan_label(str(login.get("rateLimitTier") or ""), str(login.get("subscriptionType") or "")),
    )


def claude_limits_from_payload(payload: dict[str, Any]) -> list[dict[str, Any]]:
    session = payload.get("five_hour") if isinstance(payload.get("five_hour"), dict) else None
    weekly = payload.get("seven_day_oauth_apps")
    if not isinstance(weekly, dict):
        weekly = payload.get("seven_day") if isinstance(payload.get("seven_day"), dict) else None
    raw_values = [bucket.get("utilization") for bucket in (session, weekly) if bucket]
    scoped = payload.get("limits") if isinstance(payload.get("limits"), list) else []
    raw_values.extend(entry.get("percent") for entry in scoped if isinstance(entry, dict))
    percentage_scale = any(utilization_number(value) >= 1 for value in raw_values)
    limits: list[dict[str, Any]] = []
    for title, label, bucket in (
        ("Session", "Session (5-hour)", session),
        ("Weekly", "Weekly (7-day)", weekly),
    ):
        if not bucket:
            continue
        percent = normalize_utilization(bucket.get("utilization"), percentage_scale)
        if percent >= 0:
            limits.append(
                {
                    "title": title,
                    "label": label,
                    "percent": percent,
                    "resetsAt": normalize_reset_at(bucket.get("resets_at")),
                }
            )
    seen: set[tuple[str, str]] = set()
    for entry in scoped:
        if not isinstance(entry, dict):
            continue
        scope = entry.get("scope") if isinstance(entry.get("scope"), dict) else {}
        model = scope.get("model") if isinstance(scope.get("model"), dict) else {}
        name = str(model.get("display_name") or model.get("id") or "").strip()
        kind = str(entry.get("kind") or "").strip()
        if not name or (name, kind) in seen:
            continue
        percent = normalize_utilization(entry.get("percent"), percentage_scale)
        if percent < 0:
            continue
        seen.add((name, kind))
        window = "Weekly" if "week" in kind or "day" in kind else "Session" if "hour" in kind else ""
        title = f"{name} {window}".strip()
        limits.append(
            {
                "title": title,
                "label": title,
                "percent": percent,
                "resetsAt": normalize_reset_at(entry.get("resets_at")),
            }
        )
    return limits


def cached_open_limits(path: Path) -> list[dict[str, Any]]:
    cached = read_json(path) or {}
    limits = cached.get("limits") if isinstance(cached.get("limits"), list) else []
    now = utc_now()
    valid: list[dict[str, Any]] = []
    for entry in limits:
        if not isinstance(entry, dict):
            continue
        reset = str(entry.get("resetsAt") or "")
        if not reset:
            valid.append(entry)
            continue
        try:
            parsed = dt.datetime.fromisoformat(reset.replace("Z", "+00:00"))
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=dt.timezone.utc)
            if parsed > now:
                valid.append(entry)
        except ValueError:
            valid.append(entry)
    return valid


def collect_claude_limits(force: bool) -> dict[str, Any]:
    result: dict[str, Any] = {"limits": [], "usageStatusText": "", "authHelpText": ""}
    access_token, expires_at_ms, tier = claude_login()
    result["tierLabel"] = tier
    cache_path = cache_root() / "claude-limits.json"
    fallback = cached_open_limits(cache_path)
    if not access_token:
        result.update(
            limits=fallback,
            usageStatusText="Sign in required",
            authHelpText="Run `claude auth login` to show authoritative Claude limits.",
        )
        return result
    if expires_at_ms and expires_at_ms <= time.time() * 1000:
        result.update(
            limits=fallback,
            usageStatusText="Sign-in expired",
            authHelpText="Start Claude Code or run `claude auth login` to refresh the saved sign-in.",
        )
        return result
    cached = read_json(cache_path) or {}
    fetched_at = number(cached.get("fetchedAtMs")) / 1000
    if fallback and not force and time.time() - fetched_at < 15:
        result["limits"] = fallback
        return result
    request = urllib.request.Request(
        CLAUDE_USAGE_ENDPOINT,
        headers={
            "Authorization": "Bearer " + access_token,
            "anthropic-beta": "oauth-2025-04-20",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            payload = json.loads(response.read().decode("utf-8", errors="replace"))
        limits = claude_limits_from_payload(payload if isinstance(payload, dict) else {})
        if limits:
            result["limits"] = limits
            write_private_json(cache_path, {"fetchedAtMs": round(time.time() * 1000), "limits": limits})
        else:
            result.update(
                limits=fallback,
                usageStatusText="Limits unavailable",
                authHelpText="Anthropic returned no recognizable usage windows; local activity is still shown.",
            )
    except urllib.error.HTTPError as error:
        result.update(
            limits=fallback,
            usageStatusText="Limits unavailable",
            authHelpText=f"Anthropic's usage endpoint returned status {error.code}; local activity is still shown.",
        )
    except (OSError, TimeoutError, urllib.error.URLError):
        result.update(
            limits=fallback,
            usageStatusText="Offline — showing cached limits" if fallback else "Claude limits unavailable",
            authHelpText="Couldn't reach Anthropic's usage endpoint; Ambxst will retry shortly.",
            retryAdvised=True,
        )
    return result


def claude_usage_value(usage: dict[str, Any], snake: str, camel: str) -> int:
    return number(usage.get(snake, usage.get(camel, 0)))


def scan_claude_stats() -> dict[str, Any]:
    accumulator = UsageAccumulator()
    projects = claude_config_dir() / "projects"
    seen: set[str] = set()
    if projects.is_dir():
        for path in projects.rglob("*.jsonl"):
            try:
                with path.open(encoding="utf-8", errors="replace") as handle:
                    for line_number, raw in enumerate(handle, 1):
                        if '"usage"' not in raw:
                            continue
                        try:
                            entry = json.loads(raw)
                        except ValueError:
                            continue
                        message = entry.get("message") if isinstance(entry.get("message"), dict) else {}
                        if entry.get("type") != "assistant" and message.get("role") != "assistant":
                            continue
                        usage = message.get("usage") or entry.get("usage")
                        if not isinstance(usage, dict):
                            continue
                        message_id = str(message.get("id") or entry.get("messageId") or "")
                        unique = message_id or f"{path}:{entry.get('uuid') or line_number}"
                        if unique in seen:
                            continue
                        seen.add(unique)
                        accumulator.add(
                            local_date(entry.get("timestamp") or message.get("timestamp")),
                            str(entry.get("sessionId") or path),
                            str(message.get("model") or entry.get("model") or "claude"),
                            claude_usage_value(usage, "input_tokens", "inputTokens"),
                            claude_usage_value(usage, "output_tokens", "outputTokens"),
                            claude_usage_value(usage, "cache_read_input_tokens", "cacheReadInputTokens"),
                            claude_usage_value(usage, "cache_creation_input_tokens", "cacheCreationInputTokens"),
                        )
            except OSError:
                continue
    return accumulator.record()


def collect_claude(force: bool, scan_age: float) -> dict[str, Any]:
    stats = cached_stats("claude", scan_age, scan_claude_stats)
    limits = collect_claude_limits(force)
    record: dict[str, Any] = {
        "schemaVersion": SCHEMA_VERSION,
        "id": "claude",
        "name": "Claude Code",
        "updatedAt": utc_iso(),
        "installed": shutil.which("claude") is not None,
        "ready": number(stats.get("totalPrompts")) > 0 or bool(limits.get("limits")),
        "hasLocalStats": True,
        "localStatsWindow": "All time",
    }
    record.update(stats)
    record.update(limits)
    return record


def scan_codex_stats() -> dict[str, Any]:
    accumulator = UsageAccumulator()
    home = codex_home()
    cutoff = time.time() - 30 * 24 * 60 * 60
    files: list[Path] = []
    for root in (home / "sessions", home / "archived_sessions"):
        if not root.is_dir():
            continue
        for path in root.rglob("*.jsonl"):
            try:
                if path.stat().st_mtime >= cutoff:
                    files.append(path)
            except OSError:
                continue
    for path in files:
        current_model = "codex"
        try:
            with path.open(encoding="utf-8", errors="replace") as handle:
                for raw in handle:
                    try:
                        entry = json.loads(raw)
                    except ValueError:
                        continue
                    payload = entry.get("payload") or entry
                    if entry.get("type") == "turn_context" and isinstance(payload, dict):
                        current_model = str(payload.get("model") or payload.get("model_slug") or current_model)
                        continue
                    if entry.get("type") == "response_item" and isinstance(payload, dict):
                        payload = payload.get("payload") or payload
                    if not isinstance(payload, dict) or payload.get("type") != "token_count":
                        continue
                    usage = (payload.get("info") or {}).get("last_token_usage") or {}
                    cache_read = number(usage.get("cached_input_tokens"))
                    cache_write = number(usage.get("cache_write_input_tokens"))
                    input_tokens = max(0, number(usage.get("input_tokens")) - cache_read - cache_write)
                    accumulator.add(
                        local_date(entry.get("timestamp") or path.stat().st_mtime),
                        str(path),
                        current_model,
                        input_tokens,
                        number(usage.get("output_tokens")),
                        cache_read,
                        cache_write,
                    )
        except OSError:
            continue
    return accumulator.record()


def codex_rpc_request(
    process: subprocess.Popen[str], request_id: int, method: str, params: dict[str, Any] | None = None, timeout: int = 8
) -> dict[str, Any]:
    assert process.stdin is not None and process.stdout is not None
    process.stdin.write(json.dumps({"id": request_id, "method": method, "params": params or {}}) + "\n")
    process.stdin.flush()
    deadline = time.time() + timeout
    while time.time() < deadline:
        ready, _, _ = select.select([process.stdout], [], [], 0.25)
        if not ready:
            continue
        line = process.stdout.readline()
        if not line:
            break
        try:
            message = json.loads(line)
        except ValueError:
            continue
        if message.get("id") == request_id:
            if message.get("error"):
                raise RuntimeError(method)
            return message
    raise TimeoutError(method)


def codex_limit_window(window: Any) -> dict[str, Any] | None:
    if not isinstance(window, dict) or window.get("usedPercent") is None:
        return None
    duration = number(window.get("windowDurationMins"))
    if duration == 10080:
        title, label = "Weekly", "Weekly (7-day)"
    elif duration and duration % 60 == 0:
        title, label = "Session", f"Session ({duration // 60}-hour)"
    elif duration:
        title, label = "Session", f"Session ({duration}-minute)"
    else:
        title = label = "Limit"
    return {
        "title": title,
        "label": label,
        "percent": min(1.0, max(0.0, float(window.get("usedPercent"))) / 100),
        "resetsAt": normalize_reset_at(window.get("resetsAt")),
    }


def codex_runtime_environment() -> dict[str, str]:
    environment = os.environ.copy()
    home = str(agent_home())
    additions = [f"{home}/.local/bin", f"{home}/.npm-global/bin", f"{home}/.local/share/mise/shims"]
    environment["PATH"] = os.pathsep.join([environment.get("PATH", ""), *additions])
    environment.setdefault("CODEX_HOME", str(codex_home()))
    return environment


def collect_codex_limits() -> dict[str, Any]:
    result: dict[str, Any] = {"limits": [], "tierLabel": "", "usageStatusText": "", "authHelpText": ""}
    command = shutil.which("codex", path=codex_runtime_environment()["PATH"])
    if not command:
        result.update(usageStatusText="Codex unavailable", authHelpText="Install Codex to read subscription limits.")
        return result
    process: subprocess.Popen[str] | None = None
    try:
        process = subprocess.Popen(
            [command, "-s", "read-only", "-a", "untrusted", "app-server"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            env=codex_runtime_environment(),
        )
        codex_rpc_request(
            process,
            1,
            "initialize",
            {"clientInfo": {"name": "ambxst-agent-usage", "title": "Ambxst", "version": "1"}},
        )
        assert process.stdin is not None
        process.stdin.write(json.dumps({"method": "initialized", "params": {}}) + "\n")
        process.stdin.flush()
        account_message = codex_rpc_request(process, 2, "account/read", timeout=4)
        limits_message = codex_rpc_request(process, 3, "account/rateLimits/read", timeout=4)
        account = (account_message.get("result") or {}).get("account") or {}
        rate_limits = (limits_message.get("result") or {}).get("rateLimits") or {}
        result["tierLabel"] = str(rate_limits.get("planType") or account.get("planType") or account.get("type") or "")
        for raw in (rate_limits.get("primary"), rate_limits.get("secondary")):
            window = codex_limit_window(raw)
            if window:
                result["limits"].append(window)
    except (OSError, RuntimeError, TimeoutError):
        result.update(
            usageStatusText="Codex limits unavailable",
            authHelpText="Run `codex login` if the CLI is not currently authenticated.",
        )
    finally:
        if process is not None:
            try:
                process.terminate()
                process.wait(timeout=1)
            except (OSError, subprocess.TimeoutExpired):
                process.kill()
    return result


def collect_codex(scan_age: float) -> dict[str, Any]:
    stats = cached_stats("codex", scan_age, scan_codex_stats)
    limits = collect_codex_limits()
    record: dict[str, Any] = {
        "schemaVersion": SCHEMA_VERSION,
        "id": "codex",
        "name": "Codex",
        "updatedAt": utc_iso(),
        "installed": shutil.which("codex", path=codex_runtime_environment()["PATH"]) is not None,
        "ready": number(stats.get("totalPrompts")) > 0 or bool(limits.get("limits")),
        "hasLocalStats": True,
        "localStatsWindow": "Last 30 days",
    }
    record.update(stats)
    record.update(limits)
    return record


def cursor_auth_paths() -> tuple[Path, Path]:
    cursor_config = Path(os.environ.get("CURSOR_CONFIG_DIR") or agent_config_home() / "cursor").expanduser()
    ide_config = Path(os.environ.get("CURSOR_IDE_CONFIG_DIR") or agent_config_home() / "Cursor").expanduser()
    return cursor_config / "auth.json", ide_config / "User" / "globalStorage" / "state.vscdb"


def cursor_access_token() -> str:
    auth_path, database_path = cursor_auth_paths()
    auth = read_json(auth_path) or {}
    token = str(auth.get("accessToken") or "")
    if token:
        return token
    if not database_path.is_file():
        return ""
    try:
        with sqlite3.connect(f"file:{database_path}?mode=ro", uri=True, timeout=1) as database:
            row = database.execute("SELECT value FROM ItemTable WHERE key = ?", ("cursorAuth/accessToken",)).fetchone()
        if not row:
            return ""
        value = str(row[0] or "")
        try:
            decoded = json.loads(value)
            return str(decoded) if isinstance(decoded, str) else value
        except ValueError:
            return value
    except sqlite3.Error:
        return ""


def cursor_client_version() -> str:
    configured = str(os.environ.get("CURSOR_CLIENT_VERSION") or "").strip()
    if configured:
        return configured
    for package_path in (
        Path("/usr/share/cursor/resources/app/package.json"),
        agent_home() / ".local" / "share" / "cursor" / "resources" / "app" / "package.json",
    ):
        package = read_json(package_path) or {}
        if package.get("version"):
            return str(package["version"])
    return "0.0.0"


def cursor_request(method: str, access_token: str) -> dict[str, Any]:
    request = urllib.request.Request(
        f"{CURSOR_API_BASE}/{method}",
        data=b"{}",
        method="POST",
        headers={
            "Authorization": "Bearer " + access_token,
            "Content-Type": "application/json",
            "Connect-Protocol-Version": "1",
            "x-cursor-client-type": "ide",
            "x-cursor-client-version": cursor_client_version(),
        },
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        payload = json.loads(response.read().decode("utf-8", errors="replace"))
    return payload if isinstance(payload, dict) else {}


def cursor_limits_from_payload(usage: dict[str, Any], plan: dict[str, Any]) -> dict[str, Any]:
    plan_usage = usage.get("planUsage") or usage.get("plan_usage") or {}
    if not isinstance(plan_usage, dict):
        plan_usage = {}
    limit_cents = decimal_number(
        plan_usage.get("limit", plan.get("includedAmountCents", plan.get("included_amount_cents", 0)))
    )
    spent_cents = decimal_number(plan_usage.get("includedSpend", plan_usage.get("included_spend", 0)))
    if spent_cents <= 0 and limit_cents > 0 and "remaining" in plan_usage:
        spent_cents = max(0.0, limit_cents - decimal_number(plan_usage.get("remaining")))
    if limit_cents > 0:
        percent = min(1.0, max(0.0, spent_cents / limit_cents))
    else:
        raw_percent = decimal_number(plan_usage.get("totalPercentUsed", plan_usage.get("total_percent_used", -1)))
        percent = min(1.0, max(0.0, raw_percent / 100)) if raw_percent >= 0 else -1
    limits: list[dict[str, Any]] = []
    if percent >= 0:
        detail = ""
        if limit_cents > 0:
            detail = f"${spent_cents / 100:.2f} of ${limit_cents / 100:.2f} included"
        limits.append(
            {
                "title": "Monthly included",
                "label": "Billing cycle",
                "percent": percent,
                "resetsAt": normalize_reset_at(
                    usage.get("billingCycleEnd")
                    or usage.get("billing_cycle_end")
                    or plan.get("billingCycleEnd")
                    or plan.get("billing_cycle_end")
                ),
                "detail": detail,
                "source": "authoritative",
            }
        )
    return {
        "limits": limits,
        "tierLabel": str(plan.get("planName") or plan.get("plan_name") or "Cursor"),
    }


def collect_cursor_limits(force: bool) -> dict[str, Any]:
    result: dict[str, Any] = {"limits": [], "tierLabel": "", "usageStatusText": "", "authHelpText": ""}
    token = cursor_access_token()
    cache_path = cache_root() / "cursor-limits.json"
    cached = read_json(cache_path) or {}
    cached_result = cached.get("result") if isinstance(cached.get("result"), dict) else {}
    fetched_at = decimal_number(cached.get("fetchedAtMs")) / 1000
    if not token:
        result.update(
            cached_result,
            usageStatusText="Sign in required",
            authHelpText="Sign in to Cursor to show the current billing-cycle allowance.",
        )
        return result
    if cached_result and not force and time.time() - fetched_at < 15:
        result.update(cached_result)
        return result
    try:
        usage = cursor_request("GetCurrentPeriodUsage", token)
        plan = cursor_request("GetPlanInfo", token)
        parsed = cursor_limits_from_payload(usage, plan)
        result.update(parsed)
        if parsed.get("limits"):
            write_private_json(cache_path, {"fetchedAtMs": round(time.time() * 1000), "result": parsed})
    except urllib.error.HTTPError as error:
        result.update(
            cached_result,
            usageStatusText="Sign in required" if error.code in (401, 403) else "Cursor limits unavailable",
            authHelpText="Open Cursor and sign in again." if error.code in (401, 403) else f"Cursor returned status {error.code}.",
        )
    except (OSError, TimeoutError, urllib.error.URLError):
        result.update(
            cached_result,
            usageStatusText="Offline — showing cached limits" if cached_result else "Cursor limits unavailable",
            authHelpText="Couldn't reach Cursor's usage service; Ambxst will retry shortly.",
            retryAdvised=True,
        )
    return result


def collect_cursor(force: bool, _scan_age: float) -> dict[str, Any]:
    limits = collect_cursor_limits(force)
    record: dict[str, Any] = {
        "schemaVersion": SCHEMA_VERSION,
        "id": "cursor",
        "name": "Cursor",
        "updatedAt": utc_iso(),
        "installed": shutil.which("cursor") is not None,
        "ready": bool(cursor_access_token()) or bool(limits.get("limits")),
        "hasLocalStats": False,
        "localStatsWindow": "",
    }
    record.update(empty_stats())
    record.update(limits)
    return record


def opencode_data_dir() -> Path:
    return Path(os.environ.get("OPENCODE_DATA_DIR") or agent_data_home() / "opencode").expanduser()


def opencode_go_key() -> str:
    auth = read_json(opencode_data_dir() / "auth.json") or {}
    credential = auth.get("opencode-go")
    return str(credential.get("key") or "") if isinstance(credential, dict) else ""


def scan_opencode_go_data() -> dict[str, Any]:
    accumulator = UsageAccumulator()
    events: list[dict[str, float]] = []
    database_path = opencode_data_dir() / "opencode.db"
    if not database_path.is_file():
        result = accumulator.record()
        result["costEvents"] = events
        return result
    cutoff_stats_ms = (time.time() - 30 * 24 * 60 * 60) * 1000
    cutoff_limits_ms = (time.time() - 45 * 24 * 60 * 60) * 1000
    try:
        with sqlite3.connect(f"file:{database_path}?mode=ro", uri=True, timeout=2) as database:
            rows = database.execute(
                "SELECT id, session_id, time_created, data FROM message WHERE time_created >= ?",
                (round(cutoff_limits_ms),),
            )
            for message_id, session_id, created_at, raw_data in rows:
                try:
                    data = json.loads(raw_data)
                except (TypeError, ValueError):
                    continue
                if not isinstance(data, dict) or data.get("role") != "assistant" or data.get("providerID") != "opencode-go":
                    continue
                timestamp_ms = decimal_number((data.get("time") or {}).get("created") or created_at)
                cost = max(0.0, decimal_number(data.get("cost")))
                if cost > 0:
                    events.append({"timestampMs": timestamp_ms, "cost": cost})
                if timestamp_ms < cutoff_stats_ms:
                    continue
                tokens = data.get("tokens") if isinstance(data.get("tokens"), dict) else {}
                cache = tokens.get("cache") if isinstance(tokens.get("cache"), dict) else {}
                accumulator.add(
                    local_date(timestamp_ms),
                    str(session_id or message_id),
                    str(data.get("modelID") or "opencode-go"),
                    number(tokens.get("input")),
                    number(tokens.get("output")) + number(tokens.get("reasoning")),
                    number(cache.get("read")),
                    number(cache.get("write")),
                )
    except sqlite3.Error:
        pass
    result = accumulator.record()
    result["costEvents"] = events
    return result


def opencode_go_limits(events: list[dict[str, Any]], now: dt.datetime | None = None) -> list[dict[str, Any]]:
    current = now or utc_now()
    if current.tzinfo is None:
        current = current.replace(tzinfo=dt.timezone.utc)
    now_ms = current.timestamp() * 1000
    valid = sorted(
        (
            (decimal_number(event.get("timestampMs")), max(0.0, decimal_number(event.get("cost"))))
            for event in events
            if isinstance(event, dict)
        ),
        key=lambda event: event[0],
    )
    rolling_start = 0
    for index in range(1, len(valid)):
        if valid[index][0] - valid[index - 1][0] >= 5 * 60 * 60 * 1000:
            rolling_start = index
    rolling = valid[rolling_start:] if valid and now_ms - valid[-1][0] < 5 * 60 * 60 * 1000 else []
    rolling_cost = sum(cost for _, cost in rolling)
    rolling_reset = (
        dt.datetime.fromtimestamp((rolling[-1][0] + 5 * 60 * 60 * 1000) / 1000, dt.timezone.utc) if rolling else None
    )

    week_start = (current - dt.timedelta(days=current.weekday())).replace(hour=0, minute=0, second=0, microsecond=0)
    week_end = week_start + dt.timedelta(days=7)
    month_start = current.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    if month_start.month == 12:
        month_end = month_start.replace(year=month_start.year + 1, month=1)
    else:
        month_end = month_start.replace(month=month_start.month + 1)
    weekly_cost = sum(cost for timestamp, cost in valid if timestamp >= week_start.timestamp() * 1000)
    monthly_cost = sum(cost for timestamp, cost in valid if timestamp >= month_start.timestamp() * 1000)

    limits: list[dict[str, Any]] = []
    for title, label, spent, cap, reset in (
        ("Session", "Rolling 5-hour", rolling_cost, OPENCODE_GO_LIMITS["rolling"], rolling_reset),
        ("Weekly", "Weekly", weekly_cost, OPENCODE_GO_LIMITS["weekly"], week_end),
        ("Monthly", "Calendar month", monthly_cost, OPENCODE_GO_LIMITS["monthly"], month_end),
    ):
        limits.append(
            {
                "title": title,
                "label": label,
                "percent": min(1.0, spent / cap),
                "resetsAt": reset.isoformat() if reset else "",
                "detail": f"${spent:.2f} of ${cap:.0f} locally",
                "source": "local-estimate",
            }
        )
    return limits


def collect_opencode_go(_force: bool, scan_age: float) -> dict[str, Any]:
    data = cached_stats("opencode-go", scan_age, scan_opencode_go_data)
    events = data.pop("costEvents", []) if isinstance(data.get("costEvents"), list) else []
    key_available = bool(opencode_go_key())
    record: dict[str, Any] = {
        "schemaVersion": SCHEMA_VERSION,
        "id": "opencode-go",
        "name": "OpenCode Go",
        "updatedAt": utc_iso(),
        "installed": shutil.which("opencode") is not None,
        "ready": key_available or number(data.get("totalPrompts")) > 0,
        "hasLocalStats": True,
        "localStatsWindow": "Last 30 days",
        "tierLabel": "Go",
        "limits": opencode_go_limits(events) if key_available or events else [],
        "limitsNote": (
            "Local estimate from this machine's OpenCode history. OpenCode Go does not expose its account counters "
            "through the saved API key, so the console may be higher and its monthly reset may differ."
        ),
        "usageStatusText": "" if key_available else "OpenCode Go not connected",
        "authHelpText": "Run `opencode auth login`, then choose OpenCode Go." if not key_available else "",
    }
    record.update(data)
    return record


def detect_claude() -> bool:
    return shutil.which("claude") is not None or claude_config_dir().exists()


def detect_codex() -> bool:
    return shutil.which("codex", path=codex_runtime_environment()["PATH"]) is not None or codex_home().exists()


def detect_cursor() -> bool:
    auth_path, database_path = cursor_auth_paths()
    return shutil.which("cursor") is not None or auth_path.exists() or database_path.exists()


def opencode_db_has_go_usage() -> bool:
    database_path = opencode_data_dir() / "opencode.db"
    if not database_path.is_file():
        return False
    try:
        with sqlite3.connect(f"file:{database_path}?mode=ro", uri=True, timeout=1) as database:
            row = database.execute("SELECT 1 FROM message WHERE data LIKE '%opencode-go%' LIMIT 1").fetchone()
        return row is not None
    except sqlite3.Error:
        return False


def detect_opencode_go() -> bool:
    return bool(opencode_go_key()) or opencode_db_has_go_usage()


def error_record(provider: str, error: Exception) -> dict[str, Any]:
    names = {"claude": "Claude Code", "codex": "Codex", "cursor": "Cursor", "opencode-go": "OpenCode Go"}
    return {
        "schemaVersion": SCHEMA_VERSION,
        "id": provider,
        "name": names.get(provider, provider.title()),
        "updatedAt": utc_iso(),
        "installed": True,
        "ready": False,
        "limits": [],
        "recentDays": [],
        "modelUsage": {},
        "usageStatusText": "Collector unavailable",
        "authHelpText": f"The {provider} collector failed safely ({type(error).__name__}).",
    }


PROVIDER_COLLECTORS: dict[str, Callable[[bool, float], dict[str, Any]]] = {
    "claude": lambda force, scan_age: collect_claude(force, scan_age),
    "codex": lambda _force, scan_age: collect_codex(scan_age),
    "cursor": collect_cursor,
    "opencode-go": collect_opencode_go,
}

PROVIDER_DETECTORS: dict[str, Callable[[], bool]] = {
    "claude": detect_claude,
    "codex": detect_codex,
    "cursor": detect_cursor,
    "opencode-go": detect_opencode_go,
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true", help="ignore local scan and limit caches")
    parser.add_argument("--limits-only", action="store_true", help="reuse local stats while refreshing provider limits")
    parser.add_argument("--provider", choices=tuple(PROVIDER_COLLECTORS), action="append")
    args = parser.parse_args()

    explicit_selection = args.provider is not None
    selected = args.provider or [provider for provider, detector in PROVIDER_DETECTORS.items() if detector()]
    scan_age = 0 if args.force else LIMITS_ONLY_SCAN_CACHE_SECONDS if args.limits_only else NORMAL_SCAN_CACHE_SECONDS
    providers: list[dict[str, Any]] = []
    for provider in selected:
        try:
            record = PROVIDER_COLLECTORS[provider](args.force, scan_age)
        except Exception as error:  # Provider failure must not take down the other provider.
            record = error_record(provider, error)
        if explicit_selection or record.get("installed") or record.get("ready") or number(record.get("totalPrompts")) > 0:
            providers.append(record)

    print(json.dumps({"schemaVersion": SCHEMA_VERSION, "updatedAt": utc_iso(), "providers": providers}, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
