import datetime as dt
import importlib.util
import json
import os
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).parents[1] / "scripts" / "agent_usage.py"
SPEC = importlib.util.spec_from_file_location("agent_usage", SCRIPT)
agent_usage = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(agent_usage)


class AgentUsageTest(unittest.TestCase):
    def test_claude_percentage_payload_normalizes_percent_scale(self):
        payload = {
            "five_hour": {"utilization": "1.0%", "resets_at": "2030-01-01T00:00:00Z"},
            "seven_day_oauth_apps": {"utilization": 37.0, "resets_at": "2030-01-07T00:00:00Z"},
        }

        limits = agent_usage.claude_limits_from_payload(payload)

        self.assertEqual([item["title"] for item in limits], ["Session", "Weekly"])
        self.assertAlmostEqual(limits[0]["percent"], 0.01)
        self.assertAlmostEqual(limits[1]["percent"], 0.37)
        self.assertTrue(limits[0]["resetsAt"].endswith("+00:00"))

    def test_scoped_claude_limit_keeps_model_and_window(self):
        payload = {
            "limits": [
                {
                    "kind": "weekly_scoped",
                    "percent": 52,
                    "resets_at": "2030-01-07T00:00:00Z",
                    "scope": {"model": {"display_name": "Opus"}},
                }
            ]
        }

        limits = agent_usage.claude_limits_from_payload(payload)

        self.assertEqual(limits[0]["title"], "Opus Weekly")
        self.assertAlmostEqual(limits[0]["percent"], 0.52)

    def test_codex_limit_window_normalizes_duration_and_reset(self):
        window = agent_usage.codex_limit_window(
            {"usedPercent": 24, "windowDurationMins": 10080, "resetsAt": 1893456000}
        )

        self.assertEqual(window["title"], "Weekly")
        self.assertEqual(window["label"], "Weekly (7-day)")
        self.assertAlmostEqual(window["percent"], 0.24)
        self.assertIn("2030-01-01", window["resetsAt"])

    def test_claude_scan_deduplicates_message_ids(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory)
            project = config / "projects" / "sample"
            project.mkdir(parents=True)
            timestamp = dt.datetime.now(dt.timezone.utc).isoformat()
            entry = {
                "type": "assistant",
                "timestamp": timestamp,
                "sessionId": "session-1",
                "message": {
                    "id": "message-1",
                    "role": "assistant",
                    "model": "claude-test",
                    "usage": {
                        "input_tokens": 100,
                        "output_tokens": 25,
                        "cache_read_input_tokens": 50,
                    },
                },
            }
            (project / "session.jsonl").write_text(
                json.dumps(entry) + "\n" + json.dumps(entry) + "\n", encoding="utf-8"
            )

            with patch.dict(os.environ, {"CLAUDE_CONFIG_DIR": str(config)}):
                stats = agent_usage.scan_claude_stats()

        self.assertEqual(stats["todayPrompts"], 1)
        self.assertEqual(stats["todaySessions"], 1)
        self.assertEqual(stats["todayTotalTokens"], 175)
        self.assertEqual(stats["modelUsage"]["claude-test"]["cacheReadInputTokens"], 50)

    def test_codex_scan_counts_last_turn_without_double_counting_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            codex_home = Path(directory)
            session_dir = codex_home / "sessions"
            session_dir.mkdir()
            timestamp = dt.datetime.now(dt.timezone.utc).isoformat()
            entries = [
                {"type": "turn_context", "payload": {"model": "gpt-test"}},
                {
                    "type": "event_msg",
                    "timestamp": timestamp,
                    "payload": {
                        "type": "token_count",
                        "info": {
                            "last_token_usage": {
                                "input_tokens": 100,
                                "cached_input_tokens": 40,
                                "output_tokens": 20,
                            }
                        },
                    },
                },
            ]
            (session_dir / "session.jsonl").write_text(
                "".join(json.dumps(entry) + "\n" for entry in entries), encoding="utf-8"
            )

            with patch.dict(os.environ, {"CODEX_HOME": str(codex_home)}):
                stats = agent_usage.scan_codex_stats()

        self.assertEqual(stats["todayPrompts"], 1)
        self.assertEqual(stats["todayTotalTokens"], 120)
        self.assertEqual(stats["modelUsage"]["gpt-test"]["inputTokens"], 60)
        self.assertEqual(stats["modelUsage"]["gpt-test"]["cacheReadInputTokens"], 40)

    def test_cursor_usage_normalizes_included_spend(self):
        result = agent_usage.cursor_limits_from_payload(
            {
                "billingCycleEnd": "2030-02-01T00:00:00Z",
                "planUsage": {"includedSpend": 500, "limit": 2000},
            },
            {"planName": "pro", "includedAmountCents": 2000},
        )

        self.assertEqual(result["tierLabel"], "pro")
        self.assertAlmostEqual(result["limits"][0]["percent"], 0.25)
        self.assertEqual(result["limits"][0]["detail"], "$5.00 of $20.00 included")
        self.assertTrue(result["limits"][0]["resetsAt"].endswith("+00:00"))

    def test_opencode_go_detection_requires_go_account_or_history(self):
        with tempfile.TemporaryDirectory() as directory:
            data_dir = Path(directory)
            (data_dir / "auth.json").write_text(
                json.dumps({"opencode": {"type": "api", "key": "generic-key"}}), encoding="utf-8"
            )
            with patch.dict(os.environ, {"OPENCODE_DATA_DIR": str(data_dir)}):
                self.assertFalse(agent_usage.detect_opencode_go())
                (data_dir / "auth.json").write_text(
                    json.dumps({"opencode-go": {"type": "api", "key": "go-key"}}), encoding="utf-8"
                )
                self.assertTrue(agent_usage.detect_opencode_go())

    def test_opencode_go_scan_reads_local_database_without_exposing_key(self):
        with tempfile.TemporaryDirectory() as directory:
            data_dir = Path(directory)
            database_path = data_dir / "opencode.db"
            timestamp_ms = round(dt.datetime.now(dt.timezone.utc).timestamp() * 1000)
            message = {
                "role": "assistant",
                "providerID": "opencode-go",
                "modelID": "gpt-test",
                "cost": 1.5,
                "time": {"created": timestamp_ms},
                "tokens": {
                    "input": 100,
                    "output": 20,
                    "reasoning": 5,
                    "cache": {"read": 40, "write": 10},
                },
            }
            with sqlite3.connect(database_path) as database:
                database.execute(
                    "CREATE TABLE message (id TEXT, session_id TEXT, time_created INTEGER, data TEXT)"
                )
                database.execute(
                    "INSERT INTO message VALUES (?, ?, ?, ?)",
                    ("message-1", "session-1", timestamp_ms, json.dumps(message)),
                )
            with patch.dict(os.environ, {"OPENCODE_DATA_DIR": str(data_dir)}):
                result = agent_usage.scan_opencode_go_data()

        self.assertEqual(result["todayPrompts"], 1)
        self.assertEqual(result["todayTotalTokens"], 175)
        self.assertEqual(result["costEvents"][0]["cost"], 1.5)
        self.assertNotIn("key", json.dumps(result).lower())

    def test_opencode_go_limits_are_marked_as_local_estimates(self):
        now = dt.datetime(2030, 1, 8, 12, 0, tzinfo=dt.timezone.utc)
        events = [{"timestampMs": (now - dt.timedelta(hours=1)).timestamp() * 1000, "cost": 3.0}]

        limits = agent_usage.opencode_go_limits(events, now)

        self.assertEqual([item["title"] for item in limits], ["Session", "Weekly", "Monthly"])
        self.assertAlmostEqual(limits[0]["percent"], 0.25)
        self.assertTrue(all(item["source"] == "local-estimate" for item in limits))


if __name__ == "__main__":
    unittest.main()
