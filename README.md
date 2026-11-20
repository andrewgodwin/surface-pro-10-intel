# Linux tweaks for the Microsoft Surface Pro 10 (Intel)

This repository contains my tweaks to get Linux running well on the Intel Surface Pro 10 for Business (that's the Intel version), with the Surface Pro Flex Keyboard.

## Installing

On Fedora Atomic/UBlue/Bazzite, run `make install`.

The suspend & camera fixes are patched kernel modules, which need a MOK key enrolled. So the first `make install`:

1. Installs the 'system' tweaks (ones that don't need modules)
2. Makes the signing key and queues it for enrollment

Reboot and enroll the key, then run `make modules` to build and install the new modules. Reboot _again_ to load them.

**After every kernel update**, once you're rebooted onto the new kernel, run `make modules` again.

The Bluetooth key import for the Flex keyboard is separate (see below).

## Module Signing

The suspend, lid wake and camera fixes build patched kernel modules, and Secure Boot makes the kernel refuse unsigned ones. `make key` (or `./make-key.sh`) makes a local Machine Owner Key in `mok/` and queues it for enrollment. Reboot, and on the blue "MOK management" screen choose Enroll MOK -> Continue -> Yes, enter the password you set, then Reboot. You only need to do this once.

Keep `mok/MOK.priv` safe: anything signed with it will load on this machine. To remove the key later, run `sudo mokutil --delete mok/MOK.der` and reboot.

(Each module is installed `/usr/local/lib/surface-pro-10/` and has a service that loads it at boot. We also label that directory for SELinux, as it stops kernel modules loading otherwise)

## Already Working

Working out of the box on Fedora 45 series distros:

* WiFi
* Bluetooth
* Battery/charger
* Fan
* Temperature sensors
* Platform/performance profiles
* Keyboard covers (when physically attached)

## Flex Keyboard over Bluetooth

When the Flex Keyboard is detached it switches to Bluetooth LE, and pairing keys for it are automagically done via Windows over its physical link. I have a Windows dual-boot, so I let Windows make the pairing keys and then import them.

`bluetooth-keyboard/win-bt-import.py` copies the keys from the Windows partition. It requires that BitLocker is turned off on the Windows install:

```
sudo bluetooth-keyboard/win-bt-import.py --dry-run
sudo bluetooth-keyboard/win-bt-import.py --filter keyboard
```

If it warns that the hive is "dirty", boot Windows and do a full shutdown with `shutdown /s /t 0`, as fast startup can leave recent pairings unwritten. It also works for other dual-pairing-desired devices, not just the flex keyboard.

## Touchscreen and Pen

The digitizer needs `iptsd` from the linux-surface project to do proper touch/pen input reports.

The install script layers it using `rpm-ostree` from the linux-surface repository (`touchscreen/linux-surface.repo`), then a udev rule in `touchscreen/` hides the kernel's original touch/pen devices from libinput to avoid flickering.

There's a bug where it doesn't work after suspend and resume; there is a little service (`quickspi-sleep`) that rmmods the `intel_quickspi` module right before sleep and re-adds it after wake.

## Touchpad in Tablet Mode

The tablet mode switch reports posture `0` for the Flex Keyboard, which the `surface_aggregator_tabletsw` driver doesn't know. A libinput quirk in here prevents this from turning the touchpad off in tablet mode but as a side effect keeps tablet mode on all the time, which I consider fine.

## Suspend

**Working, but needs rebuilding after each kernel update**

Suspend fails on the Fedora 45 kernel as `surface-aggregator` takes too long to respond during sleep. We build a patched one with a longer timeout and load it in at boot.

You should probably also not link the power button to immediately sleep, as doing so can make it double-bounce into sleep after a resume and get unhappy. I keep the Plasma default of "show logout options".

I also add the kernel arg `i915.enable_psr2_sel_fetch=0` due to some [upstream reports](https://github.com/linux-surface/linux-surface/issues/2158).

## Lid Switch Waking

**Working, but needs rebuilding after each kernel update**

The `surface_gpe` was missing a mapping for the Surface Pro 10, whose lid uses ACPI GPE `0x2E`. We install a patched version.

## Keyboard Waking

**Not working yet**

Not sure why this isn't working; telling the surface aggregator module to do a wake interrupt doesn't seem to help.

## Front Camera

**Working, but needs rebuilding after each kernel update**

The front camera is a Sony IMX681 (`SONY0681`) on the IPU6. The upstream IPU6 capture driver loads, but there's no IMX681 driver in the kernel, and the IPU bridge doesn't know the sensor. The `front-camera` directory builds both as out-of-tree modules, signed with your own Secure Boot key, and libcamera's software ISP (already in Bazzite) does the image processing.

## Rear Camera

**Not working yet**

It's an OmniVision OV13858 and the stock driver fails to probe as it never turns on the sensor's power rails, clock or reset line, and the INT3472 power controller uses a GPIO type (`0x08`) the kernel doesn't know. linux-surface issue #2153 has fixes, but they're not here yet.
