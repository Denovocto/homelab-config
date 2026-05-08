#!/bin/bash
# Bootstrap script for initial homelab setup
# This script helps set up the homelab from scratch

set -e

# Source optional config file if it exists
[ -f ~/.config/homelab.env ] && source ~/.config/homelab.env
[ -f /etc/homelab.env ] && source /etc/homelab.env

# Allow override via environment variable, default to ~/homelab-config
REPO_DIR="${HOMELAB_REPO_DIR:-$HOME/homelab-config}"

echo "======================================"
echo "Homelab Bootstrap Script"
echo "======================================"
echo ""
echo "Using repository at: $REPO_DIR"
echo ""

# Check if running on the correct system
if [ ! -d "$REPO_DIR" ]; then
    echo "Error: Repository not found at $REPO_DIR"
    exit 1
fi

echo "1. Checking prerequisites..."
echo ""

# Check for required tools
command -v podman >/dev/null 2>&1 || { echo "Error: podman is not installed"; exit 1; }
command -v systemctl >/dev/null 2>&1 || { echo "Error: systemd is not available"; exit 1; }

echo "✓ Podman installed: $(podman --version)"
echo "✓ Systemd available"
echo ""

# Enable linger for user services
echo "2. Enabling systemd user services..."
loginctl enable-linger "$USER"
echo "✓ User linger enabled"
echo ""

# Deploy Quadlets
echo "3. Deploying Quadlets..."
"$REPO_DIR/scripts/deploy.sh"
echo ""

# Check for secrets
echo "4. Checking Podman secrets..."
echo ""
secret_count=$(podman secret ls --format "{{.Name}}" | wc -l)

if [ "$secret_count" -eq 0 ]; then
    echo "⚠ No Podman secrets found!"
    echo ""
    echo "You need to create secrets before starting services."
    echo "See: $REPO_DIR/secrets/README.md"
    echo ""
    echo "Required secrets:"
    echo "  - authelia-jwt-secret"
    echo "  - authelia-session-secret"
    echo "  - authelia-storage-key"
    echo "  - grafana-admin-password"
    echo "  - minecraft-discord-webhook (optional)"
    echo "  - cloudflare-api-token (optional)"
    echo ""
else
    echo "✓ Found $secret_count Podman secret(s):"
    podman secret ls --format "  - {{.Name}}"
    echo ""
fi

# Check for Authelia users database
echo "5. Checking Authelia configuration..."
if [ ! -f "$REPO_DIR/configs/authelia/users_database.yml" ]; then
    echo "⚠ Authelia users database not found!"
    echo ""
    echo "You need to create users_database.yml from the template."
    echo "Template: $REPO_DIR/configs/authelia/users_database.yml.template"
    echo ""
    echo "To create users:"
    echo "  1. Copy the template:"
    echo "     cp configs/authelia/users_database.yml.template configs/authelia/users_database.yml"
    echo ""
    echo "  2. Generate password hash:"
    echo "     podman run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password 'YourPassword'"
    echo ""
    echo "  3. Add users to users_database.yml with their password hashes"
    echo ""
else
    echo "✓ Authelia users database exists"
    echo ""
fi

# Update Caddyfile domain placeholders
echo "6. Checking Caddy configuration..."
if grep -q "yourdomain.com" "$REPO_DIR/configs/caddy/Caddyfile"; then
    echo "⚠ Caddyfile contains placeholder domains!"
    echo ""
    echo "You need to update $REPO_DIR/configs/caddy/Caddyfile"
    echo "Replace 'yourdomain.com' with your actual domain"
    echo ""
else
    echo "✓ Caddyfile configured"
    echo ""
fi

echo "======================================"
echo "Bootstrap Complete!"
echo "======================================"
echo ""
echo "Next steps:"
echo ""
echo "1. Create required secrets (if not done):"
echo "   See: $REPO_DIR/secrets/README.md"
echo ""
echo "2. Create Authelia users database (if not done):"
echo "   cp configs/authelia/users_database.yml.template configs/authelia/users_database.yml"
echo "   # Then edit and add users with password hashes"
echo ""
echo "3. Update Caddyfile with your domain (if not done):"
echo "   Edit: $REPO_DIR/configs/caddy/Caddyfile"
echo ""
echo "4. Configure environment files:"
echo "   Edit service configurations as needed:"
echo "   - configs/minecraft/minecraft.env"
echo "   - configs/grafana/grafana.env"
echo "   - configs/restic/restic.env (copy from .template first)"
echo ""
echo "5. Enable and start all services (auto-start on boot):"
echo "   $REPO_DIR/scripts/enable-all-services.sh"
echo ""
echo "6. Verify services are running:"
echo "   systemctl --user list-units --type=service --state=running"
echo "   systemctl --user list-timers"
echo ""
