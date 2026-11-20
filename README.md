# Linux tweaks for the Microsoft Surface Pro 10 (Intel)

This repository contains my tweaks to get Linux running well on the Intel Surface Pro 10 for Business, with the Surface Pro Flex Keyboard.

## Installing

On Fedora Atomic, Universal Blue or Bazzite, run `make install` as your normal user. The scripts use sudo where they need it.

The suspend and camera fixes are patched kernel modules, which need a signing key enrolled first (see "Module Signing"). So the first `make install` does the following:

1. Installs the system tweaks: touchscreen, pen and touchpad.
2. Makes the signing key and queues it for enrollment.

Reboot and enroll the key, then run `make modules` to build and install the patched modules. Reboot again to load them.

**After every kernel update**, once you've rebooted into the new kernel, run `make modules` again. Until you do, suspend, lid wake and the front camera won't work.

Run `make` on its own to list the other targets. `make system` runs only the system tweaks; it's the same as `sh install-fedora-atomic.sh`. The Bluetooth key import for the Flex keyboard is separate (see below).

## Module Signing

The suspend, lid wake and camera fixes build patched kernel modules, and Secure Boot makes the kernel refuse unsigned ones ("Key was rejected by service"). `make key` (or `./make-key.sh`) makes a local Machine Owner Key in `mok/` and queues it for enrollment. Reboot, and on the blue "MOK management" screen choose Enroll MOK -> Continue -> Yes, enter the password you set, then Reboot. You only need to do this once.

Keep `mok/MOK.priv` safe: anything signed with it will load on this machine. It's in `.gitignore`. To remove the key later, run `sudo mokutil --delete mok/MOK.der` and reboot.

Each fix's `install.sh` copies its modules to `/usr/local/lib/surface-pro-10/` and enables a service that loads them at boot. `label-modules.sh` labels that directory for SELinux, which otherwise won't let the kernel load modules from it. `make modules` runs each fix's `build.sh` and `install.sh`.

## Already working on Bazzite (Fedora 45 / Kernel 7.3)

WiFi, Bluetooth, battery, charger, fan, temperature sensors, platform profiles, and the Flex Keyboard over its pogo pins.

## Flex Keyboard over Bluetooth

When the Flex Keyboard is detached it switches to Bluetooth LE, and pairing keys for it are automagically done via Windows over its physical link. I have a Windows dual-boot, so I let Windows make the pairing keys and then import them.

`bluetooth-keyboard/win-bt-import.py` copies the keys from the Windows partition. It requires that BitLocker is turned off on the Windows install:

```
sudo bluetooth-keyboard/win-bt-import.py --dry-run
sudo bluetooth-keyboard/win-bt-import.py --filter keyboard
```

If it warns that the hive is "dirty", boot Windows and do a full shutdown with `shutdown /s /t 0`, as fast startup can leave recent pairings unwritten. It also works for other dual-pairing-desired devices, not just the flex keyboard.

## Touchscreen and Pen

The digitizer sends raw capacitive heatmaps rather than finished touch reports, so it needs `iptsd` from the linux-surface project to turn them into touch and pen input.

The install script layers it using `rpm-ostree` from the linux-surface repository (`touchscreen/linux-surface.repo`).

The udev rule in `touchscreen/` then hides the kernel's original touch/pen devices from libinput to avoid flickering.

The touch controller doesn't survive the kernel driver's own suspend and resume: after a real sleep it stops answering, even though the driver's reset on resume reports success. A full reload of the driver does bring it back, so `touchscreen/quickspi-sleep.service` unloads `intel_quickspi` before sleep and loads it again on wake. That only helps once suspend itself works (see below).

## Touchpad in Tablet Mode

The tablet mode switch reports posture `0` for the Flex Keyboard, which the `surface_aggregator_tabletsw` driver doesn't know - a libinput quirk prevents this from turning the touchpad off in tablet mode but as a side effect keeps tablet mode on all the time, which I consider fine.

## Suspend

**Working, but needs rebuilding after each kernel update**

Suspend fails on the stock kernel: the Surface Aggregator takes 3-4 seconds to answer the "leaving D0" notification, and the driver gives up after 3. The aborted suspends also break the touchscreen and pen until a reboot. The `surface-aggregator` directory builds a patched module with a longer timeout, and installs a service that loads it at boot. See `surface-aggregator/README.md`.

In Plasma, set "When power button pressed" (System Settings, Power Management) to something other than Sleep. Otherwise the press that wakes the machine also reaches Plasma as a sleep request, and it goes straight back to sleep. That quick back-to-back sleep can also interrupt the touchscreen driver reload and leave touch dead. If that happens, `sudo modprobe -r intel_quickspi && sudo modprobe intel_quickspi` brings it back.

### Waking from Suspend

**Working, but needs rebuilding after each kernel update**

Opening the lid didn't wake the machine, only the power button did. The kernel's `surface_gpe` module sets up lid wake on Surfaces, but it doesn't know the Surface Pro 10, whose lid uses ACPI GPE `0x2E`. The `surface-gpe` directory builds a patched module that does, and installs a service that loads it at boot. See `surface-gpe/README.md`.

Pressing a key on the keyboard still doesn't wake it.

## Front Camera

**Working, but needs rebuilding after each kernel update**

The front camera is a Sony IMX681 (`SONY0681`) on the IPU6. The upstream IPU6 capture driver loads, but there's no IMX681 driver in the kernel, and the IPU bridge doesn't know the sensor. The `front-camera` directory builds both as out-of-tree modules, signed with your own Secure Boot key, and libcamera's software ISP (already in Bazzite) does the image processing. A service loads the modules at boot. See `front-camera/README.md`.

## Rear Camera

Not working yet.

It's an OmniVision OV13858 and the stock driver fails to probe as it never turns on the sensor's power rails, clock or reset line, and the INT3472 power controller uses a GPIO type (`0x08`) this kernel doesn't know. linux-surface issue #2153 has fixes, but they're not here yet.
