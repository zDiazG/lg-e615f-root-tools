# External sources

Downloaded files are ignored under `sources/`. The repository tracks their URLs, exact sizes, SHA-256 pins, and license notes in [`sources.lock.json`](../sources.lock.json). `scripts/bootstrap-sources.py --dry-run NAME` only prints a plan. `--fetch NAME` performs an explicit HTTPS download and checks the exact byte size and SHA-256 before placing the file in the local cache.

Cloning this repository does not download APKs, firmware, root packages, or the NDK. CI fetches only the pinned upstream POC commit into a temporary directory to verify that the patch applies. It does not run that code or fetch install packages.

| Component | Pinned input | Source | Handling |
| --- | --- | --- | --- |
| Root POC base | `timwr/CVE-2013-6282`, commit `25d31fab1c6f82f1eb22959e8bd27df9d81b8a91`; original `exploit.c` SHA-256 `f99d3761aa79822d7cff9cf96837fe1848917065dc7378fdc175f488ee77f290` | [Upstream repository](https://github.com/timwr/CVE-2013-6282) | Source is fetched to a temporary directory for patch validation. No upstream source is copied into the tracked tree. The pinned revision has no explicit license file; the repository license does not cover the upstream POC or its derived patch. |
| SimpleSSHD 19 | APK SHA-256 `149252fe5ca24bc3e585575a560862727061191f87b95eb5c2ff0a0e6c8dce07` | [Upstream download](https://www.galexander.org/software/simplesshd/SimpleSSHD-19.apk), [source repository](https://galexander.org/git/simplesshd.git) | Version 19 was observed installed on API 15. Review upstream licenses before redistribution. |
| SuperSU 2.82 | ZIP SHA-256 `f362c7e80fe3151606f3fcc79d9440e051b3deae824a87a8fef60db3d3742cce` | [Chainfire download](https://download.chainfire.eu/1113/SuperSU/UPDATE-SuperSU-v2.82-20170528234214.zip) | Proprietary package; keep local. Redistribution rights have not been established. |
| Android NDK r10e | Archive SHA-256 `ee5f405f3b57c4f5c3b3b8b5d495ae12b660e03d2112e4ed5c728d349f1e520c` | [Google NDK archive](https://dl.google.com/android/repository/android-ndk-r10e-linux-x86_64.zip) | About 1.1 GB. Fetch only when building the ARM POC. Review Google's terms before redistribution. |
| BusyBox 1.31.0 ARMv7 | SHA-256 `cd04052b8b6885f75f50b2a280bfcbf849d8710c8e61d369c533acf307eda064` | [BusyBox binary archive](https://busybox.net/downloads/binaries/1.31.0-defconfig-multiarch-musl/) | GPL-2.0. Source and binary archive terms apply. |
| QPython3 1.3.5 | APK SHA-256 `49c1c966f265a1a670fd56309e72ffa278211ca197e67c02ef8503c677a7cfe1` | [Upstream release](https://github.com/qpython-android/qpython3/releases/tag/v1.3.5) | Obsolete Android/Python release. Review upstream and bundled-component licenses before redistribution. |
| Static curl ARMv7 8.23.0 | Archive SHA-256 `10245cccca6e81b654ec7454c0397ab26e4a31910440548625a3802ce0971b3b` | [Static curl release](https://github.com/stunnel/static-curl/releases/tag/8.23.0-1) | Third-party binary build. Review release metadata and bundled certificate-bundle terms before redistribution. |

## Redistribution

Hash verification identifies downloaded bytes; it does not grant permission to redistribute them. The external APKs, SuperSU ZIP, NDK, and firmware stay out of Git history and GitHub release assets until their licenses and distribution rights are checked. Firmware candidates are documented separately and are not recommended for recovery.
