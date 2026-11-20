#!/bin/sh
# Label /usr/local/lib/surface-pro-10 so SELinux lets the kernel load modules
# from it (it only allows files labelled modules_object_t). Used by the
# install scripts; safe to run more than once.
set -eu

dir=/usr/local/lib/surface-pro-10
if ! sudo semanage fcontext -l | grep "^$dir(" >/dev/null; then
    sudo semanage fcontext -a -t modules_object_t "$dir(/.*)?"
fi
sudo restorecon -R "$dir"
