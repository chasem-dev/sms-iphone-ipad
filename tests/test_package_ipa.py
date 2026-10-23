import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile


SPEC = importlib.util.spec_from_file_location("package_ipa", Path(__file__).resolve().parents[1] / "tools/package_ipa.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / "Sunshine.app"
        self.app.mkdir()
        self.info = {"CFBundleExecutable": "Sunshine", "CFBundleSupportedPlatforms": ["iPhoneOS"]}
        self.write_info()
        executable = self.app / "Sunshine"
        executable.write_bytes(b"synthetic executable")
        executable.chmod(0o755)
        self.output = self.root / "Sunshine.ipa"

    def write_info(self):
        (self.app / "Info.plist").write_bytes(plistlib.dumps(self.info))

    def test_payload_and_permissions(self):
        MODULE.package(self.app, self.output)
        with zipfile.ZipFile(self.output) as archive:
            self.assertEqual(set(archive.namelist()), {"Payload/Sunshine.app/Info.plist", "Payload/Sunshine.app/Sunshine"})
            self.assertEqual((archive.getinfo("Payload/Sunshine.app/Sunshine").external_attr >> 16) & 0o777, 0o755)

    def test_rejects_simulator(self):
        self.info["CFBundleSupportedPlatforms"] = ["iPhoneSimulator"]
        self.write_info()
        with self.assertRaisesRegex(ValueError, "device build"):
            MODULE.package(self.app, self.output)

    def test_rejects_game_images(self):
        (self.app / "disc.gcm").write_bytes(b"not actual game data")
        with self.assertRaisesRegex(ValueError, "game assets"):
            MODULE.package(self.app, self.output)
        self.assertFalse(self.output.exists())

    def test_rejects_missing_executable(self):
        (self.app / "Sunshine").unlink()
        with self.assertRaisesRegex(ValueError, "executable"):
            MODULE.package(self.app, self.output)

    def test_rejects_symlinks(self):
        (self.app / "link").symlink_to(self.app / "Sunshine")
        with self.assertRaisesRegex(ValueError, "Symlinks"):
            MODULE.package(self.app, self.output)

    def test_rejects_output_in_bundle(self):
        with self.assertRaisesRegex(ValueError, "outside"):
            MODULE.package(self.app, self.app / "nested.ipa")


if __name__ == "__main__":
    unittest.main()
