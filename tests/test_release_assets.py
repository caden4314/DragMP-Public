"""Offline checks for strict DragMP GitHub Release verification."""
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "verify_release_assets", ROOT / "scripts" / "verify_release_assets.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReleaseVerificationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.build = self.root / "build"
        self.build.mkdir()
        self.name = "DragMP-test.zip"
        self.content = b"reproducible-test-archive"
        (self.build / self.name).write_bytes(self.content)
        self.release = self.root / "release.json"
        self.metadata = {
            "draft": False,
            "assets": [{
                "name": self.name,
                "state": "uploaded",
                "digest": "sha256:" + hashlib.sha256(self.content).hexdigest(),
            }],
        }
        self.store()

    def store(self):
        self.release.write_text(json.dumps(self.metadata), encoding="utf-8")

    def test_complete_matching_release(self):
        module.verify(self.build, self.release, [self.name])

    def test_changed_remote_digest_is_rejected(self):
        self.metadata["assets"][0]["digest"] = "sha256:" + "0" * 64
        self.store()
        with self.assertRaisesRegex(ValueError, "checksum mismatch"):
            module.verify(self.build, self.release, [self.name])

    def test_changed_local_archive_is_rejected(self):
        (self.build / self.name).write_bytes(b"tampered")
        with self.assertRaisesRegex(ValueError, "checksum mismatch"):
            module.verify(self.build, self.release, [self.name])

    def test_missing_asset_is_rejected(self):
        self.metadata["assets"] = []
        self.store()
        with self.assertRaisesRegex(ValueError, "missing or incomplete"):
            module.verify(self.build, self.release, [self.name])

    def test_incomplete_upload_is_rejected(self):
        self.metadata["assets"][0]["state"] = "starter"
        self.store()
        with self.assertRaisesRegex(ValueError, "missing or incomplete"):
            module.verify(self.build, self.release, [self.name])

    def test_draft_is_rejected(self):
        self.metadata["draft"] = True
        self.store()
        with self.assertRaisesRegex(ValueError, "draft"):
            module.verify(self.build, self.release, [self.name])

    def test_asset_traversal_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "unsafe"):
            module.verify(self.build, self.release, ["../secret"])

    def test_absent_digest_is_rejected(self):
        del self.metadata["assets"][0]["digest"]
        self.store()
        with self.assertRaisesRegex(ValueError, "checksum mismatch"):
            module.verify(self.build, self.release, [self.name])


if __name__ == "__main__":
    unittest.main()
