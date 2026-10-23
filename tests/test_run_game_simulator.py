import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location("run_game_simulator", Path(__file__).resolve().parents[1] / "tools/run_game_simulator.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class GameplayTests(unittest.TestCase):
    def test_requires_displacement_in_same_stage_and_process(self):
        status = {"schemaVersion": 1, "scope": "native-game-engine", "pid": 42,
                  "gameFrames": 100, "movementTicks": 60, "stagesLoaded": 2,
                  "inputSamples": 8, "stageInputTicks": 4, "playerPosition": [1, 2, 3],
                  "applicationState": 5, "area": 0, "paused": 0, "cutscene": 0}
        advanced = {**status, "movementTicks": 120, "playerPosition": [20, 2, 3]}
        MODULE.validate_gameplay_sequence([status, advanced])
        for previous in (status, {**status, "area": 15}, {**status, "pid": 43},
                         {**status, "stagesLoaded": 1}, {**status, "paused": 1},
                         {**status, "cutscene": 1}):
            final = {**advanced, "playerPosition": status["playerPosition"]} if previous == status else advanced
            with self.subTest(previous=previous), self.assertRaises(ValueError):
                MODULE.validate_gameplay_sequence([previous, final])

    def test_graphics_errors_fail_even_with_advancing_cpu(self):
        MODULE.validate_graphics_log("[sms_gx] Vulkan initialized\n[port] platform ready")
        for text in ("[mvk-error] VK_ERROR_FEATURE_NOT_PRESENT", "[port] fatal signal SIGSEGV",
                     "[sms_gx] Vulkan: vkQueueSubmit failed (-8)"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                MODULE.validate_graphics_log(text)

    def test_rejects_host_diagnostic_and_partial_boot(self):
        for report in ({}, {"schemaVersion": 1, "scope": "host-metal-only"},
                       {"schemaVersion": 1, "scope": "native-game-engine", "pid": 42, "gameFrames": 100}):
            with self.subTest(report=report), self.assertRaises(ValueError):
                MODULE.validate_gameplay_status(report)

    def test_requires_stage_movement_and_input(self):
        report = {"schemaVersion": 1, "scope": "native-game-engine", "pid": 42,
                  "gameFrames": 100, "movementTicks": 60, "stagesLoaded": 1,
                  "inputSamples": 8, "stageInputTicks": 4, "playerPosition": [1, 2, 3],
                  "applicationState": 5, "area": 0}
        MODULE.validate_gameplay_status(report)
        with self.assertRaises(ValueError):
            MODULE.validate_gameplay_status({**report, "area": 15})
        for key in ("pid", "gameFrames", "movementTicks", "stagesLoaded", "inputSamples", "stageInputTicks"):
            for value in (0, -1, True, "60"):
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    MODULE.validate_gameplay_status({**report, key: value})
        for position in ([True, 2, 3], [float("nan"), 2, 3], [1, 2], [1, "2", 3]):
            with self.subTest(position=position), self.assertRaises(ValueError):
                MODULE.validate_gameplay_status({**report, "playerPosition": position})

    def test_disc_bounds_and_revision(self):
        with tempfile.TemporaryDirectory() as temporary:
            image = Path(temporary) / "test.gcm"
            header = bytearray(0x800)
            header[:8] = b"GMSE01\0\0"
            header[0x1C:0x20] = b"\xc2\x33\x9f\x3d"
            struct.pack_into(">III", header, 0x420, 0x440, 0x600, 12)
            image.write_bytes(header)
            MODULE.inspect_disc(image)
            header[7] = 1
            image.write_bytes(header)
            with self.assertRaises(ValueError):
                MODULE.inspect_disc(image)
            header[7] = 0
            struct.pack_into(">I", header, 0x428, 0x1000)
            image.write_bytes(header)
            with self.assertRaises(ValueError):
                MODULE.inspect_disc(image)


if __name__ == "__main__":
    unittest.main()
