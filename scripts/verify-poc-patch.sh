#!/usr/bin/env bash
set -Eeuo pipefail

UPSTREAM_URL=https://github.com/timwr/CVE-2013-6282.git
UPSTREAM_COMMIT=25d31fab1c6f82f1eb22959e8bd27df9d81b8a91
UPSTREAM_EXPLOIT_SHA256=f99d3761aa79822d7cff9cf96837fe1848917065dc7378fdc175f488ee77f290
PATCHED_EXPLOIT_SHA256=c06a055063336d510dcec3e5a3a0de402d1260deb258328e4e4bf0de512acabe
REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PATCH_FILE="$REPO_ROOT/patches/android-cve-2013-6282/0001-api15-guarded.patch"

mode=
source_dir=
ndk_dir=
output_path=
while (($#)); do
    case "$1" in
        --dry-run|--fetch)
            [[ -z "$mode" ]] || { echo "Usage: $0 --dry-run | --fetch | --source-dir PATH [--ndk PATH]" >&2; exit 2; }
            mode=$1
            shift
            ;;
        --source-dir)
            [[ -z "$mode" && $# -ge 2 ]] || { echo "Usage: $0 --dry-run | --fetch | --source-dir PATH [--ndk PATH]" >&2; exit 2; }
            mode=--source-dir
            source_dir=$2
            shift 2
            ;;
        --ndk)
            [[ -z "$ndk_dir" && $# -ge 2 && -n "$2" ]] || { echo "Usage: $0 --dry-run | --fetch | --source-dir PATH [--ndk PATH [--output PATH]]" >&2; exit 2; }
            ndk_dir=$2
            shift 2
            ;;
        --output)
            [[ -z "$output_path" && $# -ge 2 && -n "$2" ]] || { echo "Usage: $0 --dry-run | --fetch | --source-dir PATH [--ndk PATH [--output PATH]]" >&2; exit 2; }
            output_path=$2
            shift 2
            ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

[[ -n "$mode" ]] || { echo "Usage: $0 --dry-run | --fetch | --source-dir PATH [--ndk PATH [--output PATH]]" >&2; exit 2; }
if [[ $mode == --dry-run ]]; then
    [[ -z "$ndk_dir" && -z "$output_path" ]] || { echo "--ndk and --output cannot be used with --dry-run" >&2; exit 2; }
    printf 'upstream=%s\ncommit=%s\nexploit_sha256=%s\npatch=%s\n' \
        "$UPSTREAM_URL" "$UPSTREAM_COMMIT" "$UPSTREAM_EXPLOIT_SHA256" "$PATCH_FILE"
    echo "network_or_filesystem_changes=none"
    exit 0
fi
[[ -z "$output_path" || -n "$ndk_dir" ]] || { echo "--output requires --ndk" >&2; exit 2; }
if [[ -n "$output_path" && ( -e "$output_path" || -L "$output_path" ) ]]; then
    echo "ERROR: refusing to overwrite output: $output_path" >&2
    exit 1
fi

command -v git >/dev/null || { echo "ERROR: git is required" >&2; exit 1; }
command -v sha256sum >/dev/null || { echo "ERROR: sha256sum is required" >&2; exit 1; }
command -v mktemp >/dev/null || { echo "ERROR: mktemp is required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "ERROR: python3 is required for safe temporary-directory cleanup" >&2; exit 1; }
[[ -f "$PATCH_FILE" ]] || { echo "ERROR: patch file not found: $PATCH_FILE" >&2; exit 1; }

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/api15-poc-check.XXXXXXXX")
cleanup() {
    python3 - "$tmp_root" <<'PY'
import shutil
import sys
from pathlib import Path

target = Path(sys.argv[1])
if target.is_dir() and target.name.startswith("api15-poc-check."):
    shutil.rmtree(target)
PY
}
trap cleanup EXIT HUP INT TERM
upstream_dir="$tmp_root/upstream"
working_dir="$tmp_root/patched"

if [[ $mode == --fetch ]]; then
    git init -q "$upstream_dir"
    git -C "$upstream_dir" remote add origin "$UPSTREAM_URL"
    git -C "$upstream_dir" fetch --quiet --depth=1 origin "$UPSTREAM_COMMIT"
    git -C "$upstream_dir" checkout --quiet --detach FETCH_HEAD
elif [[ $mode == --source-dir ]]; then
    [[ -d "$source_dir/.git" ]] || { echo "ERROR: source directory must be a Git checkout" >&2; exit 1; }
    actual_commit=$(git -C "$source_dir" rev-parse HEAD)
    [[ $actual_commit == "$UPSTREAM_COMMIT" ]] || { echo "ERROR: unexpected upstream commit: $actual_commit" >&2; exit 1; }
    mkdir -p "$upstream_dir"
    cp -a "$source_dir/." "$upstream_dir/"
else
    echo "ERROR: invalid mode" >&2
    exit 2
fi

actual_commit=$(git -C "$upstream_dir" rev-parse HEAD)
[[ $actual_commit == "$UPSTREAM_COMMIT" ]] || { echo "ERROR: fetched unexpected commit: $actual_commit" >&2; exit 1; }
actual_sha=$(sha256sum "$upstream_dir/exploit.c")
actual_sha=${actual_sha%% *}
[[ $actual_sha == "$UPSTREAM_EXPLOIT_SHA256" ]] || { echo "ERROR: upstream exploit.c SHA-256 mismatch: $actual_sha" >&2; exit 1; }
git -C "$upstream_dir" apply --check "$PATCH_FILE"
cp -a "$upstream_dir" "$working_dir"
git -C "$working_dir" apply "$PATCH_FILE"
patched_sha=$(sha256sum "$working_dir/exploit.c")
patched_sha=${patched_sha%% *}
[[ $patched_sha == "$PATCHED_EXPLOIT_SHA256" ]] || { echo "ERROR: patched exploit.c SHA-256 mismatch: $patched_sha" >&2; exit 1; }
git -C "$working_dir" diff --check
printf 'patch_apply=passed\nupstream_commit=%s\nupstream_exploit_sha256=%s\npatched_exploit_sha256=%s\n' \
    "$actual_commit" "$actual_sha" "$patched_sha"

if [[ -n "$ndk_dir" ]]; then
    ndk_dir=$(cd -- "$ndk_dir" && pwd)
    [[ -x "$ndk_dir/ndk-build" ]] || { echo "ERROR: ndk-build not found under $ndk_dir" >&2; exit 1; }
    command -v file >/dev/null || { echo "ERROR: file is required to identify the built executable" >&2; exit 1; }
    NDK="$ndk_dir" make -C "$working_dir" build
    binary="$working_dir/libs/armeabi/exploit"
    [[ -s "$binary" ]] || { echo "ERROR: expected ARM executable was not built" >&2; exit 1; }
    file "$binary"
    sha256sum "$binary"
    if [[ -n "$output_path" ]]; then
        [[ ! -e "$output_path" && ! -L "$output_path" ]] || { echo "ERROR: refusing to overwrite output: $output_path" >&2; exit 1; }
        output_dir=$(dirname -- "$output_path")
        mkdir -p -- "$output_dir"
        install -m 0755 -- "$binary" "$output_path"
        printf 'binary_output=%s\n' "$output_path"
    fi
fi
