import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("prepare_engine", Path(__file__).resolve().parents[1] / "tools/prepare_engine.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PrepareTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.source = Path(self.temporary.name) / "engine"
        (self.source / ".git").mkdir(parents=True)
        self.lock = {"repository": "https://example.invalid/engine.git", "commit": "parent", "submodules": {"decomp": "child"}}

    def fake_git(self, *args, cwd=None):
        if args[:2] == ("submodule", "update"):
            (self.source / "decomp").mkdir(exist_ok=True)
            (self.source / "decomp/.git").touch()
        if args == ("rev-parse", "HEAD"):
            return "child" if cwd == self.source / "decomp" else "parent"
        return ""

    def test_resumes_existing_cache_with_uninitialized_submodule(self):
        with patch.object(MODULE, "git", side_effect=self.fake_git) as git:
            MODULE.prepare(self.source, self.lock, managed=True)
            git.assert_any_call("submodule", "update", "--init", "--recursive", cwd=self.source)
            self.assertFalse(any(call.args[0] == "clone" for call in git.call_args_list))
        self.assertTrue((self.source / "decomp/.git").exists())

    def test_local_verification_never_initializes_missing_submodule(self):
        with patch.object(MODULE, "git", side_effect=self.fake_git) as git:
            with self.assertRaisesRegex(SystemExit, "Submodule decomp"):
                MODULE.prepare(self.source, self.lock, managed=False)
            self.assertTrue(all(call.args[0] in {"rev-parse", "status"} for call in git.call_args_list))

    def test_refuses_dirty_cache_before_mutation(self):
        with patch.object(MODULE, "git", return_value=" M source.cpp") as git:
            with self.assertRaisesRegex(SystemExit, "tracked modifications"):
                MODULE.prepare(self.source, self.lock, managed=True)
            self.assertEqual(git.call_count, 1)


if __name__ == "__main__":
    unittest.main()
