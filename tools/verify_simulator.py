#!/usr/bin/env python3
"""Verify the standalone Metal host, not gameplay or a linked game engine."""

import argparse
import json
import math
import os
from pathlib import Path
import shlex
import subprocess
import time
import uuid


LIMITATION = "Host Metal diagnostics only; the engine is not linked and gameplay graphics are not verified."
REQUIRED_SCENES = {"clear", "indexed-geometry", "nearest-texture", "depth-occlusion",
                   "source-alpha-blending", "scissor", "viewport", "linear-to-srgb"}
REQUIRED_DIMENSIONS = {(64, 64), (256, 128), (128, 256), (60, 124)}


def validate_report(report, verification_id):
    if not isinstance(report, dict):
        raise ValueError("Graphics report must be a JSON object.")
    if report.get("verificationID") != verification_id:
        raise ValueError("Graphics report verificationID does not match this run.")
    if type(report.get("schemaVersion")) is not int or report["schemaVersion"] != 1:
        raise ValueError("Graphics report requires schemaVersion 1.")
    if report.get("scope") != "host-metal-only":
        raise ValueError("Graphics report scope must be host-metal-only.")
    errors = []
    if report.get("passed") is not True:
        errors.append("report.passed is not true")
    tests = report.get("tests")
    if not isinstance(tests, list) or not tests:
        errors.append("tests must be a nonempty array")
    else:
        coverage = set()
        for index, test in enumerate(tests):
            if not isinstance(test, dict) or test.get("passed") is not True:
                name = test.get("name", index) if isinstance(test, dict) else index
                errors.append(f"test {name!r} did not pass")
                continue
            key = (test.get("name"), test.get("width"), test.get("height"))
            if not isinstance(key[0], str) or any(type(value) is not int for value in key[1:]):
                errors.append(f"test {index} has invalid identity or dimensions")
                continue
            if key in coverage:
                errors.append(f"duplicate test {key!r}")
            coverage.add(key)
            if test.get("checkedPixels") != key[1] * key[2] or test.get("mismatchedPixels") != 0:
                errors.append(f"test {key!r} did not compare every pixel successfully")
            maximum_error = test.get("maximumChannelError")
            if type(maximum_error) is not int or maximum_error < 0 or maximum_error > 2 or test.get("channelTolerance") != 2:
                errors.append(f"test {key!r} has invalid channel comparison results")
        expected = {(name, width, height) for name in REQUIRED_SCENES for width, height in REQUIRED_DIMENSIONS}
        if coverage != expected:
            errors.append("test coverage must include all 32 required scene/size combinations")
    onscreen = report.get("onscreen")
    if not isinstance(onscreen, dict):
        errors.append("onscreen must be an object")
    else:
        frames = onscreen.get("completedFrames")
        error_count = onscreen.get("errorCount")
        if type(frames) not in (int, float) or not math.isfinite(frames) or frames < 3:
            errors.append("onscreen.completedFrames must be at least 3")
        if type(error_count) not in (int, float) or not math.isfinite(error_count) or error_count != 0:
            errors.append("onscreen.errorCount must be zero")
    if errors:
        raise ValueError("Graphics verification failed: " + "; ".join(errors))
    return report


def wait_for_report(path, verification_id, timeout):
    deadline = time.monotonic() + timeout
    last_id = None
    while True:
        try:
            report = json.loads(path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            report = None
        except (UnicodeError, json.JSONDecodeError) as error:
            raise ValueError(f"Invalid graphics report at {path}: {error}") from error
        if report is not None:
            if not isinstance(report, dict):
                raise ValueError(f"Graphics report at {path} must be a JSON object.")
            last_id = report.get("verificationID")
            if last_id == verification_id:
                return report
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError(
                f"Timed out waiting for {path} with verificationID={verification_id}; "
                f"last observed ID={last_id!r}."
            )
        time.sleep(min(0.2, remaining))


class Simctl:
    def __init__(self, output, timeout):
        self.output = output
        self.timeout = timeout
        output.mkdir(parents=True, exist_ok=True)

    def run(self, *arguments, metal_debug=False, allow_not_running=False):
        command = ["xcrun", "simctl", *arguments]
        environment = os.environ.copy()
        if metal_debug:
            environment["SIMCTL_CHILD_MTL_DEBUG_LAYER"] = "1"
        record = {"command": command, "metalDebugLayer": metal_debug}
        try:
            result = subprocess.run(
                command, capture_output=True, text=True, errors="replace",
                timeout=self.timeout, env=environment,
            )
            record.update(returncode=result.returncode, stdout=result.stdout, stderr=result.stderr)
        except (OSError, subprocess.TimeoutExpired) as error:
            record["error"] = str(error)
            for field in ("stdout", "stderr"):
                value = getattr(error, field, None) or ""
                record[field] = value.decode(errors="replace") if isinstance(value, bytes) else value
            raise RuntimeError(f"{shlex.join(command)}: {error}; see {self.output / 'commands.jsonl'}") from error
        finally:
            with (self.output / "commands.jsonl").open("a", encoding="utf-8") as stream:
                stream.write(json.dumps(record) + "\n")
        if result.returncode:
            message = result.stdout + "\n" + result.stderr
            if allow_not_running and any(
                phrase in message.lower() for phrase in ("not running", "found nothing to terminate")
            ):
                return result.stdout
            raise RuntimeError(
                f"{shlex.join(command)} exited {result.returncode}:\n{message.strip()}"
            )
        return result.stdout


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, allow_nan=False) + "\n", encoding="utf-8")


def wait_for_state(path, verification_id, event, timeout):
    deadline = time.monotonic() + timeout
    while True:
        try:
            state = json.loads(path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            state = None
        if isinstance(state, dict) and state.get("verificationID") == verification_id and state.get("event") == event:
            return state
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError(f"Timed out waiting for lifecycle event {event!r} with verificationID={verification_id}.")
        time.sleep(min(0.2, remaining))


def validate_lifecycle(background, foreground):
    for state, paused in ((background, True), (foreground, False)):
        if not isinstance(state, dict) or not isinstance(state.get("onscreen"), dict):
            raise ValueError("Lifecycle state and onscreen statistics must be objects.")
        statistics = state.get("onscreen", {})
        frames = statistics.get("completedFrames")
        if state.get("paused") is not paused or type(frames) is not int or frames < 3:
            raise ValueError("Invalid rendering pause state or completed frame count.")
        if type(statistics.get("errorCount")) is not int or statistics["errorCount"] != 0:
            raise ValueError("GPU errors during lifecycle verification.")
        if type(state.get("processID")) is not int or state["processID"] <= 0:
            raise ValueError("Missing lifecycle process identity.")
    if background["processID"] != foreground["processID"]:
        raise ValueError("App restarted instead of resuming the same process.")
    if foreground["onscreen"]["completedFrames"] <= background["onscreen"]["completedFrames"]:
        raise ValueError("No new GPU frames completed after foregrounding.")


def verify_lifecycle(runner, device, bundle_id, container, verification_id, timeout, output):
    evidence = {"verificationID": verification_id, "scope": "host-metal-only", "passed": False}
    try:
        runner.run("launch", device, "com.apple.Preferences")
        path = Path(container) / "Documents" / "render-state.json"
        evidence["background"] = wait_for_state(path, verification_id, "background", timeout)
        runner.run("launch", device, bundle_id)
        evidence["foreground"] = wait_for_state(path, verification_id, "foreground-rendering", timeout)
        validate_lifecycle(evidence["background"], evidence["foreground"])
        evidence["passed"] = True
    except (OSError, ValueError, RuntimeError, TimeoutError) as error:
        evidence["error"] = str(error)
    write_json(output / "lifecycle-verification.json", evidence)
    return evidence


def verify_appearance(device, appearance, args):
    output = args.output / device / appearance
    runner = Simctl(output, args.timeout)
    verification_id = uuid.uuid4().hex
    summary = {
        "device": device, "appearance": appearance, "verificationID": verification_id,
        "scope": "host-metal-only", "limitation": LIMITATION, "passed": False,
        "commandLog": str(output / "commands.jsonl"),
    }
    try:
        for filename in ("graphics-verification.json", "lifecycle-verification.json", "screenshot.png"):
            (output / filename).unlink(missing_ok=True)
        runner.run("ui", device, "appearance", appearance)
        runner.run("terminate", device, args.bundle_id, allow_not_running=True)
        runner.run(
            "launch", device, args.bundle_id, "--verify-graphics", "--verification-id",
            verification_id, metal_debug=True,
        )
        container = runner.run("get_app_container", device, args.bundle_id, "data").strip()
        if not container:
            raise ValueError("simctl returned an empty app data container path.")
        report = wait_for_report(
            Path(container) / "Documents" / "graphics-verification.json", verification_id, args.timeout,
        )
        write_json(output / "graphics-verification.json", report)
        summary["report"] = str(output / "graphics-verification.json")
        validate_report(report, verification_id)
        summary["passed"] = True
    except (OSError, ValueError, RuntimeError, TimeoutError) as error:
        summary["error"] = str(error)
    try:
        runner.run("io", device, "screenshot", str(output / "screenshot.png"))
        summary["screenshot"] = str(output / "screenshot.png")
    except (OSError, RuntimeError) as error:
        summary["screenshotError"] = str(error)
        summary["passed"] = False
    if summary["passed"]:
        lifecycle = verify_lifecycle(runner, device, args.bundle_id, container, verification_id, args.timeout, output)
        summary["lifecycle"] = str(output / "lifecycle-verification.json")
        summary["passed"] = lifecycle["passed"]
        if not lifecycle["passed"]:
            summary["error"] = lifecycle["error"]
    write_json(output / "summary.json", summary)
    return summary


def verify(args):
    args.output.mkdir(parents=True, exist_ok=True)
    summary = {"scope": "host-metal-only", "limitation": LIMITATION, "passed": True, "devices": []}
    appearances = ("light", "dark") if args.appearance == "both" else (args.appearance,)
    for device in dict.fromkeys(args.device):
        device_summary = {"device": device, "passed": False, "runs": []}
        summary["devices"].append(device_summary)
        runner = Simctl(args.output / device, args.timeout)
        try:
            inventory = json.loads(runner.run("list", "devices", "--json"))
            matches = [
                entry for devices in inventory["devices"].values() for entry in devices
                if entry.get("udid") == device
            ]
            if len(matches) != 1:
                raise ValueError(f"Simulator UDID not uniquely found: {device}")
            if matches[0].get("state") == "Shutdown":
                runner.run("boot", device)
            runner.run("bootstatus", device, "-b")
            runner.run("install", device, str(args.app))
            for appearance in appearances:
                device_summary["runs"].append(verify_appearance(device, appearance, args))
            device_summary["passed"] = all(run["passed"] for run in device_summary["runs"])
        except (OSError, ValueError, RuntimeError, KeyError, TypeError) as error:
            device_summary["error"] = str(error)
        write_json(args.output / device / "summary.json", device_summary)
        summary["passed"] = summary["passed"] and device_summary["passed"]
    write_json(args.output / "summary.json", summary)
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", action="append", required=True, help="Simulator UDID; repeat for multiple devices.")
    parser.add_argument("--app", type=Path, default=Path("build/simulator/Release-iphonesimulator/Sunshine.app"))
    parser.add_argument("--bundle-id", default="dev.chasem.sms-iphone-ipad")
    parser.add_argument("--output", type=Path, default=Path("build/validation/graphics"))
    parser.add_argument("--timeout", type=float, default=60)
    parser.add_argument("--appearance", choices=("light", "dark", "both"), default="both")
    args = parser.parse_args()
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("--timeout must be a finite positive number")
    if not args.app.is_dir():
        parser.error(f"Simulator app bundle does not exist: {args.app}")
    for device in args.device:
        try:
            uuid.UUID(device)
        except ValueError:
            parser.error(f"Invalid simulator UDID: {device}")
    summary = verify(args)
    print(LIMITATION)
    print(json.dumps(summary, indent=2))
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
