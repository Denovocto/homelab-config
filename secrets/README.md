# Homelab Secrets Setup

This directory contains sensitive secrets for the homelab. **Nothing in this directory should be committed to git.**

## Required Secrets

### Authelia (SSO)
- **authelia-jwt-secret**: JWT signing key (64 char random hex)
- **authelia-session-secret**: Session encryption key (64 char random hex)
- **authelia-storage-key**: Database encryption key (64 char random hex)

### Caddy (Reverse Proxy)
- **cloudflare-api-token**: Cloudflare API token for DNS challenge (optional, only if using Cloudflare DNS)

### Minecraft
- **minecraft-discord-webhook**: Discord webhook URL for server alerts and notifications

### Grafana
- **grafana-admin-password**: Admin password for Grafana dashboard

### Tailscale (Optional if running as container)
- **tailscale-auth-key**: Tailscale auth key (get from https://login.tailscale.com/admin/settings/keys)

### Restic (Backup System)
- **restic-repository-password**: Password to encrypt restic repository (strong random password)
- **restic-ssh-key**: SSH private key for SFTP access to NAS (if using SFTP)
- **restic-discord-webhook**: Discord webhook URL for backup notifications (can reuse minecraft-discord-webhook)
- **discord-user-id**: Your Discord user ID for @mentions in backup alerts

## Creating Secrets

### 1. Generate Random Secrets

```bash
# Authelia secrets (32 bytes hex)
openssl rand -hex 32 | podman secret create authelia-jwt-secret -
openssl rand -hex 32 | podman secret create authelia-session-secret -
openssl rand -hex 32 | podman secret create authelia-storage-key -

# Grafana admin password
echo "your-secure-password" | podman secret create grafana-admin-password -
```

### 2. Add API Tokens and Webhooks

```bash
# Cloudflare API token (if using DNS challenge)
echo "your-cloudflare-token" | podman secret create cloudflare-api-token -

# Discord webhook for Minecraft alerts
echo "https://discord.com/api/webhooks/..." | podman secret create minecraft-discord-webhook -

# Discord User ID (for @mentions)
echo "your-discord-user-id" | podman secret create discord-user-id -
```

### 3. Restic Backup Secrets

```bash
# Restic repository password (generates strong random password)
openssl rand -base64 32 | podman secret create restic-repository-password -

# Restic Discord webhook (can reuse minecraft webhook or create separate)
echo "https://discord.com/api/webhooks/..." | podman secret create restic-discord-webhook -

# SSH private key for NAS access (if using SFTP)
# First, generate an SSH key pair:
#   ssh-keygen -t ed25519 -f ~/.ssh/restic_nas_key -C "restic-backup"
# Then add the public key to your NAS's authorized_keys
podman secret create restic-ssh-key ~/.ssh/restic_nas_key
```

### 4. Tailscale Auth Key

```bash
# Get from https://login.tailscale.com/admin/settings/keys
# Choose "Reusable" and set expiration
echo "tskey-auth-..." | podman secret create tailscale-auth-key -
```

## Verification

After creating secrets, verify they exist:

```bash
podman secret ls
```

You should see all the secrets listed (but not their values).

## Inspecting Secrets

To view metadata (NOT the actual secret value):

```bash
podman secret inspect authelia-jwt-secret
```

## Removing Secrets

If you need to recreate a secret:

```bash
podman secret rm secret-name
# Then create it again with the new value
```

## Security Notes

- Secrets are encrypted at rest by Podman
- Secrets are mounted as read-only files in containers
- Secrets are ephemeral and not part of container images
- Never commit actual secret values to git
- Keep a secure backup of secret values in a password manager

## Generating Authelia Password Hash

For creating users in Authelia's `users_database.yml`:

```bash
podman run --rm authelia/authelia:latest \
  authelia crypto hash generate argon2 --password 'YourPassword'
```

This will output a hash like `$argon2id$v=19$m=65536...` which you can use in the users database file.
