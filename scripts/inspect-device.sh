#!/usr/bin/env bash
set -euo pipefail
# Select one device explicitly when multiple transports are available.
if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [serial]" >&2
  exit 2
fi
command -v adb >/dev/null
selector=(-d)
if [[ $# == 1 ]]; then selector=(-s "$1"); fi
adb "${selector[@]}" get-state
adb "${selector[@]}" shell 'id; for p in ro.product.model ro.product.device ro.product.cpu.abi ro.build.version.release ro.build.version.sdk ro.build.display.id ro.lge.swversion ro.build.type ro.secure ro.debuggable ro.adb.secure service.adb.tcp.port persist.adb.tcp.port; do echo "$p=$(getprop $p)"; done; df /data'
