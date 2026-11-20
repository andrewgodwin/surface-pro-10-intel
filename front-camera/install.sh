#!/bin/sh
# Install the built modules for the running kernel to /usr/local, and enable
# the service that loads them at boot. Run ./build.sh first, and run both
# again after a kernel update.
set -eu
cd "$(dirname "$0")"

kver=$(uname -r)
dest=/usr/local/lib/surface-pro-10/front-camera
[ -f "out/$kver/imx681.ko" ] || { echo "Nothing built for this kernel, run ./build.sh first" >&2; exit 1; }

sudo install -D -m 0644 "out/$kver/imx681.ko" "$dest/$kver/imx681.ko"
sudo install -m 0644 "out/$kver/ipu-bridge.ko" "$dest/$kver/ipu-bridge.ko"
sudo install -m 0755 load.sh "$dest/load.sh"
sh ../label-modules.sh

# libcamera tuning (black level and colour) for the software ISP
sudo install -D -m 0644 imx681.yaml /etc/libcamera/ipa/simple/imx681.yaml

# Hide the IPU6's raw capture nodes, so apps only see the libcamera camera
sudo install -D -m 0644 51-hide-ipu6-nodes.conf /etc/wireplumber/wireplumber.conf.d/51-hide-ipu6-nodes.conf

sudo cp front-camera.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable front-camera.service
echo "Installed for $kver, it will be loaded at next boot."
