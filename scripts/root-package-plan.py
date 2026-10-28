#!/usr/bin/env python3
"""Inspect the pinned SuperSU ZIP and print a host-only API 15 install audit."""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import shutil
import struct
import sys
import zipfile
from pathlib import Path

EXPECTED_SHA256 = "f362c7e80fe3151606f3fcc79d9440e051b3deae824a87a8fef60db3d3742cce"
DEFAULT_PACKAGE = Path(__file__).resolve().parents[1] / "sources/root/packages/UPDATE-SuperSU-v2.82-20170528234214.zip"
LOG = logging.getLogger("root-package-plan")
STAGE_ENTRIES = {
    "arm/su": "su",
    "common/Superuser.apk": "Superuser.apk",
    "common/install-recovery.sh": "install-recovery.sh",
    "common/99SuperSUDaemon": "99SuperSUDaemon",
}


def fail(message: str) -> int:
    LOG.error(message)
    return 1


def inspect(package: Path, expected_sha256: str = EXPECTED_SHA256) -> dict[str, object]:
    if not package.is_file():
        raise ValueError(f"Package not found: {package}")

    digest = hashlib.sha256(package.read_bytes()).hexdigest()
    if digest != expected_sha256:
        raise ValueError(f"SHA-256 mismatch: {digest}")

    with zipfile.ZipFile(package) as archive:
        bad_entry = archive.testzip()
        if bad_entry:
            raise ValueError(f"ZIP CRC failed for {bad_entry}")

        required = {
            "arm/su",
            "common/Superuser.apk",
            "common/install-recovery.sh",
            "common/99SuperSUDaemon",
            "META-INF/com/google/android/update-binary",
        }

        names = set(archive.namelist())
        missing = required - names
        if missing:
            raise ValueError("Missing package entries: " + ", ".join(sorted(missing)))

        elf = archive.read("arm/su")
        if len(elf) < 20 or elf[:4] != b"\x7fELF":
            raise ValueError("arm/su is not an ELF file")
        elf_class, byte_order = elf[4], elf[5]
        if byte_order not in (1, 2):
            raise ValueError(f"Unexpected arm/su ELF byte order: {byte_order}")
        machine = struct.unpack_from("<H" if byte_order == 1 else ">H", elf, 18)[0]
        if (elf_class, byte_order, machine) != (1, 1, 40):
            raise ValueError(f"Unexpected arm/su ELF: class={elf_class}, endian={byte_order}, machine={machine}")

        installer = archive.read("META-INF/com/google/android/update-binary").decode("utf-8", "replace")
        expected_markers = (
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
        absent = [marker for marker in expected_markers if marker not in installer]
        if absent:
            raise ValueError("API 15 file-map markers missing from installer: " + "; ".join(absent))

        api15_plan = [
            {
                "source": source,
                "target": target,
                "owner": "root:root",
                "mode": mode,
                "package_behavior": behavior,
                "sha256": hashlib.sha256(archive.read(source)).hexdigest(),
            }
            for source, target, mode, behavior in (
                ("arm/su", "/system/xbin/su", "06755", "required setuid binary"),
                ("arm/su", "/system/bin/.ext/.su", "06755", "manager/UI copy"),
                ("arm/su", "/system/xbin/daemonsu", "0755", "written by update-binary"),
                ("common/Superuser.apk", "/system/app/Superuser.apk", "0644", "permission manager"),
                ("common/install-recovery.sh", "/system/etc/install-recovery.sh", "0755", "written by update-binary"),
                ("common/99SuperSUDaemon", "/system/etc/init.d/99SuperSUDaemon", "0744", "installer attempts this copy; init.d dependent"),
            )
        ]

        return {
            "source": "https://download.chainfire.eu/1113/SuperSU/UPDATE-SuperSU-v2.82-20170528234214.zip",
            "package": str(package),
            "sha256": digest,
            "zip_entries": len(archive.infolist()),
            "zip_crc": "passed",
            "su_elf": {"class": 32, "endianness": "little", "machine": "ARM"},
            "api15_plan": api15_plan,
            "installer_side_effects": [
                "remounts /system read-write",
                "creates /system/bin/.ext and stages /system/toolbox",
                "removes existing su and superuser-related paths/data before placement",
                "calls /system/xbin/su --install after copying files",
                "attempts an init.d helper and writes a daemon marker",
            ],
            "installer_cleanup_scope": [
                "legacy su binaries and manager APK/ODEx paths under /system",
                "selected competing root-manager apps and dalvik-cache entries under /data",
                "/data/su.img and /cache/su.img",
                "all /data/dalvik-cache/*.oat files",
            ],
            "generic_update_binary_commands": [
                "cat", "chmod", "chown", "cp", "dd", "echo", "grep", "ln",
                "losetup", "ls", "mkdir", "mknod", "mount", "mv", "readlink",
                "rm", "rmdir", "sh", "sleep", "sync", "umount", "unzip",
            ],
            "installer_runtime_constraints": [
                "the stock rm rejects the -f option used by update-binary",
                "providing pre-extracted BIN and COM may skip the update-binary /tmp unzip branch, but does not replace missing command helpers",
            ],
            "execution_status": "host_audit_only",
            "execution_steps": [],
            "rollback": "if Android remains bootable, regain temporary UID 0 and restore saved files or remove only files created by this install; no no-boot recovery route is verified",
            "device_changed": False,
            "warning": "Host-only package audit. It does not contact ADB, remount /system, install files, or execute su. Do not treat this report as authorization to write to a device.",
        }


def extract_stage_files(
    package: Path,
    destination: Path,
    expected_sha256: str = EXPECTED_SHA256,
) -> dict[str, str]:
    """Extract only the reviewed API 15 inputs into a new host directory."""
    inspect(package, expected_sha256=expected_sha256)
    if destination.exists():
        raise ValueError(f"Refusing to overwrite existing staging directory: {destination}")
    destination.mkdir(parents=True)
    extracted: dict[str, str] = {}
    try:
        with zipfile.ZipFile(package) as archive:
            for member, filename in STAGE_ENTRIES.items():
                content = archive.read(member)
                target = destination / filename
                with target.open("xb") as output:
                    output.write(content)
                extracted[filename] = hashlib.sha256(content).hexdigest()
    except Exception:
        shutil.rmtree(destination)
        raise
    return extracted


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", nargs="?", type=Path, default=DEFAULT_PACKAGE)
    parser.add_argument("--extract", type=Path, metavar="NEW_DIR", help="extract only the reviewed API 15 inputs into a new host directory")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    try:
        result = inspect(args.package)
        if args.extract is not None:
            result["extracted_to"] = str(args.extract)
            result["extracted_files"] = extract_stage_files(args.package, args.extract)
        print(json.dumps(result, indent=2))
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        return fail(str(error))
    return 0


if __name__ == "__main__":
    sys.exit(main())
