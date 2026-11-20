#!/bin/sh
# Create a local Machine Owner Key (MOK) for signing this repo's kernel modules, and
# queue it for enrollment. Secure Boot makes the kernel refuse unsigned modules.
#
# After running this, reboot and, on the blue "MOK management" screen, choose
# Enroll MOK -> Continue -> Yes, enter the password you set here, then Reboot.
# You only need to do this once.
set -eu
cd "$(dirname "$0")"

mkdir -p mok
chmod 700 mok
if [ ! -f mok/MOK.priv ]; then
    openssl req -new -x509 -newkey rsa:2048 -nodes -days 36500 \
        -subj "/CN=Surface module signing (local)/" \
        -outform DER -keyout mok/MOK.priv -out mok/MOK.der
    chmod 600 mok/MOK.priv
fi

if mokutil --test-key mok/MOK.der >/dev/null 2>&1; then
    sudo mokutil --import mok/MOK.der
    echo "Now reboot and enroll the key on the MOK management screen."
else
    echo "mok/MOK.der is already enrolled."
fi
