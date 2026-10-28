# Firmware candidates

These files are research copies, not approved recovery images. None has been flashed or accepted by a tested E615F recovery workflow. The two V10P downloads have not been parsed successfully, so their filenames and download pages do not establish their internal model/build identity.

The Google Drive V10P copy is the first candidate to investigate because its archive came from a source linked by the UTI Cell firmware video and its extracted KDZ has the catalog-listed size. Its MD5 still differs from the catalog. The LGROM copy is a separate, lower-confidence download: it is much smaller than the catalog entry and its hash differs.

## Candidate inventory

| Candidate filename | Expected identity from source listing | Local source file | SHA-256 | MD5 | Assessment |
| --- | --- | --- | --- | --- | --- |
| `LGE615F-BRA-V10P_00-unverified.kdz` | E615F, BRA, V10P_00 | `sources/backups/firmware-e615f-v10p/V10P_00.unverified.kdz` | `e01a1cb877dd6abfc2bbe1cd8387368e457875d3d5499eceef33516c325c099a` | `a5909933f09b85c11b4dd911e002c201` | Primary inspection candidate. RAR integrity passed and size is 301,886,494 bytes. The catalog lists 287.9 MiB and MD5 `a5909933f09b85c11b4dd91102e201c`; the MD5 does not match. |
| `LGE615F-BRA-V10P_00-lgrom-unverified.kdz` | E615F, BRA, V10P_00 | `sources/V10P_00.kdz` | `0dbc66b9ef85e554d3ea766d010f9080d7e5c9bf00c7bd71ff8d23454e18034d` | `ca31aa00d08b79566dd407d0c2b8959e` | Lower-confidence candidate. 225,022,733 bytes, versus 287.9 MiB in the catalog. The download completed, but size/hash differ from the listing. |
| `LGE615F-BTM-V10A_03-unverified.kdz` | E615F, BTM/TIM, V10A_03 | `sources/backups/firmware-e615f-v10p/other-candidates/V10A_03.unverified.kdz` | `807932509d957f8534ce946af8a7b4020149df347d5550ad8ae08a4441f95285` | `9f059fb0dfa70026d0ebe48783ebe2cc` | Extracted from the downloaded RAR. MD5 matches the E615F/BTM catalog entry. It is a different regional/operator build from this phone's V10P/BRA/OPEN firmware, and recovery compatibility is untested. This is not the LGE610 V20A firmware. |

## Source references

- V10P Google Drive archive linked by the [UTI Cell video](https://www.youtube.com/watch?v=t_H4k0ciVyc): [Drive file](https://drive.google.com/file/d/0BxKPOOWOybDlRVRra3RwdlN0Z0E/view). The video labels it for E615/E615F. This is third-party provenance, not an LG-authenticated download.
- V10P listing: [LG-Firmwares E615F/BRA/V10P_00](https://lg-firmwares.com/downloads-file/243/V10P_00). The page identifies E615F, Brazil/BRA, Android 4.0, size 287.9 MiB, and MD5 `a5909933f09b85c11b4dd91102e201c`. The page is a catalog, not the source of either local copy.
- V10P second copy: [LGROM E615F/BRA/V10P_00](https://lgrom.com/firmware/LGE615F/BRA/V10P_00/5058). Its download button returned an `sf12.click` URL. The downloaded bytes do not match the catalog size or MD5.
- V10A archive: [Google Drive file](https://drive.google.com/file/d/0BxKPOOWOybDldnFPYjFQWnJVQ2M/view), originally linked through `https://goo.gl/tqSxei`.
- V10A listing: [LG-Firmwares E615F/BTM/V10A_03](https://lg-firmwares.com/downloads-file/4751/V10A_03). The page identifies E615F, Brazil/BTM (TIM), Android 4.0, and MD5 `9f059fb0dfa70026d0ebe48783ebe2cc`.
- The device's observed identity is LG-E615f, `m4ds_open_br`, V10p, BR OPEN, Android 4.0.4/API 15. This identifies the target build, not the contents of any downloaded candidate.

## Hosting and handling

The candidate files and their source archives stay local under ignored `/sources/` paths. They are not committed to Git history. This document does not assert that a release containing these files exists. If an artifact is published later, verify its identity and redistribution rights first, then use a clearly labeled release asset instead of Git history.

Do not flash these candidates based on this record. In particular, matching a catalog MD5 establishes byte identity with that catalog entry, not a safe downgrade/recovery path. The two V10P files are not verified against the catalog hash, and the V10A file is a different operator region. No KDZ parser has successfully extracted these files, and none has been tested in Download Mode on this device.

Large firmware files do not belong in ordinary Git history. A release asset may be suitable only after identity, licensing, and recovery compatibility have been established. Project-built binaries should be published only after the build and device behavior have been validated.
