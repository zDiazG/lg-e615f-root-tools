import hashlib
import importlib.util
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts/root-package-plan.py"
PACKAGE = REPO_ROOT / "sources/root/packages/UPDATE-SuperSU-v2.82-20170528234214.zip"
SPEC = importlib.util.spec_from_file_location("root_package_plan", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


INSTALLER_MARKERS = (
    "7-19  common/Superuser.apk",
    "7+    ARCH/su",
    "7+                                  /system/bin/.ext/.su",
    "06755 if API < 18",
    "cp_perm 0 0 $SUMOD $BIN/$SU /system/bin/.ext/.su",
    "cp_perm 0 0 $SUMOD $BIN/$SU /system/xbin/su",
    "cp_perm 0 0 0755 $BIN/$SU /system/xbin/daemonsu",
    "cp_perm 0 0 0644 $COM/Superuser.apk $APKNAME",
    "cp_perm 0 0 0755 $COM/install-recovery.sh /system/etc/install-recovery.sh",
    "cp_perm 0 0 0744 $COM/99SuperSUDaemon /system/etc/init.d/99SuperSUDaemon",
    "LD_LIBRARY_PATH=$SYSTEMLIB /system/xbin/su --install",
)


def make_package(path: Path, *, bad_elf: bool = False, omit_marker: bool = False) -> str:
    elf = bytearray(32)
    elf[:4] = b"\x7fELF"
    elf[4:6] = bytes((1, 1))
    struct.pack_into("<H", elf, 18, 40)
    if bad_elf:
        elf[5] = 0
    markers = INSTALLER_MARKERS[:-1] if omit_marker else INSTALLER_MARKERS
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("arm/su", elf)
        archive.writestr("common/Superuser.apk", b"manager apk fixture")
        archive.writestr("common/install-recovery.sh", b"#!/system/bin/sh\n")
        archive.writestr("common/99SuperSUDaemon", b"#!/system/bin/sh\n")
        archive.writestr(
            "META-INF/com/google/android/update-binary",
            "\n".join(markers),
        )
    return hashlib.sha256(path.read_bytes()).hexdigest()


class RootPackagePlanTests(unittest.TestCase):
    def test_rejects_unpinned_archive_before_parsing(self):
        with tempfile.TemporaryDirectory() as directory:
            candidate = Path(directory) / "untrusted.zip"
            candidate.write_bytes(b"not the pinned package")
            with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                MODULE.inspect(candidate)

    def test_audits_a_valid_fixture_without_device_side_effects(self):
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory) / "fixture.zip"
            digest = make_package(package)
            result = MODULE.inspect(package, expected_sha256=digest)
            self.assertEqual(result["zip_crc"], "passed")
            self.assertEqual(result["su_elf"], {"class": 32, "endianness": "little", "machine": "ARM"})
            self.assertEqual(result["execution_status"], "host_audit_only")
            self.assertEqual(result["execution_steps"], [])
            self.assertFalse(result["device_changed"])
            self.assertTrue(result["warning"].startswith("Host-only package audit"))
            self.assertEqual(
                [(item["target"], item["mode"]) for item in result["api15_plan"]],
                [
                    ("/system/xbin/su", "06755"),
                    ("/system/bin/.ext/.su", "06755"),
                    ("/system/xbin/daemonsu", "0755"),
                    ("/system/app/Superuser.apk", "0644"),
                    ("/system/etc/install-recovery.sh", "0755"),
                    ("/system/etc/init.d/99SuperSUDaemon", "0744"),
                ],
            )
            self.assertTrue(all(len(item["sha256"]) == 64 for item in result["api15_plan"]))
            self.assertTrue(any("removes existing" in item for item in result["installer_side_effects"]))
            self.assertTrue(any("su --install" in item for item in result["installer_side_effects"]))
            self.assertIn("/data/su.img and /cache/su.img", result["installer_cleanup_scope"])
            self.assertIn("all /data/dalvik-cache/*.oat files", result["installer_cleanup_scope"])

    def test_rejects_wrong_elf_byte_order(self):
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory) / "bad-elf.zip"
            digest = make_package(package, bad_elf=True)
            with self.assertRaisesRegex(ValueError, "ELF byte order"):
                MODULE.inspect(package, expected_sha256=digest)

    def test_rejects_incomplete_installer_map(self):
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory) / "incomplete.zip"
            digest = make_package(package, omit_marker=True)
            with self.assertRaisesRegex(ValueError, "file-map markers missing"):
                MODULE.inspect(package, expected_sha256=digest)

    def test_extracts_only_allowlisted_api15_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory) / "fixture.zip"
            digest = make_package(package)
            destination = Path(directory) / "stage"
            extracted = MODULE.extract_stage_files(package, destination, expected_sha256=digest)
            self.assertEqual(
                set(extracted),
                {"su", "Superuser.apk", "install-recovery.sh", "99SuperSUDaemon"},
            )
            for name, expected in extracted.items():
                self.assertEqual(
                    hashlib.sha256((destination / name).read_bytes()).hexdigest(),
                    expected,
                )

    def test_refuses_existing_extraction_directory_without_touching_it(self):
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory) / "fixture.zip"
            digest = make_package(package)
            destination = Path(directory) / "stage"
            destination.mkdir()
            marker = destination / "keep.txt"
            marker.write_text("preserve")
            with self.assertRaisesRegex(ValueError, "Refusing to overwrite"):
                MODULE.extract_stage_files(package, destination, expected_sha256=digest)
            self.assertEqual(marker.read_text(), "preserve")

    @unittest.skipUnless(PACKAGE.is_file(), "pinned external package is absent")
    def test_downloaded_package_matches_pin_and_zip_crc(self):
        result = MODULE.inspect(PACKAGE)
        self.assertEqual(result["sha256"], MODULE.EXPECTED_SHA256)
        self.assertEqual(result["zip_crc"], "passed")
        self.assertEqual(result["su_elf"]["machine"], "ARM")


if __name__ == "__main__":
    unittest.main()
