#!/bin/bash
# Enable all homelab services for auto-start on boot
# This is a simple helper script - minimal logic as requested

set -e

echo "Enabling all homelab services for auto-start on boot..."
echo ""

# List of services to enable
SERVICES=(
    "homelab-network.service"
    "caddy.service"
    "authelia.service"
    "minecraft.service"
    "prometheus.service"
    "grafana.service"
)

TIMERS=(
    "restic-backup.timer"
)

# Enable and start services
for service in "${SERVICES[@]}"; do
    echo "Enabling: $service"
    systemctl --user enable --now "$service"
done

echo ""

# Enable and start timers
for timer in "${TIMERS[@]}"; do
    echo "Enabling: $timer"
    systemctl --user enable --now "$timer"
done

echo ""
echo "✓ All services enabled and started"
echo ""
echo "Services will now auto-start on boot (requires user linger to be enabled)"
echo ""
echo "Check status:"
echo "  systemctl --user list-units --type=service --state=running | grep -E '(homelab|minecraft|caddy|authelia|prometheus|grafana)'"
echo "  systemctl --user list-timers"
