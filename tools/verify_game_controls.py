#!/usr/bin/env python3
"""Exercise real UIKit touches against an already-running playable simulator stage."""

import argparse
import json
from pathlib import Path
import subprocess
import time

from run_game_simulator import ROOT, simctl, validate_gameplay_sequence, validate_graphics_log


def validate_controls(snapshots):
    validate_gameplay_sequence(snapshots)
    first, final = snapshots[0], snapshots[-1]
    if any(status.get("pid") != first["pid"] or status.get("stagesLoaded") != first["stagesLoaded"]
           for status in snapshots):
        raise ValueError("Process or stage changed during touch verification.")
    if final.get("touchPresses", 0) - first.get("touchPresses", 0) < 5:
        raise ValueError("Native UIKit button presses were not observed.")
    if final.get("cameraInputSamples", 0) <= first.get("cameraInputSamples", 0):
        raise ValueError("Camera input did not reach the game PAD path.")
    if not any(status.get("paused") == 1 for status in snapshots) or final.get("paused") != 0:
        raise ValueError("Pause/resume was not observed.")
    heights = [status["playerPosition"][1] for status in snapshots if status.get("playerPosition")]
    if not heights or max(heights) - min(heights) <= 20 or not any(status.get("buttons", 0) & 0x100 for status in snapshots):
        raise ValueError("Jump button and vertical player movement were not observed.")
    if any(final.get(key, 0) for key in ("buttons", "stickX", "stickY", "cameraX", "cameraY")):
        raise ValueError("A control remains held after the touch sequence.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    args = parser.parse_args()
    documents = Path(simctl("get_app_container", args.device, "dev.chasem.sunshine.game", "data")) / "Documents"
    report = documents / "gameplay-status.json"
    first = json.loads(report.read_text())
    if first.get("applicationState") != 5 or not 0 <= first.get("area", 15) <= 9 or first.get("paused"):
        raise SystemExit("Load an unpaused playable stage, finish dialogue, and disable scripted input first.")
    evidence = ROOT / "build/validation/touch" / args.device / time.strftime("%Y%m%d-%H%M%S")
    evidence.mkdir(parents=True)
    snapshots = [first]
    with (evidence / "xcodebuild.log").open("w") as log:
        process = subprocess.Popen(["xcodebuild", "-project", str(ROOT / "tests/ui/GameUITests.xcodeproj"),
            "-scheme", "GameUITests", "-destination", f"platform=iOS Simulator,id={args.device}",
            "-derivedDataPath", str(ROOT / "build/ui-tests"), "-resultBundlePath", str(evidence / "touch.xcresult"),
            "-only-testing:GameUITests/GameUITests/testNativeTouchControls",
            "-parallel-testing-enabled", "NO", "test"], stdout=log, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 180
        while process.poll() is None and time.monotonic() < deadline:
            if report.exists():
                snapshots.append(json.loads(report.read_text()))
            time.sleep(0.1)
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=30)
        snapshots.append(json.loads(report.read_text()))
    (evidence / "telemetry.json").write_text(json.dumps(snapshots, indent=2) + "\n")
    simctl("io", args.device, "screenshot", evidence / "final.png")
    print(f"Evidence: {evidence}")
    if process.returncode:
        raise SystemExit(f"XCTest failed ({process.returncode}); see xcodebuild.log.")
    validate_graphics_log((documents / "game.log").read_text())
    validate_controls(snapshots)
    print("PASS: native touch movement, jump, camera input, pause/resume, and key release.")


if __name__ == "__main__":
    main()
