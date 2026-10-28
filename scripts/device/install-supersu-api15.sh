#!/system/bin/sh

# Narrow, stock API 15 SuperSU system install. Run only inside the guarded POC's
# temporary UID 0 shell. The generic ZIP update-binary is intentionally unused.
set -eu

PAYLOAD=/data/local/tmp/api15-supersu/payload
MODEL_EXPECTED=LG-E615f
DEVICE_EXPECTED=m4ds
ANDROID_EXPECTED=4.0.4
API_EXPECTED=15
KERNEL_EXPECTED=3.0.8-perf+
FIRMWARE_EXPECTED=LG-E615f-V10p-SEP-02-2013
FINGERPRINT_EXPECTED=lge/m4ds_open_br/m4ds:4.0.4/IMM76D/lge615f-V10p.20130902.102815:user/release-keys

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

uid_now() {
    while read -r field value rest; do
        if [ "$field" = "Uid:" ]; then
            echo "$value"
            return 0
        fi
    done < /proc/self/status
    return 1
}

assert_target() {
    [ "$(/system/bin/getprop ro.product.model)" = "$MODEL_EXPECTED" ] || fail "Wrong model."
    [ "$(/system/bin/getprop ro.product.device)" = "$DEVICE_EXPECTED" ] || fail "Wrong device codename."
    [ "$(/system/bin/getprop ro.build.version.release)" = "$ANDROID_EXPECTED" ] || fail "Wrong Android release."
    [ "$(/system/bin/getprop ro.build.version.sdk)" = "$API_EXPECTED" ] || fail "Wrong Android API."
    [ "$(/system/bin/getprop ro.lge.swversion)" = "$FIRMWARE_EXPECTED" ] || fail "Wrong LG firmware build."
    [ "$(/system/bin/getprop ro.build.fingerprint)" = "$FINGERPRINT_EXPECTED" ] || fail "Wrong Android build fingerprint."
    case "$(/system/bin/cat /proc/version)" in
        "Linux version $KERNEL_EXPECTED "*) ;;
        *) fail "Wrong kernel release." ;;
    esac
}

system_options() {
    while read -r source target fstype options rest; do
        if [ "$target" = "/system" ]; then
            echo "$options"
            return 0
        fi
    done < /proc/mounts
    return 1
}

assert_system_readonly() {
    options=$(system_options) || fail "/system mount not found."
    case ",$options," in
        *,ro,*) ;;
        *) fail "/system must start read-only; found options=$options" ;;
    esac
}

assert_system_writable() {
    options=$(system_options) || fail "/system mount not found after remount."
    case ",$options," in
        *,rw,*) ;;
        *) fail "/system did not become writable; options=$options" ;;
    esac
}

file_size() {
    listing=$(/system/bin/ls -l "$1") || return 1
    set -- $listing
    [ "$#" -ge 4 ] || return 1
    echo "$4"
}

assert_payload() {
    [ -f "$PAYLOAD/su" ] || fail "Missing staged su binary."
    [ -f "$PAYLOAD/Superuser.apk" ] || fail "Missing staged manager APK."
    [ -f "$PAYLOAD/install-recovery.sh" ] || fail "Missing staged recovery helper."
    [ -f "$PAYLOAD/99SuperSUDaemon" ] || fail "Missing staged optional daemon helper."
    [ "$(file_size "$PAYLOAD/su")" -eq 75344 ] || fail "Unexpected su binary size."
    [ "$(file_size "$PAYLOAD/Superuser.apk")" -eq 6219992 ] || fail "Unexpected manager APK size."
    [ "$(file_size "$PAYLOAD/install-recovery.sh")" -eq 629 ] || fail "Unexpected recovery helper size."
    [ "$(file_size "$PAYLOAD/99SuperSUDaemon")" -eq 55 ] || fail "Unexpected daemon helper size."
}

assert_targets_absent() {
    for target in \
        /system/xbin/su \
        /system/bin/.ext \
        /system/xbin/daemonsu \
        /system/app/Superuser.apk \
        /system/etc/install-recovery.sh \
        /system/bin/install-recovery.sh \
        /system/etc/.installed_su_daemon \
        /system/etc/init.d/99SuperSUDaemon \
        /system/toolbox
    do
        [ ! -e "$target" ] || fail "Refusing to replace existing path: $target"
    done
}

install_file() {
    src=$1
    target=$2
    mode=$3
    temporary="$target.api15-new"
    [ ! -e "$temporary" ] || fail "Refusing to replace staged path: $temporary"
    temporary_paths="$temporary_paths $temporary"
    /system/bin/cat "$src" > "$temporary"
    /system/bin/chown 0.0 "$temporary"
    /system/bin/chmod "$mode" "$temporary"
    /system/bin/mv "$temporary" "$target"
    installed_paths="$installed_paths $target"
    echo "installed=$target mode=$mode"
}

rollback_and_remount() {
    result=$?
    trap - EXIT HUP INT TERM
    if [ "$complete" != "yes" ]; then
        echo "Install did not complete; removing only files created by this run." >&2
        for target in $installed_paths; do
            if [ -e "$target" ]; then /system/bin/rm "$target" || echo "ROLLBACK_FAILED=$target" >&2; fi
        done
        for temporary in $temporary_paths; do
            if [ -e "$temporary" ]; then /system/bin/rm "$temporary" || echo "ROLLBACK_FAILED=$temporary" >&2; fi
        done
        if [ "$created_ext_dir" = "yes" ] && [ -d /system/bin/.ext ]; then
            /system/bin/rmdir /system/bin/.ext || echo "ROLLBACK_FAILED=/system/bin/.ext" >&2
        fi
        if [ "$toolbox_staged" = "yes" ] && [ -e /system/toolbox ]; then
            /system/bin/rm /system/toolbox || echo "ROLLBACK_FAILED=/system/toolbox" >&2
        fi
        /system/bin/sync
    fi
    if [ "$system_was_remounted" = "yes" ]; then
        /system/bin/mount -o remount,ro /system || echo "CRITICAL: failed to remount /system read-only" >&2
    fi
    exit "$result"
}

preflight() {
    assert_target
    assert_payload
    echo "uid=$(uid_now)"
    echo "system_mount_options=$(system_options)"
    assert_system_readonly
    assert_targets_absent
    echo "api15_install_preflight=passed; no system writes performed"
}

apply_install() {
    [ "$(uid_now)" = "0" ] || fail "UID 0 is required."
    assert_target
    assert_payload
    assert_system_readonly
    assert_targets_absent

    system_was_remounted=no
    complete=no
    created_ext_dir=no
    toolbox_staged=no
    installed_paths=
    temporary_paths=
    trap rollback_and_remount EXIT HUP INT TERM

    /system/bin/mount -o remount,rw /system
    system_was_remounted=yes
    assert_system_writable

    /system/bin/mkdir /system/bin/.ext
    created_ext_dir=yes
    /system/bin/chown 0.0 /system/bin/.ext
    /system/bin/chmod 0777 /system/bin/.ext

    install_file "$PAYLOAD/su" /system/xbin/su 06755
    install_file "$PAYLOAD/su" /system/bin/.ext/.su 06755
    install_file "$PAYLOAD/su" /system/xbin/daemonsu 0755
    install_file "$PAYLOAD/Superuser.apk" /system/app/Superuser.apk 0644
    install_file "$PAYLOAD/install-recovery.sh" /system/etc/install-recovery.sh 0755

    link_temporary=/system/bin/install-recovery.sh.api15-new
    [ ! -e "$link_temporary" ] || fail "Refusing to replace staged path: $link_temporary"
    temporary_paths="$temporary_paths $link_temporary"
    /system/bin/ln -s /system/etc/install-recovery.sh "$link_temporary"
    /system/bin/mv "$link_temporary" /system/bin/install-recovery.sh
    installed_paths="$installed_paths /system/bin/install-recovery.sh"
    echo "installed=/system/bin/install-recovery.sh symlink=/system/etc/install-recovery.sh"

    if [ -d /system/etc/init.d ]; then
        install_file "$PAYLOAD/99SuperSUDaemon" /system/etc/init.d/99SuperSUDaemon 0744
    else
        echo "skipped=/system/etc/init.d/99SuperSUDaemon reason=init.d directory absent"
    fi

    marker_temporary=/system/etc/.installed_su_daemon.api15-new
    [ ! -e "$marker_temporary" ] || fail "Refusing to replace staged path: $marker_temporary"
    temporary_paths="$temporary_paths $marker_temporary"
    echo 1 > "$marker_temporary"
    /system/bin/chown 0.0 "$marker_temporary"
    /system/bin/chmod 0644 "$marker_temporary"
    /system/bin/mv "$marker_temporary" /system/etc/.installed_su_daemon
    installed_paths="$installed_paths /system/etc/.installed_su_daemon"
    echo "installed=/system/etc/.installed_su_daemon mode=0644"

    /system/bin/sync
    # SuperSU v2.82's API <= 21 system installer stages toolbox for its
    # post-install command, then removes the temporary copy.
    toolbox_staged=yes
    /system/bin/cat /system/bin/toolbox > /system/toolbox
    /system/bin/chown 0.0 /system/toolbox
    /system/bin/chmod 0755 /system/toolbox
    LD_LIBRARY_PATH=/system/lib /system/xbin/su --install
    echo "su_install_exit=0"
    /system/bin/rm /system/toolbox
    toolbox_staged=no
    /system/bin/sync
    complete=yes
    echo "api15_su_install=completed"
}

if [ "$#" -eq 1 ] && [ "$1" = "--preflight" ]; then
    preflight
elif [ "$#" -eq 2 ] && [ "$1" = "--apply" ] && [ "$2" = "--confirm-system-write" ]; then
    apply_install
else
    echo "Usage: $0 --preflight | --apply --confirm-system-write" >&2
    exit 2
fi
