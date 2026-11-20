# Surface Pro 10 (Intel) tweaks for Fedora Atomic / Universal Blue / Bazzite.
#
#   make install   First-time setup: system tweaks, then the patched modules
#   make modules   Rebuild and reinstall the modules (run after a kernel update)
#
# Run as your normal user; the scripts use sudo where they need it.

KVER := $(shell uname -r)

.PHONY: help install system key check-key modules build \
        surface-aggregator surface-gpe front-camera clean

help:
	@echo "make install    First-time setup: system tweaks and patched modules"
	@echo "make modules    Rebuild and reinstall the modules for the running kernel"
	@echo "                (run after every kernel update, once rebooted into it)"
	@echo ""
	@echo "make system     Only the system tweaks (touchscreen, touchpad)"
	@echo "make key        Make the module signing key and queue it for enrollment"
	@echo "make build      Only build the modules, don't install them"
	@echo "make clean      Remove built modules"

# The modules need the signing key enrolled, which takes a reboot, so a first
# install stops after queueing the key and says what to do next.
install: system
	@if [ -f mok/MOK.priv ] && ! mokutil --test-key mok/MOK.der >/dev/null 2>&1; then \
	    $(MAKE) --no-print-directory modules; \
	else \
	    sh make-key.sh && \
	    echo && \
	    echo "Then run 'make modules' to build and install the suspend, lid wake and camera fixes."; \
	fi

system:
	sh install-fedora-atomic.sh

key:
	sh make-key.sh

# The modules are signed with the local MOK key, which has to be enrolled
# (a reboot through the MOK management screen) before the kernel accepts them.
# mokutil --test-key succeeds only when the key is NOT enrolled.
check-key:
	@[ -f mok/MOK.priv ] || { \
	    echo "No signing key yet. Run 'make key', reboot to enroll it, then run this again." >&2; \
	    exit 1; }
	@if mokutil --test-key mok/MOK.der >/dev/null 2>&1; then \
	    echo "The signing key isn't enrolled yet. Run 'make key', reboot to enroll it, then run this again." >&2; \
	    exit 1; \
	fi

modules: check-key surface-aggregator surface-gpe front-camera
	@echo
	@echo "Modules installed for $(KVER). Reboot to load them."

build: check-key
	sh surface-aggregator/build.sh
	sh surface-gpe/build.sh
	sh front-camera/build.sh

surface-aggregator: check-key
	sh surface-aggregator/build.sh
	sh surface-aggregator/install.sh

surface-gpe: check-key
	sh surface-gpe/build.sh
	sh surface-gpe/install.sh

front-camera: check-key
	sh front-camera/build.sh
	sh front-camera/install.sh

clean:
	rm -rf surface-aggregator/out surface-aggregator/build surface-gpe/out surface-gpe/build front-camera/out front-camera/build
