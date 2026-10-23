#!/usr/bin/env python3
"""Install a native game build and collect evidence, without equating boot with playability."""

import argparse
import json
import math
import os
from pathlib import Path
import plistlib
import re
import shutil
import struct
import subprocess
import time


ROOT = Path(__file__).resolve().parents[1]


def inspect_disc(image):
    size = image.stat().st_size
    with image.open("rb") as stream:
        header = stream.read(0x440)
    if len(header) != 0x440 or header[:8] != b"GMSE01\0\0" or header[0x1C:0x20] != b"\xc2\x33\x9f\x3d":
        raise ValueError("An uncompressed North American Sunshine GMSE01 revision 0 disc is required.")
    dol, filesystem, length = struct.unpack_from(">III", header, 0x420)
    if dol < 0x440 or dol + 0x100 > size or filesystem < 0x440 or length < 12 or filesystem + length > size:
        raise ValueError("Disc executable or filesystem lies outside the image.")


def simctl(*arguments, environment=None):
    result = subprocess.run(["xcrun", "simctl", *map(str, arguments)], env=environment,
                            check=True, capture_output=True, text=True, timeout=120)
    return result.stdout.strip()


def validate_gameplay_status(status):
    if status.get("schemaVersion") != 1 or status.get("scope") != "native-game-engine":
        raise ValueError("Not a native game engine telemetry report.")
    if status.get("applicationState") != 5 or type(status.get("area")) is not int or not 0 <= status["area"] <= 9:
        raise ValueError("No primary playable stage; the title/menu stage is not gameplay acceptance.")
    for key in ("pid", "gameFrames", "movementTicks", "stagesLoaded", "inputSamples", "stageInputTicks"):
        if type(status.get(key)) is not int or status[key] <= 0:
            raise ValueError(f"No positive {key} evidence.")
    position = status.get("playerPosition")
    if not isinstance(position, list) or len(position) != 3 or any(
            type(value) not in (int, float) or not math.isfinite(value) for value in position):
        raise ValueError("No player position from an actual game stage.")


def validate_graphics_log(text):
    failures = [line for line in text.splitlines() if re.search(
        r"\[mvk-error\]|\[port\] fatal signal|Vulkan:.*failed|shader compile failed", line)]
    if failures:
        raise ValueError("Engine rendering errors: " + "; ".join(failures[:3]))


def validate_gameplay_sequence(snapshots):
    if not snapshots:
        raise ValueError("No native game telemetry.")
    validate_gameplay_status(snapshots[-1])
    final = snapshots[-1]
    positions = []
    for status in snapshots:
        if (status.get("pid"), status.get("area"), status.get("stagesLoaded")) != (
                final["pid"], final["area"], final["stagesLoaded"]):
            continue
        if status.get("paused") or status.get("cutscene"):
            continue
        try:
            validate_gameplay_status(status)
        except ValueError:
            continue
        positions.append(status["playerPosition"])
    if not positions or not any(math.dist(positions[0], position) > 1 for position in positions[1:]):
        raise ValueError("No observed player displacement within the final playable stage.")
    if len(snapshots) < 2 or final["movementTicks"] <= snapshots[0].get("movementTicks", 0):
        raise ValueError("Game simulation did not advance during observation.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=ROOT / "build/engine-simulator/SunshineGame.app")
    parser.add_argument("--disc", type=Path, required=True, help="Your own local image; never bundled or uploaded")
    parser.add_argument("--device", required=True, help="Exact simulator UDID")
    parser.add_argument("--seconds", type=float, default=120)
    parser.add_argument("--autopress", default="", help="Existing engine SMS_AUTOPRESS script, e.g. START@120,A@240")
    parser.add_argument("--require-gameplay", action="store_true", help="Require error-free logs, playable-stage telemetry, input, and player displacement")
    args = parser.parse_args()
    if args.seconds <= 0:
        parser.error("--seconds must be positive")
    inspect_disc(args.disc)
    with (args.app / "Info.plist").open("rb") as stream:
        bundle = plistlib.load(stream)["CFBundleIdentifier"]
    simctl("bootstatus", args.device, "-b")
    simctl("install", args.device, args.app)
    container = Path(simctl("get_app_container", args.device, bundle, "data"))
    termination = subprocess.run(["xcrun", "simctl", "terminate", args.device, bundle],
                                 capture_output=True, text=True, timeout=30)
    if termination.returncode and not any(message in termination.stderr.lower() for message in
                                         ("not running", "found nothing to terminate")):
        raise RuntimeError(termination.stderr)
    documents = container / "Documents"
    game = documents / "Game"
    game.mkdir(parents=True, exist_ok=True)
    destination = game / "disc.gcm"
    shutil.copy2(args.disc, destination)
    for name in ("gameplay-status.json", "gameplay-status.json.tmp", "game.log", "presence.log"):
        (documents / name).unlink(missing_ok=True)
    environment = os.environ.copy()
    environment["SIMCTL_CHILD_SMS_AUTOPRESS"] = args.autopress
    environment["SIMCTL_CHILD_MTL_DEBUG_LAYER"] = "1"
    launched = simctl("launch", "--terminate-running-process", args.device, bundle, environment=environment)
    print(launched, flush=True)
    evidence = ROOT / "build/validation/gameplay" / args.device / time.strftime("%Y%m%d-%H%M%S")
    evidence.mkdir(parents=True)
    deadline = time.monotonic() + args.seconds
    snapshots = []
    next_capture = 0
    started = time.monotonic()
    while time.monotonic() < deadline:
        time.sleep(min(1, max(0, deadline - time.monotonic())))
        report = documents / "gameplay-status.json"
        if report.exists():
            snapshots.append(json.loads(report.read_text()))
        elapsed = time.monotonic() - started
        if elapsed >= next_capture:
            simctl("io", args.device, "screenshot", evidence / f"second-{int(elapsed)}.png")
            next_capture += 10
    simctl("io", args.device, "screenshot", evidence / "final.png")
    for name in ("gameplay-status.json", "game.log", "presence.log"):
        if (documents / name).exists():
            shutil.copy2(documents / name, evidence / name)
    summary = {"device": args.device, "bundle": bundle, "launch": launched,
               "snapshots": snapshots, "autopress": args.autopress,
               "limitation": "Telemetry alone does not prove correct graphics or human playability; inspect screenshots and exercise controls."}
    (evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"Evidence: {evidence}")
    if args.require_gameplay:
        validate_graphics_log((documents / "game.log").read_text())
        if not snapshots:
            raise SystemExit("FAIL: no game-engine telemetry; a successful app launch is not a game boot.")
        validate_gameplay_sequence(snapshots)
        launched_pid = int(launched.rpartition(":")[2].strip())
        if snapshots[-1]["pid"] != launched_pid:
            raise SystemExit("FAIL: telemetry belongs to another process.")
        os.kill(launched_pid, 0)


if __name__ == "__main__":
    main()
