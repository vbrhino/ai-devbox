#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Run with: sudo bash setup-pi-user.sh"
    exit 1
fi

PI_USER="pi"
PI_HOME="/home/$PI_USER"
PI_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINADY+Z9DWXNWpbcGAPwl7v5zM2YGsuhw2cUgdLd5EKw rvb@PW08HMY7"

# Create user if not exists
if ! id "$PI_USER" &>/dev/null; then
    useradd -m -G sudo -s /bin/bash "$PI_USER"
    echo "Created user: $PI_USER"
else
    echo "User $PI_USER already exists — skipping creation"
    # Ensure they're in sudo group
    usermod -aG sudo "$PI_USER"
fi

# Add SSH key
mkdir -p "$PI_HOME/.ssh"
echo "$PI_KEY" > "$PI_HOME/.ssh/authorized_keys"
chown -R "$PI_USER:$PI_USER" "$PI_HOME/.ssh"
chmod 700 "$PI_HOME/.ssh"
chmod 600 "$PI_HOME/.ssh/authorized_keys"

# Set passwordless sudo
SUDOERS_FILE="/etc/sudoers.d/$PI_USER"
if [ ! -f "$SUDOERS_FILE" ]; then
    echo "$PI_USER ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_FILE"
    chmod 440 "$SUDOERS_FILE"
    echo "Passwordless sudo configured for $PI_USER"
else
    echo "Passwordless sudo already configured"
fi

echo "SSH key added for $PI_USER"
echo ""
echo "✅ Done. pi can now SSH in as: pi@100.116.127.78"
echo "   No password needed for SSH or sudo."
