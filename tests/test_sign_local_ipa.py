import datetime
import hashlib
import io
import json
from pathlib import Path
import plistlib
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import sign_local_ipa as signing


class SigningTests(unittest.TestCase):
    def setUp(self):
        self.profile = {
            "ExpirationDate": datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=7),
            "TeamIdentifier": ["TEAM123456"], "ApplicationIdentifierPrefix": ["OLDP123456"],
            "ProvisionedDevices": ["DEVICE"], "DeveloperCertificates": [b"certificate"],
            "Entitlements": {"application-identifier": "OLDP123456." + signing.BUNDLE,
                             "com.apple.developer.team-identifier": "TEAM123456", "get-task-allow": True},
        }
        self.info = {"CFBundleIdentifier": signing.BUNDLE, "CFBundleExecutable": "SunshineGame",
                     "CFBundleSupportedPlatforms": ["iPhoneOS"], "SMSLocalOnly": True,
                     "SMSLocalBundledDisc": "LocalGame/disc.gcm"}

    def make_archive(self, extra=None):
        data = io.BytesIO()
        with zipfile.ZipFile(data, "w") as archive:
            archive.writestr("Payload/SunshineGame.app/Info.plist", plistlib.dumps(self.info))
            archive.writestr("Payload/SunshineGame.app/SunshineGame", b"executable")
            archive.writestr("Payload/SunshineGame.app/LocalGame/disc.gcm", b"local fixture")
            if extra:
                archive.writestr(*extra)
        data.seek(0)
        return data

    def test_profile_uses_application_prefix_not_team(self):
        entitlements = signing.validate_profile(self.profile, "DEVICE", "TEAM123456")
        self.assertEqual(entitlements["application-identifier"], "OLDP123456." + signing.BUNDLE)
        self.assertNotIn("com.apple.developer.kernel.increased-memory-limit", entitlements)

    def test_expired_profile_rejected(self):
        self.profile["ExpirationDate"] = datetime.datetime(2020, 1, 1)
        with self.assertRaisesRegex(ValueError, "expired"):
            signing.validate_profile(self.profile, "DEVICE")

    def test_unregistered_device_rejected(self):
        with self.assertRaisesRegex(ValueError, "not registered"):
            signing.validate_profile(self.profile, "OTHER")

    def test_wrong_team_rejected(self):
        with self.assertRaisesRegex(ValueError, "different team"):
            signing.validate_profile(self.profile, "DEVICE", "WRONGTEAM1")

    def test_wrong_bundle_and_nonmatching_wildcard_rejected(self):
        for identifier in ["OLDP123456.other.*", "OLDP123456.other.app", "OTHER12345.*", "OLDP123456.*sunshine*"]:
            self.profile["Entitlements"]["application-identifier"] = identifier
            with self.assertRaisesRegex(ValueError, "authorize the Sunshine"):
                signing.validate_profile(self.profile, "DEVICE")

    def test_matching_wildcards_expand_to_exact_signed_app_id(self):
        for identifier in ["OLDP123456.*", "OLDP123456.dev.chasem.*"]:
            self.profile["Entitlements"]["application-identifier"] = identifier
            entitlements = signing.validate_profile(self.profile, "DEVICE")
            self.assertEqual(entitlements["application-identifier"], "OLDP123456." + signing.BUNDLE)
            self.assertNotIn("*", entitlements["application-identifier"])

    def test_distribution_profile_rejected(self):
        self.profile["Entitlements"]["get-task-allow"] = False
        with self.assertRaisesRegex(ValueError, "development profiles"):
            signing.validate_profile(self.profile, "DEVICE")

    def test_team_entitlement_must_match(self):
        self.profile["Entitlements"]["com.apple.developer.team-identifier"] = "OTHER"
        with self.assertRaisesRegex(ValueError, "inconsistent"):
            signing.validate_profile(self.profile, "DEVICE")

    def test_matching_private_key_identity_required(self):
        identity = hashlib.sha1(b"certificate").hexdigest().upper()
        self.assertEqual(signing.select_identity(self.profile, f'1) {identity} "Apple Development"'), identity)
        with self.assertRaisesRegex(ValueError, "private key"):
            signing.select_identity(self.profile, "0 valid identities found")

    def test_accepts_private_device_archive(self):
        with zipfile.ZipFile(self.make_archive()) as archive:
            self.assertEqual(signing.validate_archive(archive), self.info)

    def test_rejects_unsafe_archive_paths(self):
        for name in ["../escape", "/absolute", "Payload/Other.app/file",
                     "Payload/SunshineGame.app/../escape", "Payload/SunshineGame.app//file",
                     "Payload/SunshineGame.app/Frameworks/Other.framework/Other"]:
            with self.subTest(name=name), zipfile.ZipFile(self.make_archive((name, b"bad"))) as archive:
                with self.assertRaises(ValueError):
                    signing.validate_archive(archive)

    def test_rejects_archive_symlink(self):
        entry = zipfile.ZipInfo("Payload/SunshineGame.app/link")
        entry.create_system = 3
        entry.external_attr = 0o120777 << 16
        with zipfile.ZipFile(self.make_archive((entry, b"outside"))) as archive:
            with self.assertRaisesRegex(ValueError, "symlink"):
                signing.validate_archive(archive)

    def test_rejects_simulator(self):
        self.info["CFBundleSupportedPlatforms"] = ["iPhoneSimulator"]
        with zipfile.ZipFile(self.make_archive()) as archive:
            with self.assertRaisesRegex(ValueError, "private preloaded"):
                signing.validate_archive(archive)

    def test_signing_prerequisite_failure_preserves_input_and_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa, output = root / "unsigned.ipa", root / "signed.ipa"
            ipa.write_bytes(self.make_archive().getvalue())
            original = ipa.read_bytes()
            output.write_bytes(b"previous signed output")
            with patch.object(signing, "PRIVATE_DIRECTORY", root), patch.object(
                    signing, "resolve_device", return_value="DEVICE"), patch.object(
                    signing, "provision", side_effect=ValueError("No Accounts")):
                with self.assertRaisesRegex(ValueError, "No Accounts"):
                    signing.sign_local(ipa, output, "DEVICE", team="TEAM123456")
            self.assertEqual(ipa.read_bytes(), original)
            self.assertEqual(output.read_bytes(), b"previous signed output")
            self.assertFalse(list(root.glob("sign-private-*")))

    def test_rejects_same_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa = root / "unsigned.ipa"
            ipa.write_bytes(self.make_archive().getvalue())
            with patch.object(signing, "PRIVATE_DIRECTORY", root):
                with self.assertRaisesRegex(ValueError, "distinct output"):
                    signing.sign_local(ipa, ipa, "DEVICE", team="TEAM123456")

    def test_signing_sequence_and_private_output_with_mock_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa, output = root / "unsigned.ipa", root / "signed.ipa"
            ipa.write_bytes(self.make_archive().getvalue())
            original = ipa.read_bytes()
            profile_path = root / "Sunshine.mobileprovision"
            profile_path.write_bytes(b"mock profile envelope")
            profile = dict(self.profile)
            profile["ExpirationDate"] = profile["ExpirationDate"].replace(tzinfo=None)
            expected_entitlements = signing.validate_profile(profile, "DEVICE")
            identity = hashlib.sha1(b"certificate").hexdigest().upper()

            def read_command(command, **kwargs):
                if command[:2] == ["security", "cms"]:
                    return plistlib.dumps(profile)
                if command[:2] == ["security", "find-identity"]:
                    return f'1) {identity} "Apple Development"'
                self.assertEqual(command[:3], ["codesign", "-d", "--entitlements"])
                return plistlib.dumps(expected_entitlements)

            def run_command(command, **kwargs):
                self.assertEqual(command[0], "codesign")
                if "--sign" in command:
                    self.assertEqual(command[command.index("--sign") + 1], identity)
                    app = Path(command[-1])
                    self.assertEqual((app / "embedded.mobileprovision").read_bytes(), b"mock profile envelope")
                    self.assertEqual((app / "SunshineGame").stat().st_mode & 0o777, 0o755)
                    (app / "_CodeSignature").mkdir()
                    (app / "_CodeSignature/CodeResources").write_bytes(b"mock signature")
                return subprocess.CompletedProcess(command, 0, "", "Authority=Apple Development")

            with patch.object(signing, "PRIVATE_DIRECTORY", root), patch.object(
                    signing, "resolve_device", return_value="DEVICE"), patch.object(
                    signing.subprocess, "check_output", side_effect=read_command), patch.object(
                    signing.subprocess, "run", side_effect=run_command) as commands:
                self.assertEqual(signing.sign_local(ipa, output, "DEVICE", profile_path=profile_path), output.resolve())
            self.assertEqual(commands.call_count, 4)
            self.assertEqual(ipa.read_bytes(), original)
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(archive.read("Payload/SunshineGame.app/LocalGame/disc.gcm"), b"local fixture")
                self.assertEqual(archive.read("Payload/SunshineGame.app/embedded.mobileprovision"), b"mock profile envelope")
            receipt = json.loads(output.with_suffix(".json").read_text())
            self.assertTrue(receipt["signatureVerified"])
            self.assertFalse(receipt["installed"])
            self.assertEqual(receipt["ipaSHA256"], hashlib.sha256(output.read_bytes()).hexdigest())
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)
            self.assertEqual(output.with_suffix(".json").stat().st_mode & 0o777, 0o600)
            self.assertFalse(list(root.glob("sign-private-*")))


if __name__ == "__main__":
    unittest.main()
