#!/bin/sh
# Load the camera modules for this boot only: swaps the stock ipu-bridge for
# the patched one and loads the imx681 sensor driver. Reboot to undo.
#
# Usage: sudo sh load.sh [directory holding <kernel version>/*.ko]
set -eu
cd "$(dirname "$0")"

out=${1:-out}/$(uname -r)
[ -f "$out/imx681.ko" ] || { echo "Nothing built for this kernel, run ./build.sh first" >&2; exit 1; }

start=$(date +%s)
rmmod intel_ipu6_isys intel_ipu6 ipu_bridge 2>/dev/null || true
insmod "$out/ipu-bridge.ko"
modprobe v4l2-cci
insmod "$out/imx681.ko"
modprobe intel_ipu6_isys

# When run by hand, wait for the sensor to probe and show what happened
if [ -z "${1:-}" ]; then
    sleep 6
    dmesg --since "@$start" | grep -iE 'imx681|SONY|ipu|bridge|int3472' || true
fi
