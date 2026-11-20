#!/bin/sh
# Load the patched surface_gpe, for this boot only. The stock module doesn't
# know the Surface Pro 10 and refuses to load, so there's normally nothing to
# swap out.
#
# Usage: sudo sh load.sh [directory holding <kernel version>/surface_gpe.ko]
set -eu
cd "$(dirname "$0")"

ko=${1:-out}/$(uname -r)/surface_gpe.ko
[ -f "$ko" ] || { echo "Nothing built for this kernel, run ./build.sh first" >&2; exit 1; }

if lsmod | awk '$1 == "surface_gpe" { found = 1 } END { exit !found }'; then
    rmmod surface_gpe
fi
insmod "$ko"
