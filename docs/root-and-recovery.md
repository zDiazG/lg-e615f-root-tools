# Root and recovery procedure

This document separates the temporary kernel-root step from installing persistent `su`. They are separate operations with different effects.

## Observed result

On the exact LG-E615f, V10p BR OPEN, Android 4.0.4/API 15, kernel `3.0.8-perf+` target, the patched proof of concept obtained temporary UID 0. A narrow SuperSU v2.82 installer then wrote the reviewed files to `/system`. After reboot, SSH login remained UID 10072 and `su -c id` returned UID 0 without another approval prompt. The user approved SimpleSSHD once in the SuperSU UI and left its repeat-prompt option unchecked.

This result is device-specific. It is not a safe generic procedure for other Android phones.

## What the proof of concept changes

The default POC invocation refuses to run. `--preflight` reads kernel memory through the vulnerable local socket-option interface. It does not obtain root and is not a host-only dry run. On the tested phone, `--execute --confirm-kernel-write` temporarily changed the `ptmx_fops` callback pointer in kernel RAM, invoked the callback, restored and reread the original pointer, then checked UID 0.

The patched path checks operations that the original sample ignored and refuses to open the root shell unless callback restoration verifies. That reduces known failure cases. It cannot guarantee that a bad address, kernel timing issue, or device-specific behavior will not panic or hang the handset before restoration. A successful reboot clears that temporary kernel state. A hard lock may require a physical power cycle.

## Persistent install

The separate device installer is `scripts/device/install-supersu-api15.sh`. It accepts only the exact V10p target and refuses to replace existing installation paths. It writes these paths to `/system`:

- `/system/xbin/su`
- `/system/bin/.ext/.su`
- `/system/xbin/daemonsu`
- `/system/app/Superuser.apk`
- `/system/etc/install-recovery.sh`
- `/system/bin/install-recovery.sh` symlink
- `/system/etc/.installed_su_daemon`

It stages `/system/toolbox` only for `su --install`, removes that temporary copy, and remounts `/system` read-only. It skips the optional `init.d` helper when the directory is absent. It does not write boot, recovery, or another firmware partition.

The host-side package audit is `scripts/root-package-plan.py`. It checks the pinned ZIP hash, CRCs, ARM ELF header, required installer entries, and the proposed file map. It does not contact ADB or change a phone. The device installer checks staged file sizes; verify extracted hashes on the host and compare installed files after transfer when reproducing the process.

Do not run the install script on a phone that already has any target path. The tested phone already has the listed root files, so the install preflight should refuse it.

## Recovery limits

A pre-install raw image of `/dev/block/mmcblk0p14` was captured while `/system` was read-only. It is only the `/system` partition. It is not a KDZ, full eMMC dump, or a tested image that can restore a phone that no longer boots.

If Android remains bootable and privileged access still works, a partition image may be useful for investigation. This repository does not provide a verified restore command for that image. No tested recovery route exists for a bootloop or hard brick. Download-mode KDZ candidates are unverified and must not be treated as a safety net.

## Required operator action

The first SuperSU grant for SimpleSSHD requires approval in the phone's UI. After that grant is saved, SSH can request `su -c ...` without a recurring prompt. Keep USB ADB available during device work. The CI workflow never runs the POC, installs an APK, or writes to a phone.

The POC and installer can leave the device unable to boot. Use them only on the exact target after reading [device support](device-support.md). No warranty is provided.
