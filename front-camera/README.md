# Front Camera

The Surface Pro 10's front camera is a Sony IMX681 (ACPI `SONY0681`), connected to the Meteor Lake IPU6 over 2-lane MIPI CSI-2 at 380.8 MHz.

Two things are missing from the kernel:

* A driver for the sensor. `src/imx681.c` is the one from linux-surface PR #2156 (by Andre Gilerson, with the Surface Pro 10 work by djmulder), reverse-engineered from Windows I2C traces. That PR reports 1920x1080 at about 16fps, working in Firefox and Teams through PipeWire.
* An entry for the sensor in `ipu-bridge`, which tells the IPU6 driver which sensors exist. `src/ipu-bridge.patch` adds it, plus a reprobe of the sensor once the bridge has set it up, in case the sensor driver loaded first.

The image processing is done by libcamera's software ISP, which Bazzite already ships along with the PipeWire libcamera plugin.

**Status:** both modules build and sign, but haven't been loaded yet, so this is untested on this machine.

## Usage

1. `./make-key.sh` makes a signing key in `mok/` and queues it for enrollment. Reboot, and on the blue "MOK management" screen choose Enroll MOK -> Continue -> Yes, enter the password you set, then Reboot. You only need to do this once.
2. `./build.sh` builds and signs both modules for the running kernel into `out/<kernel version>/`. It fetches `ipu-bridge.c` from the matching upstream stable tag and patches it, so run it again after a kernel update.
3. `sudo sh load.sh` swaps the stock `ipu-bridge` for the patched one, loads `imx681`, and prints the relevant kernel log. It only lasts until reboot.

Then check with `cam -l` and `cam -c 1 --capture=10`, or open the camera in Firefox.

Secure Boot makes the kernel refuse unsigned modules ("Key was rejected by service"), which is why the key is needed. Keep `mok/MOK.priv` safe: anything signed with it will load on this machine. It's in `.gitignore`. To remove the key later, run `sudo mokutil --delete mok/MOK.der` and reboot.

## Still to do

* Load the modules automatically at boot, and rebuild them after kernel updates.
* A libcamera tuning file. djmulder's gist (`2ce4980d8fc438bf72201d361f4a55e4`) has an IMX681 sensor helper and tuning; without them the auto exposure and colour may be off.
