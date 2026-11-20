# Install iptsd (touchscreen and pen) from the linux-surface repository
curl -fsSL https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc | sudo tee /etc/pki/rpm-gpg/RPM-GPG-KEY-linux-surface >/dev/null
sudo cp touchscreen/linux-surface.repo /etc/yum.repos.d/
sudo rpm-ostree install --idempotent --apply-live -y iptsd

# Hide the raw touchscreen/stylus devices so only iptsd's are used
sudo cp touchscreen/99-surface-pro-10-touchscreen.rules /etc/udev/rules.d/
sudo udevadm control --reload
sudo udevadm trigger --action=add --subsystem-match=hidraw
sudo udevadm trigger --action=change --subsystem-match=input

# Reload the touchscreen driver across sleep, as it doesn't survive resume
sudo cp touchscreen/quickspi-sleep.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable quickspi-sleep.service

# Keep the keyboard's touchpad working when the tablet mode switch misfires
sudo install -D -m 0644 touchpad/local-overrides.quirks /etc/libinput/local-overrides.quirks

echo
echo "Done. Log out and back in for the touchscreen and touchpad changes."
