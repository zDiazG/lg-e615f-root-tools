# Device support

## Verified configuration

The device used for the observed root run reported:

| Property | Value |
| --- | --- |
| Model | LG-E615f |
| Device code | `m4ds` |
| Product build | `m4ds_open_br`, V10p BR OPEN |
| Android release | 4.0.4 |
| Android API | 15 |
| Kernel release | `3.0.8-perf+` |
| Primary ABI | `armeabi-v7a` |

The target guard checks the model, device code, Android release and API, LG software version, build fingerprint, kernel release, and ADB shell UID before the install path proceeds. A matching API level alone is insufficient.

## Evidence on this device

- The patched ARM binary built against API 15 headers and ran on this handset.
- The read-only POC preflight resolved the expected symbols and read the `ptmx_fops` slot.
- The guarded POC obtained temporary UID 0, restored and reread the original callback, then verified UID 0 before opening its root shell.
- SuperSU v2.82 was installed in `/system`. The permission manager remembered SimpleSSHD's grant after one approval on the phone.
- Direct SSH returned UID 10072 for the SimpleSSHD login and UID 0 for `su -c id`, including after reboots. USB ADB also remained available.
- SimpleSSHD v19's boot receiver and port 2222 listener were observed after two controlled reboots. Two earlier checks did not find the listener until the app was started; that failure was not reproduced and its cause is unknown.

These are observations from one LG-E615f/V10p handset. A successful run does not prove that a future kernel write cannot hang or panic the phone.

## API level versus firmware and kernel

API 15 is Android 4.0.x Ice Cream Sandwich. API 16 is Android 4.1.x Jelly Bean. The device in this project is API 15. API 16 is not another name for this firmware.

The E615F firmware catalogs list Jelly Bean releases for some regional variants. No API 16 release was installed or tested here. The patched build has no device evidence for API 16 or for another E615 model. Do not generalize the result to a different firmware, kernel, ABI, or phone just because it reports API 15 or API 16.

## Unsupported and unverified cases

- Any handset other than the exact LG-E615f V10p target above.
- E615F regional or carrier variants other than the tested V10p BR OPEN build.
- Jelly Bean/API 16, including catalog-listed firmware.
- A full firmware restore, bootloop recovery, or hard-brick recovery.
- Permanent ADB-over-TCP startup. The observed `adb tcpip` mode switch disabled USB ADB; USB mode was restored after the transport check.

Firmware research is recorded separately in [firmware candidates](firmware-candidates.md). Those files are not validated recovery images.
