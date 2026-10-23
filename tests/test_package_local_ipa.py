import importlib.util
import json
from pathlib import Path
import plistlib
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile


TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
SPEC = importlib.util.spec_from_file_location("package_local_ipa", TOOLS / "package_local_ipa.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class LocalPackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / "SunshineGame.app"
        self.app.mkdir()
        self.info = {"CFBundleSupportedPlatforms": ["iPhoneOS"], "CFBundleExecutable": "SunshineGame",
                     "CFBundleIdentifier": "dev.chasem.sunshine.game"}
        self.write_info()
        (self.app / "SunshineGame").write_bytes(b"synthetic executable")
        (self.app / "SunshineGame").chmod(0o755)
        self.disc = self.root / "own.iso"
        image = bytearray(0x800)
        image[:8] = b"GMSE01\0\0"
        image[0x1c:0x20] = b"\xc2\x33\x9f\x3d"
        struct.pack_into(">III", image, 0x420, 0x440, 0x600, 12)
        struct.pack_into(">III", image, 0x600, 0x01000000, 0, 1)
        self.disc.write_bytes(image)
        self.private = self.root / "build/local-private"
        self.output = self.private / "personal.ipa"
        directory = patch.object(MODULE, "PRIVATE_DIRECTORY", self.private)
        directory.start()
        self.addCleanup(directory.stop)

    def write_info(self):
        (self.app / "Info.plist").write_bytes(plistlib.dumps(self.info))

    def test_preloaded_private_bundle_preserves_source(self):
        original_info = (self.app / "Info.plist").read_bytes()
        MODULE.package_local(self.app, self.disc, self.output)
        self.assertEqual((self.app / "Info.plist").read_bytes(), original_info)
        self.assertFalse((self.app / "LocalGame").exists())
        with zipfile.ZipFile(self.output) as archive:
            self.assertEqual(archive.read("Payload/SunshineGame.app/LocalGame/disc.gcm"), self.disc.read_bytes())
            info = plistlib.loads(archive.read("Payload/SunshineGame.app/Info.plist"))
            self.assertIs(info["SMSLocalOnly"], True)
            self.assertEqual(info["SMSLocalBundledDisc"], "LocalGame/disc.gcm")
            mode = archive.getinfo("Payload/SunshineGame.app/SunshineGame").external_attr >> 16
            self.assertEqual(mode & 0o777, 0o755)
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.private.stat().st_mode & 0o777, 0o700)
        report_path = self.output.with_suffix(".json")
        self.assertEqual(report_path.stat().st_mode & 0o777, 0o600)
        report = json.loads(report_path.read_text())
        self.assertEqual(report["discSHA256"], report["embeddedDiscSHA256"])
        self.assertIs(report["gameplayOnPhysicalDeviceVerified"], False)
        self.assertIn("unsigned", report["signing"])
        self.assertEqual(sorted(path.name for path in self.private.iterdir()), ["personal.ipa", "personal.json"])

    def test_rejects_output_outside_ignored_private_directory(self):
        with self.assertRaisesRegex(ValueError, "must stay under"):
            MODULE.package_local(self.app, self.disc, self.root / "share.ipa")

    def test_optional_icon_is_staged_and_reported(self):
        artwork = self.root / "artwork.png"
        artwork.write_bytes(b"synthetic artwork")

        def compile_fixture(source, staged, temporary):
            self.assertEqual(source, artwork.resolve())
            self.assertNotEqual(staged, self.app)
            (staged / "Assets.car").write_bytes(b"synthetic compiled catalog")
            primary = {"CFBundlePrimaryIcon": {"CFBundleIconName": "AppIcon", "CFBundleIconFiles": ["AppIcon60x60"]}}
            return {"CFBundleIcons": primary, "CFBundleIcons~ipad": primary}

        with patch.object(MODULE, "compile_icon", side_effect=compile_fixture) as compiler:
            MODULE.package_local(self.app, self.disc, self.output, artwork)
        compiler.assert_called_once()
        self.assertFalse((self.app / "Assets.car").exists())
        report = json.loads(self.output.with_suffix(".json").read_text())
        self.assertEqual(report["appIcon"]["name"], "AppIcon")
        self.assertEqual(report["appIcon"]["devices"], ["iphone", "ipad"])

    def test_icon_cannot_be_overwritten_by_output(self):
        self.private.mkdir(parents=True)
        self.output.write_bytes(b"artwork")
        with self.assertRaisesRegex(ValueError, "separate source image"):
            MODULE.package_local(self.app, self.disc, self.output, self.output)
        self.assertEqual(self.output.read_bytes(), b"artwork")

    def test_rejects_simulator_and_preserves_previous_output(self):
        self.private.mkdir(parents=True)
        self.output.write_bytes(b"previous")
        self.info["CFBundleSupportedPlatforms"] = ["iPhoneSimulator"]
        self.write_info()
        with self.assertRaisesRegex(ValueError, "device build"):
            MODULE.package_local(self.app, self.disc, self.output)
        self.assertEqual(self.output.read_bytes(), b"previous")

    def test_rejects_diagnostic_host(self):
        self.info["CFBundleExecutable"] = "Sunshine"
        self.write_info()
        with self.assertRaisesRegex(ValueError, "native SunshineGame"):
            MODULE.package_local(self.app, self.disc, self.output)

    def test_rejects_invalid_disc(self):
        self.disc.write_bytes(b"not a disc")
        with self.assertRaisesRegex(ValueError, "disc is required"):
            MODULE.package_local(self.app, self.disc, self.output)
        self.assertFalse(self.output.exists())

    def test_removes_stale_signing_only_from_staged_copy(self):
        signature = self.app / "_CodeSignature"
        signature.mkdir()
        (signature / "CodeResources").write_bytes(b"old signature")
        (self.app / "embedded.mobileprovision").write_bytes(b"old profile")
        MODULE.package_local(self.app, self.disc, self.output)
        with zipfile.ZipFile(self.output) as archive:
            self.assertFalse(any("_CodeSignature" in name or name.endswith("mobileprovision") for name in archive.namelist()))
        self.assertTrue((signature / "CodeResources").exists())
        self.assertTrue((self.app / "embedded.mobileprovision").exists())

    def test_still_rejects_other_game_asset_files(self):
        (self.app / "other.iso").write_bytes(b"fixture")
        with self.assertRaisesRegex(ValueError, "game assets"):
            MODULE.package_local(self.app, self.disc, self.output)
        self.assertFalse(self.output.exists())

    def test_rejects_already_bundled_source(self):
        (self.app / "LocalGame").mkdir()
        with self.assertRaisesRegex(ValueError, "asset-free"):
            MODULE.package_local(self.app, self.disc, self.output)

    def test_metadata_cannot_overwrite_input_disc(self):
        self.private.mkdir(parents=True)
        selected = self.output.with_suffix(".json")
        selected.write_bytes(self.disc.read_bytes())
        with self.assertRaisesRegex(ValueError, "overwrite"):
            MODULE.package_local(self.app, selected, self.output)


if __name__ == "__main__":
    unittest.main()
