#!/bin/bash
# Removes msi-fancontrol. Leaves the msi-ec driver installed (remove it with `sudo make dkms-uninstall` in its repo).
set -e
[ "$EUID" -eq 0 ] || exec sudo "$0" "$@"
systemctl disable --now msi-fancontrol.service 2>/dev/null || true   # stopping restores comfort + no boost
rm -f /etc/systemd/system/msi-fancontrol.service /usr/local/bin/msi-fancontrol.sh /usr/local/bin/fanprofile
rm -rf /var/lib/msi-fancontrol
systemctl daemon-reload
echo "msi-fancontrol removed. /etc/modules-load.d/msi-ec.conf and /etc/default/msi-fancontrol (if any) were left in place."
