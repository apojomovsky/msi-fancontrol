#!/bin/bash
set -e
[ "$EUID" -eq 0 ] || exec sudo "$0" "$@"
cd "$(dirname "$0")"

install -m 755 msi-fancontrol.sh /usr/local/bin/msi-fancontrol.sh
install -m 755 fanprofile /usr/local/bin/fanprofile
install -m 644 msi-fancontrol.service /etc/systemd/system/msi-fancontrol.service
echo msi_ec > /etc/modules-load.d/msi-ec.conf
mkdir -p /var/lib/msi-fancontrol
[ -f /var/lib/msi-fancontrol/profile ] || echo auto > /var/lib/msi-fancontrol/profile
systemctl daemon-reload
systemctl enable msi-fancontrol.service
systemctl restart msi-fancontrol.service
systemctl --no-pager status msi-fancontrol.service | head -5
