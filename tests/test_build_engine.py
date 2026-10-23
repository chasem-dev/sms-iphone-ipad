import argparse
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("build_engine", Path(__file__).resolve().parents[1] / "tools/build_engine.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class EngineBuildTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.reference = self.root / "reference"
        self.cache = self.root / "cache"
        self.reference.mkdir()
        self.git("init", "-q", cwd=self.reference)
        (self.reference / "CMakeLists.txt").write_text("original\n")
        self.git("add", ".", cwd=self.reference)
        self.git("-c", "user.name=Build Test", "-c", "user.email=test@example.invalid",
                 "commit", "-qm", "fixture", cwd=self.reference)
        self.lock = {"repository": "unused", "commit": self.git("rev-parse", "HEAD", cwd=self.reference), "submodules": {}}
        self.patch = self.root / "engine.patch"
        self.write_patch("patched")

    def git(self, *args, cwd):
        return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()

    def write_patch(self, replacement):
        self.patch.write_text("diff --git a/CMakeLists.txt b/CMakeLists.txt\n"
                              "--- a/CMakeLists.txt\n+++ b/CMakeLists.txt\n"
                              f"@@ -1 +1 @@\n-original\n+{replacement}\n")

    def prepare(self):
        MODULE.prepare_engine(self.reference, self.cache, self.lock, [self.patch])

    def test_isolated_clone_and_idempotent_patches(self):
        self.prepare()
        self.prepare()
        self.assertEqual((self.cache / "CMakeLists.txt").read_text(), "patched\n")
        self.assertEqual((self.reference / "CMakeLists.txt").read_text(), "original\n")
        self.assertEqual(self.git("status", "--porcelain", cwd=self.reference), "")
        self.assertEqual(self.git("rev-parse", "HEAD", cwd=self.cache), self.lock["commit"])

    def test_patch_revision_replaces_only_known_edits(self):
        self.prepare()
        self.write_patch("revised")
        self.prepare()
        self.assertEqual((self.cache / "CMakeLists.txt").read_text(), "revised\n")

    def test_unknown_cache_edit_is_preserved(self):
        self.prepare()
        (self.cache / "CMakeLists.txt").write_text("user edit\n")
        with self.assertRaisesRegex(SystemExit, "unexpected edits"):
            self.prepare()
        self.assertEqual((self.cache / "CMakeLists.txt").read_text(), "user edit\n")

    def test_bad_patch_revision_restores_previous_managed_edits(self):
        self.prepare()
        self.patch.write_text(self.patch.read_text().replace("-original", "-missing"))
        with self.assertRaises(subprocess.CalledProcessError):
            self.prepare()
        self.assertEqual((self.cache / "CMakeLists.txt").read_text(), "patched\n")
        self.write_patch("recovered")
        self.prepare()
        self.assertEqual((self.cache / "CMakeLists.txt").read_text(), "recovered\n")

    def test_missing_applied_patch_is_not_silently_accepted(self):
        self.prepare()
        (self.cache / "CMakeLists.txt").write_text("original\n")
        with self.assertRaisesRegex(SystemExit, "unexpected edits"):
            self.prepare()

    def test_reference_cannot_be_cache(self):
        with self.assertRaisesRegex(SystemExit, "must not be the reference"):
            MODULE.prepare_engine(self.reference, self.reference, self.lock, [])

    def test_simulator_compilers_have_explicit_target(self):
        args = argparse.Namespace(build_dir=self.root / "build", llvm_bin=Path("/llvm/bin"),
                                  moltenvk=Path("/simulator/libMoltenVK.a"), game_main=Path("/GameMain.mm"),
                                  info_plist=Path("/GameInfo.plist.in"), cmake_arg=[])
        command = list(map(str, MODULE.configure_command(args, self.cache, "/sdl", "/host/plugin.dylib", "/sim-sdk")))
        for language in ("C", "CXX", "OBJC", "OBJCXX"):
            self.assertIn(f"-DCMAKE_{language}_COMPILER_TARGET=arm64-apple-ios15.0-simulator", command)
        self.assertIn("-DCMAKE_OSX_SYSROOT=/sim-sdk", command)
        self.assertIn("-DCMAKE_RANLIB=/usr/bin/ranlib", command)

    def test_plugin_uses_host_sdk_and_target(self):
        plugin_source = self.reference / "tools/gameptr/GamePtrPass.cpp"
        plugin_source.parent.mkdir(parents=True)
        plugin_source.write_text("fixture")
        def fake_run(*command, **kwargs):
            if command[0] == "xcrun":
                return "/mac-sdk"
            if command[-1] == "--cxxflags":
                return "-I/llvm/include -std=c++17"
            return "clang fixture"
        with patch.object(MODULE, "run", side_effect=fake_run) as runner:
            MODULE.build_host_plugin(Path("/llvm/bin"), self.reference, self.root / "build")
        command = next(call.args for call in runner.call_args_list if "-shared" in call.args)
        self.assertIn("--target=arm64-apple-macos", command)
        self.assertEqual(command[command.index("-isysroot") + 1], "/mac-sdk")
        self.assertNotIn("--target=arm64-apple-ios15.0-simulator", command)

    def test_sdl_checksum_checked_before_extraction(self):
        downloads = self.root / "downloads"
        downloads.mkdir()
        (downloads / f"SDL2-{MODULE.SDL_VERSION}.tar.gz").write_bytes(b"bad archive")
        with self.assertRaisesRegex(SystemExit, "checksum mismatch"):
            MODULE.prepare_sdl(self.root)


if __name__ == "__main__":
    unittest.main()
