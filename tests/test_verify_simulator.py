import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock


SPEC = importlib.util.spec_from_file_location("verify_simulator", Path(__file__).resolve().parents[1] / "tools/verify_simulator.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def passing_report(verification_id="current"):
    return {
        "schemaVersion": 1, "verificationID": verification_id, "scope": "host-metal-only",
        "passed": True, "tests": [
            {"name": name, "passed": True, "width": width, "height": height,
             "checkedPixels": width * height, "mismatchedPixels": 0, "maximumChannelError": 0, "channelTolerance": 2}
            for name in MODULE.REQUIRED_SCENES for width, height in MODULE.REQUIRED_DIMENSIONS
        ],
        "onscreen": {"completedFrames": 3, "errorCount": 0},
    }


class ReportTests(unittest.TestCase):
    def test_missing_or_duplicate_coverage_is_rejected(self):
        report = passing_report()
        report["tests"].pop()
        with self.assertRaisesRegex(ValueError, "coverage"):
            MODULE.validate_report(report, "current")
        report = passing_report()
        report["tests"].append(report["tests"][0])
        with self.assertRaisesRegex(ValueError, "duplicate"):
            MODULE.validate_report(report, "current")

    def test_pixel_mismatch_cannot_hide_behind_pass_flag(self):
        report = passing_report()
        report["tests"][0]["mismatchedPixels"] = 1
        with self.assertRaisesRegex(ValueError, "every pixel"):
            MODULE.validate_report(report, "current")

    def test_valid_report(self):
        report = passing_report()
        self.assertIs(MODULE.validate_report(report, "current"), report)

    def test_invalid_reports(self):
        cases = [
            ("schemaVersion", True), ("schemaVersion", 2), ("verificationID", "stale"),
            ("scope", "gameplay"), ("passed", False), ("passed", 1),
            ("tests", []), ("tests", {}), ("tests", [{"name": "failed", "passed": False}]),
            ("tests", [None]), ("tests", [{"passed": 1}]), ("onscreen", None),
        ]
        for field, value in cases:
            with self.subTest(field=field, value=value):
                report = passing_report()
                report[field] = value
                with self.assertRaises(ValueError):
                    MODULE.validate_report(report, "current")
        with self.assertRaises(ValueError):
            MODULE.validate_report([], "current")

    def test_onscreen_error_checks(self):
        for field, values in (
            ("completedFrames", [None, 0, 2, True, "3", float("nan"), float("inf")]),
            ("errorCount", [None, 1, -1, False, "0", float("nan"), float("inf")]),
        ):
            for value in values:
                with self.subTest(field=field, value=value):
                    report = passing_report()
                    report["onscreen"][field] = value
                    with self.assertRaisesRegex(ValueError, field):
                        MODULE.validate_report(report, "current")


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.path = self.root / "graphics-verification.json"

    def test_stale_failure_is_ignored_until_current_report(self):
        stale = passing_report("stale")
        stale["passed"] = False
        self.path.write_text(json.dumps(stale))
        with mock.patch.object(MODULE.time, "sleep", side_effect=lambda delay: self.path.write_text(json.dumps(passing_report()))):
            report = MODULE.wait_for_report(self.path, "current", 1)
        self.assertEqual(report["verificationID"], "current")

    def test_stale_and_missing_reports_timeout(self):
        for report in (None, passing_report("stale")):
            with self.subTest(report=report):
                if report:
                    self.path.write_text(json.dumps(report))
                with self.assertRaisesRegex(TimeoutError, "verificationID=current"):
                    MODULE.wait_for_report(self.path, "current", 0)

    def test_matching_failed_report_is_not_filtered_out(self):
        report = passing_report()
        report["passed"] = False
        self.path.write_text(json.dumps(report))
        actual = MODULE.wait_for_report(self.path, "current", 0)
        with self.assertRaisesRegex(ValueError, "report.passed"):
            MODULE.validate_report(actual, "current")

    def test_malformed_report_errors(self):
        for contents in ("{broken", "[]"):
            with self.subTest(contents=contents):
                self.path.write_text(contents)
                with self.assertRaises(ValueError):
                    MODULE.wait_for_report(self.path, "current", 0)

    def test_command_errors_and_not_running(self):
        runner = MODULE.Simctl(self.root, 1)
        for message, ignored in (("Application is not running", True), ("found nothing to terminate", True), ("Permission denied", False)):
            with self.subTest(message=message):
                result = subprocess.CompletedProcess([], 3, "", message)
                with mock.patch.object(MODULE.subprocess, "run", return_value=result):
                    if ignored:
                        runner.run("terminate", "device", "bundle", allow_not_running=True)
                    else:
                        with self.assertRaisesRegex(RuntimeError, "Permission denied"):
                            runner.run("terminate", "device", "bundle", allow_not_running=True)
        self.assertIn("Permission denied", (self.root / "commands.jsonl").read_text())

    def test_launch_environment_and_timeout_evidence(self):
        runner = MODULE.Simctl(self.root, 1)
        with mock.patch.object(MODULE.subprocess, "run", side_effect=subprocess.TimeoutExpired("xcrun", 1, output=b"partial", stderr=b"diagnostic")) as run:
            with self.assertRaisesRegex(RuntimeError, "commands.jsonl"):
                runner.run("launch", "device", "bundle", metal_debug=True)
        self.assertEqual(run.call_args.kwargs["env"]["SIMCTL_CHILD_MTL_DEBUG_LAYER"], "1")
        record = json.loads((self.root / "commands.jsonl").read_text())
        self.assertEqual(record["stdout"], "partial")
        self.assertEqual(record["stderr"], "diagnostic")

    def test_device_workflow_and_failed_evidence(self):
        device = "00000000-0000-0000-0000-000000000001"
        args = argparse.Namespace(device=[device], output=self.root / "output", timeout=1,
                                  appearance="both", app=self.root / "Sunshine.app", bundle_id="test.bundle")
        calls = []
        verification_ids = []

        def fake_run(runner, *arguments, **options):
            calls.append((arguments, options))
            if arguments[0] == "list":
                return json.dumps({"devices": {"runtime": [{"udid": device, "state": "Shutdown"}]}})
            if arguments[0] == "launch":
                verification_ids.append(arguments[-1])
                report = passing_report(arguments[-1])
                if len(verification_ids) == 2:
                    report["onscreen"]["errorCount"] = 1
                documents = self.root / "container" / "Documents"
                documents.mkdir(parents=True, exist_ok=True)
                (documents / "graphics-verification.json").write_text(json.dumps(report))
            if arguments[0] == "get_app_container":
                return str(self.root / "container") + "\n"
            if arguments[0] == "io":
                Path(arguments[-1]).write_bytes(b"screenshot")
            return ""

        with mock.patch.object(MODULE.Simctl, "run", fake_run), mock.patch.object(MODULE, "verify_lifecycle", return_value={"passed": True}):
            summary = MODULE.verify(args)
        self.assertFalse(summary["passed"])
        self.assertEqual(len(set(verification_ids)), 2)
        commands = [arguments[0] for arguments, options in calls]
        self.assertEqual(commands[:4], ["list", "boot", "bootstatus", "install"])
        self.assertEqual(commands.count("install"), 1)
        self.assertEqual(
            [arguments for arguments, options in calls if arguments[0] == "ui"],
            [("ui", device, "appearance", "light"), ("ui", device, "appearance", "dark")],
        )
        for arguments, options in calls:
            if arguments[0] == "launch":
                self.assertTrue(options["metal_debug"])
                self.assertEqual(arguments[3:5], ("--verify-graphics", "--verification-id"))
            if arguments[0] == "terminate":
                self.assertTrue(options["allow_not_running"])
        for appearance, passed in (("light", True), ("dark", False)):
            output = args.output / device / appearance
            evidence = json.loads((output / "summary.json").read_text())
            self.assertEqual(evidence["passed"], passed)
            self.assertTrue((output / "graphics-verification.json").is_file())
            self.assertTrue((output / "screenshot.png").is_file())
        self.assertEqual(json.loads((args.output / "summary.json").read_text()), summary)

    def test_booted_device_skips_boot_and_deduplicates_install(self):
        args = argparse.Namespace(device=["device", "device"], output=self.root, timeout=1,
                                  appearance="light", app=self.root / "Sunshine.app", bundle_id="test.bundle")
        inventory = json.dumps({"devices": {"runtime": [{"udid": "device", "state": "Booted"}]}})
        with mock.patch.object(MODULE.Simctl, "run", side_effect=[inventory, "", ""]) as run:
            with mock.patch.object(MODULE, "verify_appearance", return_value={"passed": True}):
                summary = MODULE.verify(args)
        self.assertTrue(summary["passed"])
        self.assertEqual([call.args[0] for call in run.call_args_list], ["list", "bootstatus", "install"])

    def test_launch_and_screenshot_failures_are_saved(self):
        args = argparse.Namespace(output=self.root, timeout=1, bundle_id="test.bundle")
        with mock.patch.object(MODULE.Simctl, "run", side_effect=["", "", RuntimeError("launch failed"), RuntimeError("screenshot failed")]):
            summary = MODULE.verify_appearance("device", "dark", args)
        self.assertFalse(summary["passed"])
        self.assertEqual(summary["error"], "launch failed")
        self.assertEqual(summary["screenshotError"], "screenshot failed")
        self.assertEqual(json.loads((self.root / "device" / "dark" / "summary.json").read_text()), summary)


class LifecycleTests(unittest.TestCase):
    def states(self):
        background = {"paused": True, "processID": 42, "onscreen": {"completedFrames": 5, "errorCount": 0}}
        foreground = {"paused": False, "processID": 42, "onscreen": {"completedFrames": 10, "errorCount": 0}}
        return background, foreground

    def test_valid_resume(self):
        MODULE.validate_lifecycle(*self.states())

    def test_restart_stalled_frames_and_errors_are_rejected(self):
        for field, value in (("processID", 43), ("paused", True)):
            background, foreground = self.states()
            foreground[field] = value
            with self.assertRaises(ValueError):
                MODULE.validate_lifecycle(background, foreground)
        for field, value in (("completedFrames", 5), ("errorCount", 1)):
            background, foreground = self.states()
            foreground["onscreen"][field] = value
            with self.assertRaises(ValueError):
                MODULE.validate_lifecycle(background, foreground)

    def test_wrong_run_cannot_satisfy_state_wait(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "state.json"
            path.write_text(json.dumps({"verificationID": "stale", "event": "background"}))
            with self.assertRaises(TimeoutError):
                MODULE.wait_for_state(path, "current", "background", 0)

    def test_background_and_foreground_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            runner = mock.Mock()
            with mock.patch.object(MODULE, "wait_for_state", side_effect=self.states()):
                report = MODULE.verify_lifecycle(runner, "device", "bundle", output, "current", 1, output)
            self.assertTrue(report["passed"])
            self.assertEqual(runner.run.call_args_list, [mock.call("launch", "device", "com.apple.Preferences"),
                                                        mock.call("launch", "device", "bundle")])
            self.assertTrue((output / "lifecycle-verification.json").exists())


if __name__ == "__main__":
    unittest.main()
