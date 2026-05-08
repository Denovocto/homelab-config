# Secrets Setup Guide

This guide walks you through setting up all required secrets for the homelab.

## Overview

Secrets are managed using Podman's built-in secret management system. Secrets are:
- Encrypted at rest
- Mounted as read-only files or injected as environment variables into containers
- Never stored in container images
- Never committed to git

## Prerequisites

- Podman installed
- Access to the homelab server

## Required Secrets

### Phase 1 (Critical Services)

These secrets are required for the core services to function:

#### 1. Authelia Secrets

```bash
# Generate JWT secret (32 bytes hex)
openssl rand -hex 32 | podman secret create authelia-jwt-secret -

# Generate session secret (32 bytes hex)
openssl rand -hex 32 | podman secret create authelia-session-secret -

# Generate storage encryption key (32 bytes hex)
openssl rand -hex 32 | podman secret create authelia-storage-key -
```

#### 2. Grafana Admin Password

```bash
# Choose a strong password
echo "your-secure-password-here" | podman secret create grafana-admin-password -
```

#### 3. Minecraft Discord Webhook (Optional)

If you want server notifications in Discord:

```bash
# Get webhook URL from Discord:
# Server Settings → Integrations → Webhooks → New Webhook
echo "https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN" | podman secret create minecraft-discord-webhook -
```

#### 4. Cloudflare API Token (Optional)

Only needed if using Cloudflare DNS challenge for HTTPS certificates:

```bash
# Get API token from Cloudflare dashboard:
# My Profile → API Tokens → Create Token
# Template: "Edit zone DNS"
echo "your-cloudflare-api-token" | podman secret create cloudflare-api-token -
```

### Phase 2 (Optional Services)

Additional secrets for secondary services can be added as needed.

## Creating Authelia Users

Authelia requires password hashes for user authentication. Here's how to create them:

### 1. Generate Password Hash

```bash
podman run --rm authelia/authelia:latest \
  authelia crypto hash generate argon2 --password 'YourPasswordHere'
```

This will output something like:
```
$argon2id$v=19$m=65536,t=3,p=4$...
```

### 2. Create Users Database

Copy the template:
```bash
cp configs/authelia/users_database.yml.template configs/authelia/users_database.yml
```

Edit `configs/authelia/users_database.yml` and replace the password hashes:

```yaml
---
users:
  admin:
    displayname: "Admin User"
    password: "$argon2id$v=19$m=65536,t=3,p=4$..."  # Your hash here
    email: admin@yourdomain.com
    groups:
      - admins

  friend1:
    displayname: "Friend Name"
    password: "$argon2id$v=19$m=65536,t=3,p=4$..."  # Their hash here
    email: friend@example.com
    groups:
      - users
```

**Important:** Do NOT commit `users_database.yml` to git. It's already in `.gitignore`.

## Verifying Secrets

After creating secrets, verify they exist:

```bash
podman secret ls
```

You should see output like:
```
ID                         NAME                         DRIVER      CREATED        UPDATED
abc123...                  authelia-jwt-secret          file        2 minutes ago  2 minutes ago
def456...                  authelia-session-secret      file        2 minutes ago  2 minutes ago
ghi789...                  authelia-storage-key         file        2 minutes ago  2 minutes ago
jkl012...                  grafana-admin-password       file        1 minute ago   1 minute ago
```

## Inspecting Secrets

To view metadata (NOT the actual secret value):

```bash
podman secret inspect authelia-jwt-secret
```

## Updating Secrets

If you need to change a secret:

```bash
# Remove the old secret
podman secret rm secret-name

# Create with new value
echo "new-value" | podman secret create secret-name -

# Restart affected services
systemctl --user restart service-name.service
```

## Backup and Recovery

**IMPORTANT:** Podman secrets are stored locally. If you lose the server, you lose the secrets.

### Backup Strategy

1. Store secret values in a password manager (1Password, Bitwarden, etc.)
2. Or export secrets to an encrypted archive:

```bash
# Create encrypted backup
mkdir -p ~/secrets-backup
podman secret ls --format "{{.Name}}" | while read secret; do
    echo "Backing up: $secret"
    # Note: This requires manual intervention to retrieve values
done

# Encrypt the backup directory
tar czf - ~/secrets-backup | gpg --symmetric --cipher-algo AES256 > secrets-backup.tar.gz.gpg

# Store the encrypted file safely (external drive, cloud storage, etc.)
```

3. Restore from backup when needed

### Recovery Process

After server rebuild:

1. Restore from password manager or encrypted backup
2. Recreate secrets using the commands in this guide
3. Verify with `podman secret ls`
4. Start services

## Troubleshooting

### Secret not found error

If a container fails to start with "secret not found":

```bash
# Check if secret exists
podman secret ls | grep secret-name

# If missing, create it
echo "value" | podman secret create secret-name -

# Restart the service
systemctl --user restart service-name.service
```

### Permission denied

Secrets are user-specific. Make sure you're creating them as the same user that runs the containers:

```bash
# Check current user
whoami

# Ensure you're creating secrets as the correct user
podman secret ls
```

## Security Best Practices

1. **Never commit secrets to git** - They're in `.gitignore`, but double-check
2. **Use strong, random values** - Use `openssl rand` or password generators
3. **Rotate secrets periodically** - Especially after team member changes
4. **Limit secret access** - Only create secrets on the homelab server
5. **Monitor secret usage** - Check logs for unauthorized access attempts
6. **Backup encrypted** - Always encrypt secret backups
7. **Use 2FA** - Enable two-factor authentication in Authelia

## Next Steps

After setting up secrets:

1. Verify all secrets are created: `podman secret ls`
2. Create Authelia users database
3. Update Caddyfile with your domain
4. Deploy services: `./scripts/bootstrap.sh`

See [IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md) for the full deployment process.
