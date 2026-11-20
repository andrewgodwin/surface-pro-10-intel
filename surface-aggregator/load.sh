#!/bin/sh
# Swap the stock surface_aggregator for the patched one, for this boot only.
# Everything built on top of it (battery, keyboard, tablet switch, ...) is
# unloaded first and reloaded afterwards. Reboot to undo.
#
# Usage: sudo sh load.sh [directory holding <kernel version>/surface_aggregator.ko]
set -eu
cd "$(dirname "$0")"

ko=${1:-out}/$(uname -r)/surface_aggregator.ko
[ -f "$ko" ] || { echo "Nothing built for this kernel, run ./build.sh first" >&2; exit 1; }

deps=$(lsmod | awk '$1 == "surface_aggregator" { gsub(",", " ", $4); print $4 }')
# rmmod rather than modprobe -r, which can't handle a module loaded by insmod.
# Dependents can hold each other (surface_hid on surface_hid_core), so retry
# until they're all gone.
loaded() { lsmod | awk -v m="$1" '$1 == m { found = 1 } END { exit !found }'; }
for _ in 1 2 3; do
    for m in $deps; do
        loaded "$m" && rmmod "$m" 2>/dev/null || true
    done
done
if loaded surface_aggregator; then rmmod surface_aggregator; fi
modprobe crc_itu_t
insmod "$ko"
# The registry creates the SAM devices, which udev then loads drivers for, but
# reload what was there before too in case anything isn't picked up that way.
modprobe surface_aggregator_registry
for m in $deps; do modprobe "$m"; done

dmesg | grep -iE 'surface_serial_hub|surface_aggregator' | tail -5
