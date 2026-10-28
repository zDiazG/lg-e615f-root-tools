#!/system/bin/sh

# Read-only target inventory. Run as adb shell over USB or TCP/IP, never as a privilege test.
set -eu

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

prop() {
    /system/bin/getprop "$1" 2>/dev/null || true
}

[ "$#" -eq 0 ] || fail "This script takes no arguments and performs no writes."

model=$(prop ro.product.model)
device=$(prop ro.product.device)
release=$(prop ro.build.version.release)
api=$(prop ro.build.version.sdk)
abi=$(prop ro.product.cpu.abi)
build=$(prop ro.build.display.id)
firmware=$(prop ro.lge.swversion)
fingerprint=$(prop ro.build.fingerprint)
kernel_line=$(/system/bin/cat /proc/version 2>/dev/null) || fail "Cannot read kernel version."
case "$kernel_line" in
    "Linux version "*) ;;
    *) fail "Unexpected /proc/version contents: $kernel_line" ;;
esac
kernel=${kernel_line#Linux version }
kernel=${kernel%% *}
uid=
while read -r field value rest; do
    if [ "$field" = "Uid:" ]; then
        uid=$value
        break
    fi
done < /proc/self/status
[ -n "$uid" ] || fail "Cannot read UID from /proc/self/status."

echo "model=$model"
echo "device=$device"
echo "android_release=$release"
echo "api=$api"
echo "abi=$abi"
echo "build=$build"
echo "firmware=$firmware"
echo "fingerprint=$fingerprint"
echo "kernel=$kernel"
echo "uid=$uid"

[ "$release" = "4.0.4" ] || fail "Unexpected Android release: $release"
[ "$api" = "15" ] || fail "Unexpected Android API: $api"
[ "$abi" = "armeabi-v7a" ] || fail "Unexpected primary ABI: $abi"
[ "$kernel" = "3.0.8-perf+" ] || fail "Unexpected kernel release: $kernel"
[ "$firmware" = "LG-E615f-V10p-SEP-02-2013" ] || fail "Unexpected LG firmware build: $firmware"
[ "$fingerprint" = "lge/m4ds_open_br/m4ds:4.0.4/IMM76D/lge615f-V10p.20130902.102815:user/release-keys" ] || fail "Unexpected Android build fingerprint."
[ "$uid" = "2000" ] || fail "Expected adb shell UID 2000, got $uid"

echo
echo "Existing su paths:"
for path in /system/bin/su /system/xbin/su; do
    if [ -e "$path" ]; then
        /system/bin/ls -l "$path"
    else
        echo "absent=$path"
    fi
done

echo
echo "System mount:"
/system/bin/cat /proc/mounts | while read -r source target fstype options rest; do
    if [ "$target" = "/system" ]; then
        echo "$source $target $fstype $options"
    fi
done

echo
echo "Space:"
/system/bin/df /system /data

echo
echo "SuperSU update-binary runtime requirements (read-only):"
installer_commands="cat chmod chown cp dd echo grep ln losetup ls mkdir mknod mount mv readlink rm rmdir sh sleep sync umount unzip"
missing_commands=
for command_name in $installer_commands; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        missing_commands="$missing_commands $command_name"
    fi
done
if [ -n "$missing_commands" ]; then
    echo "missing_installer_commands=${missing_commands# }"
    installer_ready=no
else
    echo "missing_installer_commands=none"
    installer_ready=yes
fi
if [ -d /tmp ]; then
    if [ -w /tmp ]; then
        echo "tmp_exists=yes tmp_writable_for_adb_shell=yes"
    else
        echo "tmp_exists=yes tmp_writable_for_adb_shell=no"
        installer_ready=no
    fi
else
    echo "tmp_exists=no tmp_writable_for_adb_shell=no"
    installer_ready=no
fi
rm_probe="/data/local/tmp/.api15-supersu-rm-option-probe-$$"
if [ -e "$rm_probe" ]; then
    echo "rm_f_option_supported=unknown (probe path already exists)"
else
    rm_probe_output=$(rm -f "$rm_probe" 2>&1 || true)
    if [ -n "$rm_probe_output" ]; then
        echo "rm_f_option_supported=no ($rm_probe_output)"
        installer_ready=no
    else
        echo "rm_f_option_supported=yes"
    fi
fi
echo "generic_update_binary_runtime_ready=$installer_ready"

echo
echo "Existing SuperSU installer cleanup targets:"
cleanup_paths="
/system/xbin/daemonsu /system/xbin/sugote /system/xbin/sugote-mksh
/system/xbin/supolicy /system/xbin/ku.sud /system/xbin/.ku /system/xbin/.su
/system/lib/libsupol.so /system/lib64/libsupol.so /system/bin/.ext/.su
/system/etc/init.d/99SuperSUDaemon /system/etc/.installed_su_daemon
/system/app/Superuser.apk /system/app/Superuser.odex /system/app/Superuser
/system/app/SuperUser.apk /system/app/SuperUser.odex /system/app/SuperUser
/system/app/superuser.apk /system/app/superuser.odex /system/app/superuser
/system/app/Supersu.apk /system/app/Supersu.odex /system/app/Supersu
/system/app/SuperSU.apk /system/app/SuperSU.odex /system/app/SuperSU
/system/app/supersu.apk /system/app/supersu.odex /system/app/supersu
/system/app/VenomSuperUser.apk /system/app/VenomSuperUser.odex /system/app/VenomSuperUser
/system/etc/install-recovery.sh /system/bin/install-recovery.sh
/system/etc/install-recovery_original.sh /system/bin/install-recovery_original.sh
/system/bin/app_process32_original /system/bin/app_process32_xposed
/system/bin/app_process64_original /system/bin/app_process64_xposed /system/bin/app_process_init
/system/toolbox
"
found_cleanup_paths=
for path in $cleanup_paths; do
    if [ -e "$path" ]; then
        echo "present=$path"
        found_cleanup_paths=yes
    fi
done
if [ -z "$found_cleanup_paths" ]; then
    echo "present=none"
fi

echo
echo "Existing SuperSU installer data/cache cleanup targets:"
data_cleanup_paths="
/data/app/com.noshufou.android.su* /data/app/com.koushikdutta.superuser*
/data/app/com.mgyun.shua.su* /data/app/com.m0narx.su*
/data/app/com.kingroot.kinguser* /data/app/com.kingroot.master*
/data/app/me.phh.superuser* /data/app/eu.chainfire.supersu-*
/data/app/eu.chainfire.supersu.apk /data/su.img /cache/su.img
/data/dalvik-cache/*com.noshufou.android.su* /data/dalvik-cache/*com.koushikdutta.superuser*
/data/dalvik-cache/*com.mgyun.shua.su* /data/dalvik-cache/*com.m0narx.su*
/data/dalvik-cache/*com.kingroot.kinguser* /data/dalvik-cache/*com.kingroot.master*
/data/dalvik-cache/*me.phh.superuser* /data/dalvik-cache/*eu.chainfire.supersu*
/data/dalvik-cache/*Superuser.apk* /data/dalvik-cache/*SuperUser.apk*
/data/dalvik-cache/*superuser.apk* /data/dalvik-cache/*VenomSuperUser.apk*
/data/dalvik-cache/*Supersu.apk* /data/dalvik-cache/*SuperSU.apk*
/data/dalvik-cache/*supersu.apk* /data/dalvik-cache/*.oat
"
found_data_cleanup_paths=
for path in $data_cleanup_paths; do
    if [ -e "$path" ]; then
        echo "present=$path"
        found_data_cleanup_paths=yes
    fi
done
if [ -z "$found_data_cleanup_paths" ]; then
    echo "present=none"
fi

echo "Read-only preflight complete; no kernel or system writes were attempted."
