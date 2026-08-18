import argparse
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPTS = Path(__file__).parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

import agent_common
import agent_crash
import agent_integration
import crash_watch


class CrashWatcherTest(unittest.TestCase):
    def event(self, **changes):
        values = {
            "pid": 4242,
            "uid": os.getuid(),
            "comm": "sample-app",
            "executable": "/usr/bin/sample-app",
            "signal": "SIGSEGV",
            "happened_at": "2030-01-02T03:04:05+00:00",
        }
        values.update(changes)
        return crash_watch.CrashEvent(**values)

    def test_journal_record_becomes_bounded_metadata(self):
        event = crash_watch.event_from_journal(
            {
                "COREDUMP_PID": "4242",
                "COREDUMP_UID": str(os.getuid()),
                "COREDUMP_COMM": "sample-app",
                "COREDUMP_EXE": "/usr/bin/sample-app",
                "COREDUMP_SIGNAL_NAME": "SIGSEGV",
                "__REALTIME_TIMESTAMP": "1893553445000000",
            }
        )

        self.assertIsNotNone(event)
        self.assertEqual(event.pid, 4242)
        self.assertEqual(event.name, "sample-app")
        self.assertEqual(event.signal, "SIGSEGV")
        self.assertIn("2030-01-02", event.happened_at)

    def test_announcement_requires_current_user_and_selected_installed_agent(self):
        event = self.event()
        with (
            patch.object(crash_watch, "capture_disabled_path", return_value=Path("/missing/capture-flag")),
            patch.object(crash_watch, "default_agent", return_value="codex"),
            patch.object(crash_watch, "provider_executable", return_value="/usr/bin/codex"),
        ):
            self.assertTrue(crash_watch.should_announce(event))
            self.assertFalse(crash_watch.should_announce(self.event(uid=os.getuid() + 1)))
            self.assertFalse(crash_watch.should_announce(event, crash_watch.re.compile("sample")))

        with (
            patch.object(crash_watch, "capture_disabled_path", return_value=Path("/missing/capture-flag")),
            patch.object(crash_watch, "default_agent", return_value=""),
        ):
            self.assertFalse(crash_watch.should_announce(event))

    def test_dedupe_window_reopens_after_timeout(self):
        window = crash_watch.DedupeWindow(60)

        self.assertTrue(window.accepts("sample-app", now=100))
        self.assertFalse(window.accepts("sample-app", now=159))
        self.assertTrue(window.accepts("sample-app", now=160))

    def test_delivery_passes_fields_as_argv_without_a_shell(self):
        completed = subprocess.CompletedProcess([], 0)
        with (
            patch.dict(os.environ, {"AMBXST_CRASH_DELIVERY_ATTEMPTS": "1"}),
            patch.object(crash_watch.subprocess, "run", return_value=completed) as run,
        ):
            crash_watch.deliver(self.event(comm="name with spaces"))

        command = run.call_args.args[0]
        self.assertEqual(command[1:4], ["crash-notify", "4242", "name with spaces"])
        self.assertNotIn("shell", run.call_args.kwargs)


class AgentLauncherTest(unittest.TestCase):
    def test_all_provider_commands_start_in_guarded_interactive_modes(self):
        with patch.object(agent_common, "provider_executable", side_effect=lambda value: f"/bin/{value}"):
            self.assertEqual(
                agent_common.provider_command("claude", "diagnose")[:3],
                ["/bin/claude", "--permission-mode", "plan"],
            )
            self.assertEqual(
                agent_common.provider_command("codex", "diagnose")[:5],
                ["/bin/codex", "-s", "read-only", "-a", "untrusted"],
            )
            self.assertEqual(
                agent_common.provider_command("cursor", "diagnose")[:3],
                ["/bin/cursor", "--mode", "ask"],
            )
            self.assertEqual(
                agent_common.provider_command("opencode-go", "diagnose"),
                ["/bin/opencode-go", "--prompt", "diagnose"],
            )

    def test_prompt_contains_metadata_and_never_copies_unknown_core_fields(self):
        supplied = argparse.Namespace(comm="", exe="", signal="", time="")
        record = {
            "Executable": "/usr/bin/sample-app",
            "SignalName": "SIGSEGV",
            "Timestamp": 1893553445000000,
            "SECRET_FROM_PROCESS_MEMORY": "do-not-copy",
        }

        prompt = agent_crash.diagnostic_prompt(4242, record, supplied)

        self.assertIn("PID: 4242", prompt)
        self.assertIn("diagnose-crash", prompt)
        self.assertNotIn("do-not-copy", prompt)
        self.assertIn("Do not apply fixes or upload the core", prompt)

    def test_coredump_record_rejects_another_users_dump(self):
        result = subprocess.CompletedProcess(
            [], 0, stdout=json.dumps({"OwnerUID": os.getuid() + 1}), stderr=""
        )
        with patch.object(agent_crash.subprocess, "run", return_value=result):
            with self.assertRaisesRegex(RuntimeError, "another user"):
                agent_crash.coredump_record(4242)


class AgentIntegrationTest(unittest.TestCase):
    def test_safe_symlink_is_idempotent_and_refuses_regular_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            source.mkdir()
            target = root / "nested" / "target"

            agent_integration.safe_symlink(source, target)
            agent_integration.safe_symlink(source, target)
            self.assertEqual(target.resolve(), source.resolve())

            target.unlink()
            target.write_text("owned by user", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "Refusing to replace"):
                agent_integration.safe_symlink(source, target)

            target.unlink()
            other = root / "other"
            other.mkdir()
            target.symlink_to(other)
            with self.assertRaisesRegex(RuntimeError, "existing symlink"):
                agent_integration.safe_symlink(source, target)

            target.unlink()
            (source / agent_integration.SKILL_MARKER).touch()
            (other / agent_integration.SKILL_MARKER).touch()
            target.symlink_to(other)
            agent_integration.safe_symlink(source, target)
            self.assertEqual(target.resolve(), source.resolve())

    def test_install_skills_links_one_repo_copy_into_each_harness(self):
        with tempfile.TemporaryDirectory() as directory:
            destinations = [Path(directory) / "one", Path(directory) / "two"]
            with (
                patch.object(agent_integration, "skill_directories", return_value=destinations),
                patch.object(agent_integration, "isolated_session", return_value=False),
            ):
                agent_integration.install_skills()

            for destination in destinations:
                for name in agent_integration.SKILL_NAMES:
                    self.assertTrue((destination / name).is_symlink())
                    self.assertTrue((destination / name / "SKILL.md").is_file())

    def test_isolated_lab_resolves_agent_state_into_real_home(self):
        with patch.dict(os.environ, {"AMBXST_AGENT_DATA_HOME": "/real/home"}):
            self.assertEqual(agent_common.agent_home(), Path("/real/home"))
            self.assertEqual(agent_common.config_home(), Path("/real/home/.config"))
            self.assertEqual(agent_common.state_home(), Path("/real/home/.local/state"))

    def test_setup_requires_an_explicit_default_agent_before_mutating(self):
        with (
            patch.object(agent_integration, "default_agent", return_value=""),
            patch.object(agent_integration, "install_skills") as install_skills,
        ):
            with self.assertRaisesRegex(RuntimeError, "Choose a default"):
                agent_integration.install()
        install_skills.assert_not_called()

    def test_ui_setup_persists_selected_provider(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "agents.json"
            with (
                patch.object(agent_integration, "agent_state_path", return_value=state),
                patch.object(agent_integration, "provider_executable", return_value="/usr/bin/codex"),
                patch.object(agent_integration, "install_skills"),
                patch.object(agent_integration, "install_unit"),
                patch.object(agent_integration, "capture_disabled_path", return_value=Path(directory) / "off"),
                patch.object(agent_integration, "run_systemctl"),
            ):
                agent_integration.install("codex")

            self.assertEqual(json.loads(state.read_text(encoding="utf-8")), {"defaultAgent": "codex"})

    def test_setup_links_unit_and_enables_user_service(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            unit = root / "systemd" / "ambxst-crash-watch.service"
            flag = root / "state" / "crash-capture-off"
            flag.parent.mkdir(parents=True)
            flag.touch()
            with (
                patch.object(agent_integration, "default_agent", return_value="codex"),
                patch.object(agent_integration, "provider_executable", return_value="/usr/bin/codex"),
                patch.object(agent_integration, "install_skills") as install_skills,
                patch.object(agent_integration, "unit_target", return_value=unit),
                patch.object(agent_integration, "capture_disabled_path", return_value=flag),
                patch.object(agent_integration, "run_systemctl") as systemctl,
            ):
                agent_integration.install()

            install_skills.assert_called_once_with()
            self.assertTrue(unit.is_file())
            self.assertFalse(unit.is_symlink())
            content = unit.read_text(encoding="utf-8")
            self.assertIn(agent_integration.UNIT_MARKER, content)
            self.assertIn(str(agent_integration.ROOT / "scripts" / "crash_watch.py"), content)
            self.assertFalse(flag.exists())
            self.assertEqual(
                systemctl.call_args_list,
                [
                    unittest.mock.call("daemon-reload", check=True),
                    unittest.mock.call("enable", "--now", "ambxst-crash-watch.service", check=True),
                ],
            )

    def test_unit_install_refuses_unmanaged_file(self):
        with tempfile.TemporaryDirectory() as directory:
            unit = Path(directory) / "ambxst-crash-watch.service"
            unit.write_text("[Unit]\nDescription=User owned\n", encoding="utf-8")
            with patch.object(agent_integration, "unit_target", return_value=unit):
                with self.assertRaisesRegex(RuntimeError, "existing unit"):
                    agent_integration.install_unit()

    def test_capture_toggle_uses_state_flag_and_user_service(self):
        with tempfile.TemporaryDirectory() as directory:
            flag = Path(directory) / "crash-capture-off"
            result = subprocess.CompletedProcess([], 0, stdout="", stderr="")
            with (
                patch.object(agent_integration, "isolated_session", return_value=False),
                patch.object(agent_integration, "capture_disabled_path", return_value=flag),
                patch.object(agent_integration, "run_systemctl", return_value=result) as systemctl,
            ):
                agent_integration.set_capture(False)
                self.assertTrue(flag.exists())
                systemctl.assert_called_with("stop", "ambxst-crash-watch.service")

                agent_integration.set_capture(True)
                self.assertFalse(flag.exists())
                systemctl.assert_called_with("start", "ambxst-crash-watch.service")


if __name__ == "__main__":
    unittest.main()
