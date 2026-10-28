#!/usr/bin/env bash
set -Eeuo pipefail

# Install legacy tools in the SSH application's private home, without root.
dry_run=0
if [[ $# == 2 && $1 == --dry-run ]]; then
    dry_run=1
    ssh_target=$2
elif [[ $# == 1 && $1 != -* ]]; then
    ssh_target=$1
else
    echo "Usage: $0 [--dry-run] SSH_HOST" >&2
    exit 2
fi
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for tool in python3 ssh flock sed tar; do command -v "$tool" >/dev/null; done
if ((dry_run)); then
    printf 'target=%s\n' "$ssh_target"
    printf 'remote_paths=%s\n' '~/bin ~/opt/python3.2 ~/env.sh'
    python3 "$repo_root/scripts/bootstrap-sources.py" --dry-run \
        busybox-1.31.0-armv7 qpython3-1.3.5 curl-static-armv7-8.23.0
    echo "remote_or_local_changes=none"
    exit 0
fi
mkdir -p "$repo_root/sources/"{bin,apks,runtime}
exec 9>"$repo_root/sources/runtime/.user-tools.lock"
flock -n 9 || { echo "Another tool installation is active" >&2; exit 1; }
ssh_opts=(-o BatchMode=yes -o ConnectTimeout=10)
# Legacy SSH child processes may not inherit Android's property workspace.
abi=$(ssh "${ssh_opts[@]}" "$ssh_target" 'cat /system/build.prop' | sed -n 's/^ro.product.cpu.abi=//p')
[[ $abi == armeabi-v7a ]] || { echo "Expected Android armeabi-v7a; got: $abi" >&2; exit 1; }

busybox_file="$repo_root/sources/bin/busybox-1.31.0-armv7l"
python_apk="$repo_root/sources/apks/qpython3-1.3.5.apk"
runtime_tar="$repo_root/sources/runtime/python3.2-qpython-1.3.5.tar.gz"
curl_archive="$repo_root/sources/bin/curl-linux-armv7-musl-8.23.0-1.tar.xz"
curl_file="$repo_root/sources/bin/curl-8.23.0-armv7"
python3 "$repo_root/scripts/bootstrap-sources.py" --fetch \
    busybox-1.31.0-armv7 qpython3-1.3.5 curl-static-armv7-8.23.0
tar -xOf "$curl_archive" curl > "$curl_file"
[[ -s $curl_file ]] || { echo "ERROR: curl binary extraction returned an empty file" >&2; exit 1; }

# Extract only the interpreter, libraries, and configuration headers. No APK install.
python3 - "$python_apk" "$runtime_tar" <<'PY'
import io
import pathlib
import sys
import tarfile
import zipfile

with zipfile.ZipFile(sys.argv[1]) as apk, tarfile.open(sys.argv[2], "w:gz") as output:
    for name in ("assets/private1.mp3", "assets/private2.mp3", "assets/private3.mp3"):
        with tarfile.open(fileobj=io.BytesIO(apk.read(name)), mode="r:gz") as source:
            for member in source.getmembers():
                if not (member.name == "bin/python" or
                        member.name.split("/")[0] in ("lib", "include")):
                    continue
                for path in (member.name, member.linkname):
                    parsed = pathlib.PurePosixPath(path)
                    if parsed.is_absolute() or ".." in parsed.parts:
                        raise ValueError("Unsafe archive path: " + path)
                if not (member.isfile() or member.isdir() or member.issym() or member.islnk()):
                    raise ValueError("Unsupported archive entry: " + member.name)
                output.addfile(member, source.extractfile(member) if member.isfile() else None)
PY

ssh "${ssh_opts[@]}" "$ssh_target" \
    'mkdir -p "$HOME/bin" "$HOME/opt/python3.2" && chmod 700 "$HOME/bin" "$HOME/opt" "$HOME/opt/python3.2" && cat > "$HOME/bin/busybox.new" && chmod 700 "$HOME/bin/busybox.new" && mv "$HOME/bin/busybox.new" "$HOME/bin/busybox"' < "$busybox_file"
ssh "${ssh_opts[@]}" "$ssh_target" \
    'cat > "$HOME/bin/curl-static.new" && chmod 700 "$HOME/bin/curl-static.new" && mv "$HOME/bin/curl-static.new" "$HOME/bin/curl-static"' < "$curl_file"
ssh "${ssh_opts[@]}" "$ssh_target" \
    '"$HOME/bin/busybox" tar -xzf - -C "$HOME/opt/python3.2"' < "$runtime_tar"
ssh "${ssh_opts[@]}" "$ssh_target" 'cat > "$HOME/bin/python3" && chmod 700 "$HOME/bin/python3"' <<'SH'
#!/system/bin/sh
runtime="$HOME/opt/python3.2"
export LD_LIBRARY_PATH="$runtime/lib:/system/lib"
export PYTHONHOME="$runtime"
export PYTHONUNBUFFERED=1
exec "$runtime/bin/python" "$@"
SH
ssh "${ssh_opts[@]}" "$ssh_target" 'cat > "$HOME/bin/curl" && chmod 700 "$HOME/bin/curl"' <<'SH'
#!/system/bin/sh
# Static Linux resolvers do not use Android's legacy DNS properties.
# This affects only curl; both DoH and destination certificates remain verified.
exec "$HOME/bin/curl-static" --doh-url "${LG_CURL_DOH_URL:-https://1.1.1.1/dns-query}" "$@"
SH
ssh "${ssh_opts[@]}" "$ssh_target" 'cat > "$HOME/env.sh" && chmod 600 "$HOME/env.sh"' <<'SH'
export PATH="$HOME/bin:$PATH"
SH
ssh "${ssh_opts[@]}" "$ssh_target" 'cat > "$HOME/bin/lg-shell" && chmod 700 "$HOME/bin/lg-shell"' <<'SH'
#!/system/bin/sh
export PATH="$HOME/bin:$PATH"
exec "$HOME/bin/busybox" ash "$@"
SH
ssh "${ssh_opts[@]}" "$ssh_target" '
for tool in ash awk basename bzip2 cat chmod cp cut date dirname du env find grep gzip head id ln ls mkdir mv printf readlink sed sha256sum sort tail tar tee timeout touch tr uname uniq unzip wc wget xargs; do
    "$HOME/bin/busybox" ln -sf busybox "$HOME/bin/$tool" || exit 1
done
"$HOME/bin/busybox" uname -a
"$HOME/bin/curl" --version | head -n 1
"$HOME/bin/python3" -c "import sys,json,socket,sqlite3,subprocess; print(sys.version); print(json.dumps(dict(sqlite=sqlite3.sqlite_version)))"
'
