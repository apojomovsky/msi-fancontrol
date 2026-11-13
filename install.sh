#!/bin/bash
set -e
cd "$(dirname "$0")"
install -m 755 fan-boost.sh /usr/local/bin/fan-boost.sh
install -m 755 fanprofile /usr/local/bin/fanprofile
install -m 644 fan-boost.service /etc/systemd/system/fan-boost.service
echo msi_ec > /etc/modules-load.d/msi-ec.conf
mkdir -p /var/lib/fan-boost
[ -f /var/lib/fan-boost/profile ] || echo auto > /var/lib/fan-boost/profile
systemctl daemon-reload
systemctl enable fan-boost.service
systemctl restart fan-boost.service
systemctl --no-pager status fan-boost.service | head -5
