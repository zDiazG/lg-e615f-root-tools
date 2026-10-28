import hashlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts/bootstrap-sources.py"
SPEC = importlib.util.spec_from_file_location("bootstrap_sources", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FakeResponse(io.BytesIO):
    def __init__(self, body: bytes, url: str):
        super().__init__(body)
        self.headers = {"Content-Length": str(len(body))}
        self.url = url

    def geturl(self):
        return self.url

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, traceback):
        self.close()


class BootstrapSourcesTests(unittest.TestCase):
    def source(self, root: Path, body: bytes = b"pinned test payload"):
        return {
            "url": "https://example.invalid/package.bin",
            "path": "sources/package.bin",
            "size_bytes": len(body),
            "sha256": hashlib.sha256(body).hexdigest(),
            "license_note": "fixture",
        }

    def test_manifest_rejects_http_and_path_traversal(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "manifest.json"
            data = {"schema_version": 1, "sources": {"bad": self.source(Path(directory))}}
            data["sources"]["bad"]["url"] = "http://example.invalid/source"
            manifest.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError, "HTTPS"):
                MODULE.load_manifest(manifest)

            data["sources"]["bad"]["url"] = "https://example.invalid/source"
            data["sources"]["bad"]["path"] = "../outside.bin"
            manifest.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError, "stay inside"):
                MODULE.load_manifest(manifest)

    def test_dry_run_plans_without_creating_source_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            item = self.source(root)
            target = MODULE.destination_for("fixture", item, root)
            self.assertFalse(target.parent.exists())
            rendered = MODULE.plan_source("fixture", item, root)
            self.assertIn("https://example.invalid/package.bin", rendered)
            self.assertIn(str(target), rendered)
            self.assertFalse(target.parent.exists())

    def test_fetch_verifies_hash_and_writes_atomically(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            body = b"pinned test payload"
            item = self.source(root, body)
            response = FakeResponse(body, "https://cdn.example.invalid/package.bin")
            with patch.object(MODULE.urllib.request, "urlopen", return_value=response):
                target = MODULE.fetch_source("fixture", item, root)
            self.assertEqual(target.read_bytes(), body)
            self.assertEqual(MODULE.file_digest(target), item["sha256"])
            self.assertEqual(list(target.parent.glob("*.part")), [])

    def test_fetch_rejects_hash_mismatch_without_leaving_partial_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            item = self.source(root)
            item["sha256"] = "0" * 64
            response = FakeResponse(b"pinned test payload", item["url"])
            with patch.object(MODULE.urllib.request, "urlopen", return_value=response):
                with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                    MODULE.fetch_source("fixture", item, root)
            self.assertFalse((root / "sources/package.bin").exists())
            self.assertEqual(list((root / "sources").glob("*.part")), [])

    def test_existing_wrong_file_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "sources/package.bin"
            target.parent.mkdir()
            target.write_bytes(b"local data")
            item = self.source(root)
            with self.assertRaisesRegex(ValueError, "does not match pinned source"):
                MODULE.fetch_source("fixture", item, root)
            self.assertEqual(target.read_bytes(), b"local data")


if __name__ == "__main__":
    unittest.main()
