# Surface Aggregator (Suspend)

**Working**, but needs rebuilding after each kernel update (see below)

Suspend fails on the stock 7.3 kernel. The Surface Aggregator Module (SAM, the embedded controller behind the battery, keyboard and buttons) has to be told the system is leaving D0 before it sleeps, and that request times out:

```
surface_serial_hub serial0-0: rtl: dropping unexpected command message (rqid = 0x0213)
surface_serial_hub serial0-0: pm: D0-exit notification failed: -110
surface_serial_hub serial0-0: PM: failed to suspend: error -110
```

The kernel aborts the suspend and resumes everything, then systemd (or the desktop) tries again. You get a black screen for 30 seconds or more, the power button seems to do nothing, and the touchscreen and pen break: each aborted attempt resets the touch controller, which then stops answering until a reboot.

Tracing the `surface_aggregator` events shows the EC ACKs the D0-exit command (`tc=SAM cid=0x33`) straight away, but only sends its response 3.1-4 seconds later, sometimes 7. Every other command answers in about a millisecond. The driver gives up on a response after a fixed 3 seconds (`SSH_RTL_REQUEST_TIMEOUT`), so it times out just before the reply arrives. The late reply is then dropped as "unexpected", and all three retries fail the same way.

`src/request-timeout.patch` raises that timeout to 10 seconds.

The linux-surface kernel carries no changes to this part of the driver, so it most likely has the same problem.

## Usage

Set up the signing key first, if you haven't already (see "Module Signing" in the main README).

1. `./build.sh` fetches the driver from the matching upstream stable tag, patches it, and builds and signs it into `out/<kernel version>/`. Run it again after a kernel update.
2. `./install.sh` copies it to `/usr/local/lib/surface-pro-10/surface-aggregator/<kernel version>/` (labelled for SELinux, which otherwise refuses to load it) and enables `surface-aggregator-patched.service`, which swaps it in at every boot.

The stock module is loaded from the initramfs, so the service has to replace it after boot. That means unloading the stock module first, which runs into the same slow D0-exit, so the pogo keyboard drops out for about 10 seconds early in each boot.

After a kernel update, run `./build.sh` and `./install.sh` again, or `make modules` at the top of the repo. Until you do, the service is skipped and the stock module stays, so suspend is broken again.

To swap it in by hand for the current boot only, without installing, run `sudo sh load.sh`.

To test without really sleeping, run the device suspend callbacks and resume automatically after five seconds:

```
echo devices | sudo tee /sys/power/pm_test
echo mem | sudo tee /sys/power/state
echo none | sudo tee /sys/power/pm_test
```

If the `echo mem` step succeeds and there's no `D0-exit notification failed` in `dmesg`, the fix works.

## Still to do

* Rebuild it automatically after kernel updates.
* Find out why the EC is that slow to answer D0-exit, and report it upstream.
