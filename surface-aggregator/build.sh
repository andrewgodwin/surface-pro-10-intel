#!/bin/sh
# Build and sign a patched surface_aggregator module for the running kernel.
# The source is fetched from the matching upstream stable tag and patched, so
# this works again after a kernel update. Signs with the repo's MOK key.
#
# Output goes to out/<kernel version>/.
set -eu
cd "$(dirname "$0")"

kver=$(uname -r)
kdir=/lib/modules/$kver/build
base=${kver%%-*}            # 7.3.3-ogc1.1.fc45.x86_64 -> 7.3.3
tag=v${base%.0}             # upstream tags x.y.0 as vx.y
mok=../mok
out=out/$kver
build=build/$kver
path=drivers/platform/surface/aggregator
url="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/$path"

[ -f $mok/MOK.priv ] || { echo "No signing key, run ../make-key.sh first" >&2; exit 1; }

rm -rf "$build"
mkdir -p "$build/$path" "$out"

for f in Makefile bus.c bus.h controller.c controller.h core.c ssh_msgb.h \
         ssh_packet_layer.c ssh_packet_layer.h ssh_parser.c ssh_parser.h \
         ssh_request_layer.c ssh_request_layer.h trace.h; do
    curl -fsS -o "$build/$path/$f" "$url/$f?h=$tag"
done
git -C "$build" init -q
for p in src/*.patch; do
    git -C "$build" apply "$PWD/$p"
done

make -s -C "$kdir" M="$PWD/$build/$path" CONFIG_SURFACE_AGGREGATOR=m CONFIG_SURFACE_AGGREGATOR_BUS=y modules
"$kdir/scripts/sign-file" sha512 $mok/MOK.priv $mok/MOK.der "$build/$path/surface_aggregator.ko"
cp "$build/$path/surface_aggregator.ko" "$out/"

rm -rf build
echo "Built and signed: $out/surface_aggregator.ko"
