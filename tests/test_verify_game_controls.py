import importlib.util
from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
try:
    SPEC = importlib.util.spec_from_file_location("verify_game_controls", TOOLS / "verify_game_controls.py")
    MODULE = importlib.util.module_from_spec(SPEC)
    SPEC.loader.exec_module(MODULE)
finally:
    sys.path.pop(0)


class TouchControlTests(unittest.TestCase):
    def sequence(self):
        initial = {"schemaVersion": 1, "scope": "native-game-engine", "pid": 42,
                   "gameFrames": 100, "movementTicks": 60, "stagesLoaded": 2,
                   "inputSamples": 8, "stageInputTicks": 4, "playerPosition": [0, 0, 0],
                   "applicationState": 5, "area": 0, "paused": 0, "cutscene": 0,
                   "touchPresses": 0, "cameraInputSamples": 0, "buttons": 0,
                   "stickX": 0, "stickY": 0, "cameraX": 0, "cameraY": 0}
        jumping = {**initial, "playerPosition": [30, 80, 0], "buttons": 0x100}
        paused = {**initial, "paused": 1}
        final = {**initial, "playerPosition": [30, 0, 0], "movementTicks": 200,
                 "touchPresses": 5, "cameraInputSamples": 10}
        return [initial, jumping, paused, final]

    def test_accepts_actual_touch_evidence(self):
        MODULE.validate_controls(self.sequence())

    def test_rejects_missing_actions_and_stuck_controls(self):
        for key, value in (("touchPresses", 4), ("cameraInputSamples", 0), ("paused", 1),
                           ("stickX", 10), ("buttons", 0x100), ("cameraY", 10),
                           ("pid", 43), ("stagesLoaded", 3)):
            snapshots = self.sequence()
            snapshots[-1][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                MODULE.validate_controls(snapshots)

    def test_rejects_absent_jump_or_pause(self):
        for index in (1, 2):
            snapshots = self.sequence()
            snapshots.pop(index)
            with self.subTest(index=index), self.assertRaises(ValueError):
                MODULE.validate_controls(snapshots)


if __name__ == "__main__":
    unittest.main()
