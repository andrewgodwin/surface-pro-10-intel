#!/bin/sh
# Build and sign the imx681 and patched ipu-bridge modules for the running
# kernel. The ipu-bridge source is fetched from the matching upstream stable
# tag and patched, so this works again after a kernel update.
#
# Output goes to out/<kernel version>/.
set -eu
cd "$(dirname "$0")"

kver=$(uname -r)
kdir=/lib/modules/$kver/build
base=${kver%%-*}            # 7.3.3-ogc1.1.fc45.x86_64 -> 7.3.3
tag=v${base%.0}             # upstream tags x.y.0 as vx.y
out=out/$kver
build=build/$kver

[ -f mok/MOK.priv ] || { echo "No signing key, run ./make-key.sh first" >&2; exit 1; }

rm -rf "$build"
mkdir -p "$build/imx681" "$build/ipu-bridge/drivers/media/pci/intel" "$out"

cp src/imx681.c "$build/imx681/"
echo 'obj-m += imx681.o' > "$build/imx681/Makefile"

curl -fsS -o "$build/ipu-bridge/drivers/media/pci/intel/ipu-bridge.c" \
    "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/media/pci/intel/ipu-bridge.c?h=$tag"
git -C "$build/ipu-bridge" init -q
git -C "$build/ipu-bridge" apply "$PWD/src/ipu-bridge.patch"
mv "$build/ipu-bridge/drivers/media/pci/intel/ipu-bridge.c" "$build/ipu-bridge/"
echo 'obj-m += ipu-bridge.o' > "$build/ipu-bridge/Makefile"

for m in imx681 ipu-bridge; do
    make -s -C "$kdir" M="$PWD/$build/$m" modules
    "$kdir/scripts/sign-file" sha512 mok/MOK.priv mok/MOK.der "$build/$m/$m.ko"
    cp "$build/$m/$m.ko" "$out/"
done

rm -rf build
echo "Built and signed: $(ls "$out" | tr "\n" " ")"
