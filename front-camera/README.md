# Front Camera

The Surface Pro 10's front camera is a Sony IMX681 (ACPI `SONY0681`), connected to the Meteor Lake IPU6 over 2-lane MIPI CSI-2 at 380.8 MHz.

Two things are missing from the kernel:

* A driver for the sensor. `src/imx681.c` is the one from linux-surface PR #2156 (by Andre Gilerson, with the Surface Pro 10 work by djmulder), reverse-engineered from Windows I2C traces. That PR reports 1920x1080 at about 16fps, working in Firefox and Teams through PipeWire.
* An entry for the sensor in `ipu-bridge`, which tells the IPU6 driver which sensors exist. `src/ipu-bridge.patch` adds it, plus a reprobe of the sensor once the bridge has set it up, in case the sensor driver loaded first.

The image processing is done by libcamera's software ISP, which Bazzite already ships along with the PipeWire libcamera plugin.

**Status:** working. `cam` captures 1920x1136 at about 16fps.

The PR's driver turned on both the horizontal and vertical flip (register `0x0101` = `0x03`), which gave an upside-down picture. Flipping also changes the colour-filter order the sensor reads out in, while the driver still reported the native RGGB, so red and blue were swapped. This repo's copy turns the flips off, which fixes both.

`imx681.yaml` is a libcamera tuning file, installed to `/etc/libcamera/ipa/simple/`. Without it, libcamera falls back to generic settings, and the picture is washed out and muted. The tuning file does two things:

* **Black level.** It fixes the black level at 68 (10-bit). Raw frames show the sensor's true black level is 64. Without a fixed value, libcamera guesses it from the darkest pixels, noise drags the guess down, and blacks come out grey. Setting it slightly high also pushes the noisiest shadows to black.
* **Colour.** It adds a 1.2x saturation boost, as a colour matrix. This isn't a measured calibration.

Edit it and run `systemctl --user restart wireplumber` to try other values.

## Usage

1. Set up the signing key, if you haven't already (see "Module Signing" in the main README).
2. `./build.sh` builds and signs both modules for the running kernel into `out/<kernel version>/`. It fetches `ipu-bridge.c` from the matching upstream stable tag and patches it, so run it again after a kernel update.
3. `./install.sh` copies them to `/usr/local/lib/surface-pro-10/front-camera/<kernel version>/` (labelled for SELinux, which otherwise refuses to load them) and enables `front-camera.service`, which loads them at every boot.

It also installs `51-hide-ipu6-nodes.conf` into `/etc/wireplumber/wireplumber.conf.d/`. That hides the IPU6's dozens of raw capture nodes from PipeWire: they can't stream on their own, and apps such as GNOME Camera may pick one and fail with "Link has been severed". Run `systemctl --user restart wireplumber` for it to take effect without logging out.

The service runs before the login screen, because the stock IPU6 modules can't be swapped out once PipeWire has the camera open. After a kernel update, run `./build.sh` and `./install.sh` again, or `make modules` at the top of the repo. Until you do, the service is skipped and there's no front camera.

To load them by hand for the current boot only, without installing, run `sudo sh load.sh`. It swaps the stock `ipu-bridge` for the patched one, loads `imx681`, and prints the relevant kernel log. If PipeWire already has the camera open, stop it first with `systemctl --user stop wireplumber`, and start it again afterwards. Don't run `cam` until WirePlumber has had a few seconds to start, or it can grab the camera first and WirePlumber won't offer it to apps until it's restarted again.

Then check with `cam -l` and `cam -c 1 --capture=10`, or open the camera in Firefox.

## Still to do

* Rebuild the modules automatically after kernel updates.
* Noise. Even indoors the sensor only uses about 5-8% of its range at maximum exposure, and libcamera's software ISP does no noise reduction. libcamera also has no IMX681 sensor helper, so it doesn't know how the gain register maps to real gain, and its auto exposure won't raise analogue gain much. djmulder's gist (`2ce4980d8fc438bf72201d361f4a55e4`) is a libcamera patch that adds one (gain = 1024/(1024 - code), black level 64), but using it means rebuilding libcamera. It would be worth sending upstream.
* A measured colour matrix in place of the generic saturation boost.
