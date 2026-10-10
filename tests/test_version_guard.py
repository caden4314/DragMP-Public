"""Version guard tests to prevent same-tag code changes."""
import importlib.util
from pathlib import Path
import unittest

src = Path(__file__).resolve().parents[1] / "scripts" / "guard_release_version.py"
spec = importlib.util.spec_from_file_location("guard", src)
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class VersionPolicyTests(unittest.TestCase):
    def test_source_modified_same_version_rejected(self):
        self.assertTrue(guard.must_advance(["src/client/main.lua"], "1.0.0-private.1", "1.0.0-private.1"))

    def test_source_modified_new_version_allowed(self):
        self.assertFalse(guard.must_advance(["src/server/main.lua"], "1.0.0-private.1", "1.0.0-private.2"))

    def test_builder_only_change_can_keep_version(self):
        self.assertFalse(guard.must_advance(["deploy/vps-builder/start.sh"], "1.0.0-private.1", "1.0.0-private.1"))


if __name__ == "__main__":
    unittest.main()
