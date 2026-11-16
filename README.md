# Linux tweaks for the Microsoft Surface Pro 10 (Intel)

This repository contains my tweaks to get Linux running well on the Intel Surface Pro 10 for Business, with the Surface Pro Flex Keyboard.

`sh install-fedora-atomic.sh` should install all the relevant tweaks if you are running Fedora Atomic/Universal Blue/Bazzite. The Bluetooth key import for the Flex keyboard is separate, along with camera fixes if you want them (see below).

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

## Touchpad in Tablet Mode

The tablet mode switch reports posture `0` for the Flex Keyboard, which the `surface_aggregator_tabletsw` driver doesn't know - a libinput quirk prevents this from turning the touchpad off in tablet mode but as a side effect keeps tablet mode on all the time, which I consider fine.

## Front Camera

**Work in progress - not yet confirmed working**

The front camera is a Sony IMX681 (`SONY0681`) on the IPU6. The upstream IPU6 capture driver loads, but there's no IMX681 driver in the kernel, and the IPU bridge doesn't know the sensor. The `front-camera` directory builds both as out-of-tree modules, signed with your own Secure Boot key, and libcamera's software ISP (already in Bazzite) does the image processing. See `front-camera/README.md`.

## Rear Camera

Not working yet.

It's an OmniVision OV13858 and the stock driver fails to probe as it never turns on the sensor's power rails, clock or reset line, and the INT3472 power controller uses a GPIO type (`0x08`) this kernel doesn't know. linux-surface issue #2153 has fixes, but they're not here yet.
