#!/bin/bash
# Removes fan-boost. Leaves the msi-ec driver installed (remove it with `sudo make dkms-uninstall` in its repo).
set -e
[ "$EUID" -eq 0 ] || exec sudo "$0" "$@"
systemctl disable --now fan-boost.service 2>/dev/null || true   # stopping restores comfort + no boost
rm -f /etc/systemd/system/fan-boost.service /usr/local/bin/fan-boost.sh /usr/local/bin/fanprofile
rm -rf /var/lib/fan-boost
systemctl daemon-reload
echo "fan-boost removed. /etc/modules-load.d/msi-ec.conf and /etc/default/fan-boost (if any) were left in place."
