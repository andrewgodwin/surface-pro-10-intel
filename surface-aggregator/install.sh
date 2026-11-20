#!/bin/sh
# Install the built module for the running kernel to /usr/local, and enable the
# service that swaps it in at boot. Run ./build.sh first, and run both again
# after a kernel update.
set -eu
cd "$(dirname "$0")"

kver=$(uname -r)
dest=/usr/local/lib/surface-pro-10/surface-aggregator
[ -f "out/$kver/surface_aggregator.ko" ] || { echo "Nothing built for this kernel, run ./build.sh first" >&2; exit 1; }

sudo install -D -m 0644 "out/$kver/surface_aggregator.ko" "$dest/$kver/surface_aggregator.ko"
sudo install -m 0755 load.sh "$dest/load.sh"
sh ../label-modules.sh

sudo cp surface-aggregator-patched.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable surface-aggregator-patched.service
echo "Installed for $kver, it will be loaded at next boot."
