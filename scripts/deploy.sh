#!/bin/bash
# Deploy Quadlets from git repo to systemd
# This script copies Quadlet files to the systemd user directory

set -e

# Source optional config file if it exists
[ -f ~/.config/homelab.env ] && source ~/.config/homelab.env
[ -f /etc/homelab.env ] && source /etc/homelab.env

# Allow override via environment variable, default to ~/homelab-config
REPO_DIR="${HOMELAB_REPO_DIR:-$HOME/homelab-config}"
SYSTEMD_DIR="$HOME/.config/containers/systemd"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

echo "Using repository at: $REPO_DIR"

# Ensure systemd directories exist
mkdir -p "$SYSTEMD_DIR"/{networks,volumes,containers}
mkdir -p "$SYSTEMD_USER_DIR"

# Copy Quadlets
echo "Deploying Quadlets..."
rsync -av --delete "$REPO_DIR/quadlets/networks/" "$SYSTEMD_DIR/networks/"
rsync -av --delete "$REPO_DIR/quadlets/volumes/" "$SYSTEMD_DIR/volumes/"
rsync -av --delete "$REPO_DIR/quadlets/containers/" "$SYSTEMD_DIR/containers/"

# Copy systemd timers
if [ -d "$REPO_DIR/quadlets/timers" ]; then
    echo "Deploying systemd timers..."
    rsync -av --delete "$REPO_DIR/quadlets/timers/" "$SYSTEMD_USER_DIR/"
fi

# Reload systemd
echo "Reloading systemd..."
systemctl --user daemon-reload

echo ""
echo "========================================"
echo "Deployment Complete!"
echo "========================================"
echo ""
echo "Quadlets deployed to systemd user directories."
echo ""
echo "Next steps:"
echo ""
echo "1. Enable and start all services (auto-start on boot):"
echo "   $REPO_DIR/scripts/enable-all-services.sh"
echo ""
echo "2. View running services:"
echo "   systemctl --user list-units --type=service --state=running"
echo ""
echo "3. View scheduled timers:"
echo "   systemctl --user list-timers"
echo ""
echo "Note: User linger must be enabled for auto-start on boot."
echo "  Check: loginctl show-user \$USER | grep Linger"
echo "  Enable: loginctl enable-linger \$USER"
