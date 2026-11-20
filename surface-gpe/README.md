# Surface GPE (Lid Wake)

**Working**, but needs rebuilding after each kernel update (see below)

Opening the lid (or the Flex Keyboard cover) doesn't wake the Surface Pro 10 from suspend; only the power button does.

On Surfaces, lid wake is set up by the kernel's `surface_gpe` module. It arms the ACPI GPE (general-purpose event) that the firmware raises when the lid changes, so that it can wake the system. The GPE number differs per model, so the module has a table of models, and it refuses to load on anything not in it. The Surface Pro 10 isn't there.

The number comes from the lid's GPE handler in the DSDT. On this machine `_L2E` is the only GPE handler that references the lid (`LID0`), and `/sys/firmware/acpi/interrupts/gpe2E` counts up as the lid is closed and opened. `src/surface-pro-10.patch` adds the Surface Pro 10 for Business to the table with GPE `0x2E`.

The keyboard doesn't wake the system, with or without this. Key presses go through the Surface Aggregator, whose wake-up the driver deliberately leaves off (`/sys/bus/serial/devices/serial0-0/power/wakeup`), because the EC also wakes the system for other reasons, such as the battery level. Turning it on didn't make key presses wake it here either.

## Usage

Set up the signing key first, if you haven't already (see "Module Signing" in the main README).

1. `./build.sh` fetches `surface_gpe.c` from the matching upstream stable tag, patches it, and builds and signs it into `out/<kernel version>/`.
2. `./install.sh` copies it to `/usr/local/lib/surface-pro-10/surface-gpe/<kernel version>/` (labelled for SELinux, which otherwise refuses to load it) and enables `surface-gpe-patched.service`, which loads it at every boot. The stock module never loads on this machine, so there's nothing to swap out.

After a kernel update, run `./build.sh` and `./install.sh` again, or `make modules` at the top of the repo. Until you do, the service is skipped and only the power button wakes the system.

To load it by hand for the current boot only, without installing, run `sudo sh load.sh`.

## Still to do

* Send the table entry upstream, so the stock module supports the Surface Pro 10.
