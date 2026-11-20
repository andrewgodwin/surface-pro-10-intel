#!/bin/sh
# Build and sign a patched surface_gpe module for the running kernel. The
# source is fetched from the matching upstream stable tag and patched, so this
# works again after a kernel update. Signs with the repo's MOK key.
#
# Output goes to out/<kernel version>/.
set -eu
cd "$(dirname "$0")"

kver=$(uname -r)
kdir=/lib/modules/$kver/build
base=${kver%%-*}            # 7.3.4-ogc8.1.fc45.x86_64 -> 7.3.4
tag=v${base%.0}             # upstream tags x.y.0 as vx.y
mok=../mok
out=out/$kver
build=build/$kver
path=drivers/platform/surface
url="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/$path"

[ -f $mok/MOK.priv ] || { echo "No signing key, run ../make-key.sh first" >&2; exit 1; }

rm -rf "$build"
mkdir -p "$build/$path" "$out"

curl -fsS -o "$build/$path/surface_gpe.c" "$url/surface_gpe.c?h=$tag"
echo 'obj-m += surface_gpe.o' > "$build/$path/Makefile"
git -C "$build" init -q
for p in src/*.patch; do
    git -C "$build" apply "$PWD/$p"
done

make -s -C "$kdir" M="$PWD/$build/$path" modules
"$kdir/scripts/sign-file" sha512 $mok/MOK.priv $mok/MOK.der "$build/$path/surface_gpe.ko"
cp "$build/$path/surface_gpe.ko" "$out/"

rm -rf build
echo "Built and signed: $out/surface_gpe.ko"
