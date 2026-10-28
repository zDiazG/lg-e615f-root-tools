# LG E615f Root Tools

`lg-e615f-root-tools` contains device-specific notes, a guarded patch to a public Android kernel-root proof of concept, and setup helpers for the LG E615f on stock V10p firmware. It is not a general Android rooting toolkit.

## Tested target

| Item | Observed value |
| --- | --- |
| Device | LG-E615f, `m4ds` |
| Firmware | V10p BR OPEN |
| Android | 4.0.4, API 15 (Ice Cream Sandwich) |
| Kernel | `3.0.8-perf+` |
| ABI | 32-bit ARMv7 |

The patched proof of concept has obtained temporary UID 0 on this exact handset and firmware. SuperSU v2.82 was installed under `/system`; `su -c id` returned UID 0 over SimpleSSHD before and after reboot, without another permission prompt. SimpleSSHD's boot receiver and SSH listener were observed after two controlled reboots. These results apply to the tested handset. They do not establish support for other devices or builds.

API numbers identify Android framework levels. API 15 is Android 4.0.x. API 16 is Android 4.1.x Jelly Bean. The current phone is API 15. API 16 firmware and other E615 variants have not been tested with this patched build.

## Before using the device scripts

Read [device support and limits](docs/device-support.md), [root and recovery procedure](docs/root-and-recovery.md), and [external sources](docs/external-sources.md). The kernel write can hang or panic the phone before a temporary root shell appears. The later SuperSU install writes to `/system`. A local raw `/system` image exists for the tested handset, but it is not a full firmware image or a recovery method for a bootloop or hard brick.

The scripts stop on a target mismatch and refuse to overwrite existing root paths. Do not run them against another phone or firmware based only on an Android API number.

## Prepare and validate on the host

List dependencies and preview downloads without network or filesystem changes:

```sh
python3 scripts/bootstrap-sources.py --list
python3 scripts/bootstrap-sources.py --dry-run simplesshd-19 supersu-v2.82
```

Download a named dependency only when you intend to use it. Every downloaded file is checked against the byte size and SHA-256 in [`sources.lock.json`](sources.lock.json). Files go under ignored `sources/` and are not run by CI.

```sh
python3 scripts/bootstrap-sources.py --fetch simplesshd-19 supersu-v2.82
python3 scripts/root-package-plan.py
python3 -m unittest discover -s tests -v
bash scripts/verify-poc-patch.sh --fetch
```

To also build the patched ARM binary with the local NDK r10e:

```sh
bash scripts/verify-poc-patch.sh --fetch --ndk sources/root/tools/android-ndk-r10e
```

The NDK archive is about 1.1 GB. CI checks the upstream commit and patch application but does not download the NDK, build a device binary, run the proof of concept, or connect to a phone. `--dry-run` never fetches sources automatically.

## Project contents

- `patches/android-cve-2013-6282/` records the upstream revision and guarded API 15 patch.
- `scripts/device/` contains read-only target inventory and a narrow SuperSU installer for the exact V10p target.
- `scripts/bootstrap-sources.py` fetches explicitly selected, pinned external files into ignored `sources/`.
- `scripts/verify-poc-patch.sh` verifies the upstream source, applies the patch in a temporary copy, and can build it with a supplied NDK.
- `docs/` contains the supported-device record, install/recovery guidance, source credits, firmware notes, and user-tool details.
- `.github/workflows/ci.yml` runs host tests, shell syntax checks, source-plan checks, and patch-application validation. It does not run device operations.

## Limits

This project has no verified no-boot recovery route for the E615f. The available `/system` dump cannot be converted into a KDZ through a verified process. Firmware candidates are unverified and must not be treated as recovery images. The scripts and binaries come with no warranty; using them can leave the phone unable to boot.

The patch is based on [timwr/CVE-2013-6282](https://github.com/timwr/CVE-2013-6282). Other external components and their terms are listed in [external sources](docs/external-sources.md).
