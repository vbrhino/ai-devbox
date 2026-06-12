#!/bin/bash
# Fix SSH key access for pi user
set -e

KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOs7ixkOOMsv73Od2Pg7H5itSotwcp3rrTIHawjggrDd rvb@PW08HMY7'

echo "=== Adding SSH key for pi ==="
mkdir -p /home/pi/.ssh
echo "$KEY" > /home/pi/.ssh/authorized_keys
chmod 700 /home/pi/.ssh
chmod 600 /home/pi/.ssh/authorized_keys
chown -R pi:pi /home/pi/.ssh

echo "=== Current sshd config ==="
grep -i "AuthorizedKeysFile\|PubkeyAuthentication" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null || true

echo "=== Recent auth failures ==="
journalctl -u ssh --no-pager -n 5 2>/dev/null || tail -5 /var/log/auth.log 2>/dev/null || echo "(no logs available)"

echo "=== Restarting SSH ==="
systemctl restart ssh
sleep 1
systemctl status ssh --no-pager | head -5

echo ""
echo "Done! Key added. Pi should now connect."
