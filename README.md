# LG E615f Root Tools

`lg-e615f-root-tools` documents a patched kernel-root proof of concept and host/device setup scripts for one LG E615f on stock V10p firmware. It is not a general Android rooting toolkit.

## Tested target

| Item | Observed value |
| --- | --- |
| Device | LG-E615f, `m4ds` |
| Firmware | V10p BR OPEN |
| Android | 4.0.4, API 15 (Ice Cream Sandwich) |
| Kernel | `3.0.8-perf+` |
| ABI | 32-bit ARMv7 |

The patched proof of concept obtained temporary UID 0 on this handset. SuperSU v2.82 then provided persistent `su`; `su -c id` over SimpleSSHD returned UID 0 after reboot without another approval prompt. SimpleSSHD also started after two observed reboots. These results apply to this handset and build only. API 16 is Android 4.1.x; it has not been tested here.

## Before using the device scripts

Read [device support](docs/device-support.md), [root and recovery](docs/root-and-recovery.md), and [external sources](docs/external-sources.md). The kernel write can hang or panic the phone, and the persistent install changes `/system`. No tested recovery path exists for a bootloop or hard brick.

The device installer checks the target identity and refuses existing root paths. The POC itself does not identify the handset, so use its binary only on the recorded E615f/V10p build.

## Host setup

Requirements: Python 3, Bash, Git, and standard archive tools. The NDK is needed only to build the ARM binary.

List pinned inputs or preview a download plan. These commands do not fetch files:

```sh
python3 scripts/bootstrap-sources.py --list
python3 scripts/bootstrap-sources.py --dry-run simplesshd-19 supersu-v2.82
```

Fetch only the packages you plan to use. The script checks byte size and SHA-256 and saves downloads under ignored `sources/`:

```sh
python3 scripts/bootstrap-sources.py --fetch simplesshd-19 supersu-v2.82
python3 scripts/root-package-plan.py
python3 -m unittest discover -s tests -v
```

To build the patched ARM executable, fetch and extract the pinned NDK, then save the output under the ignored `artifacts/` directory:

```sh
python3 scripts/bootstrap-sources.py --fetch android-ndk-r10e-linux-x86_64
unzip sources/root/tools/android-ndk-r10e-linux-x86_64.zip -d sources/root/tools
bash scripts/verify-poc-patch.sh --fetch \
  --ndk sources/root/tools/android-ndk-r10e \
  --output artifacts/api15-root-poc-armv7
```

`--output` refuses to overwrite an existing file. Without it, the script removes the temporary build directory when it exits. The NDK archive is about 1.1 GB. CI validates the host tooling and patch application; it does not build or run the POC or connect to a phone.

## Project files

- `patches/android-cve-2013-6282/` contains the pinned upstream reference and API 15 patch.
- `scripts/` contains source bootstrap, host audits, and device installers.
- `docs/` records device support, recovery limits, firmware candidates, and external sources.
- `.github/workflows/ci.yml` runs host-side checks only.

## License

Original project material is licensed under GPL-3.0-or-later; see [LICENSE](LICENSE). The upstream POC and `patches/android-cve-2013-6282/0001-api15-guarded.patch` are excluded. Their pinned source and other external components are listed in [external sources](docs/external-sources.md).

Firmware candidates are unverified and are not recovery images. The local `/system` image is not a full firmware dump and has no verified restore procedure.
