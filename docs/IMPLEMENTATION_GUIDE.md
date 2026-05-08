# Homelab GitOps Architecture - Fresh Start

**Last Updated:** 2026-05-02
**System:** 6-core, 16GB RAM, 512GB Storage
**Approach:** GitOps, Podman Quadlets, Podman Secrets, Zero Bash Scripts

---

## Table of Contents

1. [Architecture Philosophy](#architecture-philosophy)
2. [Network Architecture](#network-architecture)
3. [Priority Services (Phase 1)](#priority-services-phase-1)
4. [Secondary Services (Phase 2)](#secondary-services-phase-2)
5. [GitOps Repository Structure](#gitops-repository-structure)
6. [Secrets Management](#secrets-management)
7. [Authentication Flow](#authentication-flow)
8. [Minecraft Architecture](#minecraft-architecture)
9. [Implementation Roadmap](#implementation-roadmap)
10. [Complete Quadlet Examples](#complete-quadlet-examples)

---

## Architecture Philosophy

### Core Principles

1. **GitOps:** Everything version controlled, declarative
   - All Quadlet files in git
   - All config files in git (with secrets redacted)
   - Infrastructure as code
   - Reproducible from scratch

2. **Zero Bash Scripts:** Use native tooling
   - ❌ No bash scripts for container orchestration
   - ✅ Quadlets for services
   - ✅ Systemd timers for scheduled tasks
   - ✅ Podman secrets for sensitive data

3. **Secrets Management:**
   - ❌ No plaintext environment variables
   - ❌ No `.env` files
   - ✅ Podman secrets (encrypted, ephemeral in containers)
   - ✅ Secrets never committed to git

4. **Fresh Start:**
   - ❌ No migration from existing setup
   - ✅ Build from scratch
   - ✅ Clean, modern architecture

5. **Security Layers:**
   - Public services behind Authelia SSO
   - Admin interfaces (Cockpit) via Tailscale only
   - Podman rootless
   - Firewall hardening
   - No unnecessary public exposure

---

## Network Architecture

### Dual-Network Design

```
┌─────────────────────────────────────────────────────────────┐
│                        INTERNET                              │
└───────────────┬─────────────────────────┬───────────────────┘
                │                         │
                │                         │
        ┌───────▼────────┐        ┌──────▼──────────┐
        │ Your Domain    │        │ Tailscale       │
        │ (Public DNS)   │        │ (VPN Only)      │
        └───────┬────────┘        └──────┬──────────┘
                │                         │
                │                         │
        ┌───────▼────────┐        ┌──────▼──────────┐
        │ Firewall       │        │ Tailscale Daemon│
        │ Port 80/443    │        │ (Admin Only)    │
        │ Port 25565     │        └──────┬──────────┘
        └───────┬────────┘                │
                │                         │
        ┌───────▼──────────────────────────▼──────────┐
        │         Podman Host (Fedora Server)         │
        │                                              │
        │  ┌─────────────────────────────────────┐    │
        │  │   Podman Network: homelab           │    │
        │  │                                      │    │
        │  │   ┌──────────────────────────┐      │    │
        │  │   │   Caddy (Reverse Proxy)  │      │    │
        │  │   │   :80, :443              │      │    │
        │  │   └────────┬─────────────────┘      │    │
        │  │            │                         │    │
        │  │   ┌────────▼─────────────────┐      │    │
        │  │   │   Authelia (SSO)         │      │    │
        │  │   │   :9091                  │      │    │
        │  │   └────────┬─────────────────┘      │    │
        │  │            │                         │    │
        │  │   ┌────────▼────────┬───────────┐   │    │
        │  │   │                 │           │   │    │
        │  │   │  Minecraft      │  Web Apps │   │    │
        │  │   │  :25565         │           │   │    │
        │  │   └─────────────────┴───────────┘   │    │
        │  └─────────────────────────────────────┘    │
        │                                              │
        │  Cockpit :9090 (Tailscale Only)             │
        └──────────────────────────────────────────────┘
```

### Access Patterns

#### Public Users (Web Apps)
```
User → https://app.yourdomain.com
  → Caddy (HTTPS termination)
  → Authelia (SSO login)
  → Application
```

#### Public Users (Minecraft)
```
User → mc.yourdomain.com:25565
  → Firewall (port forward)
  → Minecraft container
```

#### Admin (You)
```
You → Tailscale VPN
  → https://homelab:9090 (Cockpit)
  → Manage all containers
```

### Network Components

| Component | Purpose | Access |
|-----------|---------|--------|
| **Caddy** | Reverse proxy, HTTPS, routing | Public :80/:443 |
| **Authelia** | SSO, 2FA, session management | Internal (via Caddy) |
| **Minecraft** | Game server | Public :25565 |
| **Tailscale** | Admin VPN access | Private VPN |
| **Cockpit** | Web management UI | Tailscale only |

### Firewall Rules

```bash
# Public services
sudo firewall-cmd --permanent --add-port=80/tcp      # HTTP (redirects to HTTPS)
sudo firewall-cmd --permanent --add-port=443/tcp     # HTTPS (Caddy)
sudo firewall-cmd --permanent --add-port=25565/tcp   # Minecraft

# Tailscale (automatic, no manual rules needed)
# Cockpit accessible via Tailscale IP only

sudo firewall-cmd --reload
```

**Note:** Cockpit port 9090 NOT opened publicly. Access via `http://100.x.x.x:9090` (Tailscale IP).

---

## Priority Services (Phase 1)

**Focus:** Authentication, Networking, Minecraft

### Service Stack

| Service | Purpose | Priority | RAM | Storage |
|---------|---------|----------|-----|---------|
| **Tailscale** | Admin VPN | 🔴 Critical | 20MB | 50MB |
| **Caddy** | Reverse proxy | 🔴 Critical | 30MB | 100MB |
| **Authelia** | SSO/2FA | 🔴 Critical | 100MB | 100MB |
| **Minecraft** | Pixelmon server | 🔴 Critical | 4GB | 10GB |
| **Cockpit** | Management UI | ⚠️ Important | 50MB | 200MB |
| **Total Phase 1** | | | **~4.2GB** | **~10.5GB** |

### Implementation Order

1. ✅ **Tailscale** - Secure admin access first
2. ✅ **Cockpit** - Verify it's running, configure for Tailscale-only access
3. ✅ **Podman Secrets** - Set up secrets infrastructure
4. ✅ **Caddy** - Reverse proxy with auto-HTTPS
5. ✅ **Authelia** - SSO before deploying apps
6. ✅ **Minecraft** - Main service

---

## Secondary Services (Phase 2)

**Focus:** Monitoring, Dashboards, Productivity

### Service Stack

| Service | Purpose | RAM | Storage |
|---------|---------|-----|---------|
| **Prometheus** | Metrics collection | 200MB | 5GB |
| **Grafana** | Dashboards | 200MB | 1GB |
| **Uptime Kuma** | Service monitoring | 50MB | 1GB |
| **Homarr** | Service dashboard | 50MB | 200MB |
| **Affine** | Productivity | 300MB | 2GB |
| **Total Phase 2** | | **~800MB** | **~9GB** |

**Deploy after Phase 1 is stable and tested.**

---

## GitOps Repository Structure

### Directory Layout

```
homelab/
├── README.md
├── .gitignore                    # Ignore secrets, temp files
├── docs/
│   ├── ARCHITECTURE.md
│   ├── SECRETS_SETUP.md
│   └── TROUBLESHOOTING.md
│
├── quadlets/
│   ├── networks/
│   │   └── homelab.network
│   │
│   ├── volumes/
│   │   ├── minecraft-data.volume
│   │   ├── prometheus-data.volume
│   │   ├── grafana-data.volume
│   │   └── ...
│   │
│   └── containers/
│       ├── phase1-critical/
│       │   ├── tailscale.container
│       │   ├── caddy.container
│       │   ├── authelia.container
│       │   └── minecraft.container
│       │
│       └── phase2-services/
│           ├── prometheus.container
│           ├── grafana.container
│           ├── uptime-kuma.container
│           ├── homarr.container
│           └── affine.container
│
├── configs/
│   ├── caddy/
│   │   └── Caddyfile
│   │
│   ├── authelia/
│   │   ├── configuration.yml      # Secrets referenced via Podman secrets
│   │   └── users_database.yml.template
│   │
│   ├── prometheus/
│   │   └── prometheus.yml
│   │
│   └── minecraft/
│       └── server.properties
│
├── secrets/
│   ├── .gitignore                # Ignore all files here
│   ├── README.md                 # Instructions for secret creation
│   └── secrets.env.template      # Template showing required secrets
│
├── scripts/
│   ├── bootstrap.sh              # Initial setup script
│   ├── deploy.sh                 # Deploy Quadlets from git
│   └── restic-backup.sh          # Restic backup automation
│
└── backups/
    └── .gitignore                # Don't commit backups to git
```

### .gitignore

```gitignore
# Secrets
secrets/*.env
secrets/*.txt
secrets/*.key
secrets/*.pem
configs/authelia/users_database.yml

# Backups
backups/

# Local overrides
*.local

# Temporary files
*.tmp
*.log
```

### What Goes in Git

✅ **DO commit:**
- All Quadlet `.container`, `.network`, `.volume` files
- Config files with secret placeholders (e.g., `${DISCORD_WEBHOOK}`)
- Templates
- Documentation
- Bootstrap/deployment scripts

❌ **DO NOT commit:**
- Actual secrets (API keys, passwords, tokens)
- Backup archives
- User data
- Container volumes

---

## Secrets Management

### Podman Secrets Overview

Podman secrets are:
- Encrypted at rest
- Mounted as read-only files in containers
- Ephemeral (not part of container image)
- Managed separately from Quadlet files

### Secret Creation Workflow

```bash
# Create secret from stdin
echo "my-secret-value" | podman secret create secret-name -

# Create secret from file
podman secret create secret-name /path/to/secret.txt

# List secrets
podman secret ls

# Inspect secret (shows metadata, not value)
podman secret inspect secret-name

# Remove secret
podman secret rm secret-name
```

### Required Secrets

#### Phase 1 Secrets

```bash
# Authelia
podman secret create authelia-jwt-secret -
podman secret create authelia-session-secret -
podman secret create authelia-storage-key -

# Caddy (if using Cloudflare DNS challenge)
podman secret create cloudflare-api-token -

# Minecraft (if using Discord webhooks)
podman secret create minecraft-discord-webhook -

# Tailscale
podman secret create tailscale-auth-key -
```

#### Secret Generation

```bash
# Generate random secrets (32 bytes, hex)
openssl rand -hex 32

# Generate random secrets (64 bytes, base64)
openssl rand -base64 64

# Generate Authelia password hash
podman run --rm authelia/authelia:latest \
  authelia crypto hash generate argon2 --password 'YourPassword'
```

### Using Secrets in Quadlets

```ini
# Example: Authelia container
[Container]
Image=authelia/authelia:latest
Secret=authelia-jwt-secret,type=env,target=AUTHELIA_JWT_SECRET
Secret=authelia-session-secret,type=env,target=AUTHELIA_SESSION_SECRET
Secret=authelia-storage-key,type=env,target=AUTHELIA_STORAGE_ENCRYPTION_KEY

# Alternative: Mount as file
Secret=authelia-jwt-secret,type=mount,target=/run/secrets/jwt_secret
```

### Secrets Documentation File

```bash
# secrets/README.md
# Homelab Secrets Setup

## Required Secrets

### Authelia
- authelia-jwt-secret: JWT signing key (64 char random)
- authelia-session-secret: Session encryption (64 char random)
- authelia-storage-key: Database encryption (64 char random)

### Caddy
- cloudflare-api-token: Cloudflare API token (if using DNS challenge)

### Minecraft
- minecraft-discord-webhook: Discord webhook URL for alerts

### Tailscale
- tailscale-auth-key: Tailscale auth key (one-time or reusable)

## Creating Secrets

1. Generate random values:
   openssl rand -hex 32 | podman secret create authelia-jwt-secret -
   openssl rand -hex 32 | podman secret create authelia-session-secret -
   openssl rand -hex 32 | podman secret create authelia-storage-key -

2. Add API tokens:
   echo "your-cloudflare-token" | podman secret create cloudflare-api-token -
   echo "https://discord.com/api/webhooks/..." | podman secret create minecraft-discord-webhook -

3. Tailscale auth key (get from https://login.tailscale.com/admin/settings/keys):
   echo "tskey-auth-..." | podman secret create tailscale-auth-key -

## Verification

podman secret ls
```

---

## Authentication Flow

### Authelia Architecture

```
User → https://app.yourdomain.com
  ↓
Caddy checks authentication header
  ↓
No valid session? → Redirect to https://auth.yourdomain.com
  ↓
User logs in (username/password + 2FA)
  ↓
Authelia sets session cookie
  ↓
Redirect back to https://app.yourdomain.com
  ↓
Caddy validates session with Authelia
  ↓
Access granted → App
```

### Authelia Configuration (GitOps-Friendly)

```yaml
# configs/authelia/configuration.yml
---
server:
  address: 'tcp://0.0.0.0:9091'

log:
  level: 'info'
  format: 'text'

# JWT secret from Podman secret
jwt_secret: '${AUTHELIA_JWT_SECRET}'

# Default theme
theme: 'dark'

# Authentication backend
authentication_backend:
  file:
    path: '/config/users_database.yml'
  password_reset:
    disable: false

# Password policy
password_policy:
  standard:
    enabled: true
    min_length: 12
    require_uppercase: true
    require_lowercase: true
    require_number: true
    require_special: false

# Access control rules
access_control:
  default_policy: 'deny'

  rules:
    # Allow all authenticated users to access services
    - domain:
        - 'minecraft.yourdomain.com'
        - 'homarr.yourdomain.com'
        - 'grafana.yourdomain.com'
        - 'affine.yourdomain.com'
      policy: 'one_factor'  # Username + password

    # Require 2FA for admin services
    - domain:
        - 'prometheus.yourdomain.com'
      policy: 'two_factor'  # Username + password + TOTP

# Session configuration
session:
  secret: '${AUTHELIA_SESSION_SECRET}'
  name: 'authelia_session'
  domain: 'yourdomain.com'
  expiration: '1h'
  inactivity: '5m'

# Storage (encrypted SQLite)
storage:
  encryption_key: '${AUTHELIA_STORAGE_ENCRYPTION_KEY}'
  local:
    path: '/config/db.sqlite3'

# Notification (file-based for now, can add SMTP later)
notifier:
  filesystem:
    filename: '/config/notification.txt'

# TOTP (Google Authenticator, Authy, etc.)
totp:
  issuer: 'yourdomain.com'
  period: 30
  skew: 1
```

### Users Database Template

```yaml
# configs/authelia/users_database.yml.template
---
users:
  admin:
    displayname: "Admin User"
    password: "$argon2id$..."  # Generate with authelia crypto hash
    email: admin@yourdomain.com
    groups:
      - admins

  friend1:
    displayname: "Friend Name"
    password: "$argon2id$..."
    email: friend@example.com
    groups:
      - users

# To generate password hash:
# podman run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password 'YourPassword'
```

**Note:** Do NOT commit actual `users_database.yml` to git. Treat as secret.

### Caddy Configuration

```caddyfile
# configs/caddy/Caddyfile

{
    email your@email.com
    admin off
}

# Authelia SSO endpoint
auth.yourdomain.com {
    reverse_proxy authelia:9091
}

# Protected app example: Homarr
homarr.yourdomain.com {
    # Forward auth to Authelia
    forward_auth authelia:9091 {
        uri /api/verify?rd=https://auth.yourdomain.com
        copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
    }

    reverse_proxy homarr:7575
}

# Grafana (requires 2FA, configured in Authelia rules)
grafana.yourdomain.com {
    forward_auth authelia:9091 {
        uri /api/verify?rd=https://auth.yourdomain.com
        copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
    }

    reverse_proxy grafana:3000
}

# Minecraft status page (public, no auth)
minecraft.yourdomain.com {
    # Could serve a static status page
    respond "Minecraft server: mc.yourdomain.com:25565"
}
```

### User Onboarding Flow

1. **Admin creates user:**
   - Generate password hash
   - Add to `users_database.yml`
   - Restart Authelia: `systemctl --user restart authelia.service`

2. **User first access:**
   - Visit `https://homarr.yourdomain.com`
   - Redirected to `https://auth.yourdomain.com`
   - Login with username/password
   - (Optional) Set up 2FA TOTP

3. **Subsequent access:**
   - Session cookie valid for 1 hour
   - Auto-login to all services
   - No repeated logins needed

---

## Minecraft Architecture

### No PlayIt.gg Needed

**Traditional Port Forwarding** (recommended):
```
Internet → Your Public IP:25565 → Router Port Forward → Server:25565 → Minecraft Container
```

**Setup:**
1. Configure router to forward TCP port 25565 to your server's LAN IP
2. Set DNS A record: `mc.yourdomain.com` → Your public IP
3. Users connect to: `mc.yourdomain.com:25565`

**Advantages:**
- ✅ Professional, standard approach
- ✅ Low latency, direct connection
- ✅ No third-party dependencies
- ✅ Free

**Disadvantages:**
- ⚠️ Exposes public IP
- ⚠️ Requires router access
- ⚠️ Vulnerable to DDoS (mitigate with whitelist, rate limiting)

### Alternative: Cloudflare Spectrum

If you want DDoS protection and don't want to expose IP:

**Cloudflare Spectrum** ($5/month on Pro plan):
```
Internet → Cloudflare Spectrum → Your Server:25565 → Minecraft Container
```

Setup via Cloudflare dashboard, provides DDoS protection for TCP/UDP traffic.

### Minecraft Quadlet (Declarative, No Scripts)

```ini
# quadlets/containers/phase1-critical/minecraft.container
[Unit]
Description=Minecraft Pixelmon Server
After=network-online.target homelab-network.service

[Container]
Image=docker.io/itzg/minecraft-server:java11
ContainerName=minecraft-papa
AutoUpdate=registry

# Network
Network=homelab.network
PublishPort=25565:25565
PublishPort=19565:19565

# Volumes
Volume=minecraft-data.volume:/data:Z

# Environment - Base Config
Environment=EULA=TRUE
Environment=TYPE=FORGE
Environment=VERSION=1.16.5
Environment=MEMORY=4G
Environment=INIT_MEMORY=2G
Environment=FORGE_VERSION=36.2.39
Environment=ENABLE_ROLLING_LOGS=true

# Minecraft Operator
Environment=OPS=YourMinecraftUsername

# Prometheus Exporter (for Prometheus integration)
Environment=ENABLE_METRICS=true
Environment=METRICS_PORT=19565

# Discord Webhook (via Podman secret)
Secret=minecraft-discord-webhook,type=env,target=DISCORD_WEBHOOK

# Resource Limits
MemoryMax=5G
MemoryHigh=4.5G

[Service]
Restart=always
TimeoutStartSec=600

[Install]
WantedBy=default.target
```

### Discord Integration (No Bash Scripts)

**Option 1:** Use Minecraft mod (DiscordSRV)
- Install DiscordSRV mod in Minecraft
- Configure via mod config files (version controlled)
- Webhook URL from Podman secret

**Option 2:** Systemd OnSuccess/OnFailure (for service alerts only)

```ini
# minecraft.container
[Service]
Restart=always
OnSuccess=/usr/bin/systemd-cat -t minecraft echo "Minecraft started successfully"
OnFailure=/usr/bin/systemd-cat -t minecraft echo "Minecraft failed to start"
```

Then use journald → webhook forwarder (systemd-journal-upload or Grafana Loki).

**Recommendation:** Use DiscordSRV mod for in-game events, systemd for service monitoring.

### Backups (Systemd Timer, No Bash)

Actually, you DO need a small script for backup logic. But we can make it minimal:

```ini
# ~/.config/systemd/user/backup-minecraft.service
[Unit]
Description=Backup Minecraft World

[Service]
Type=oneshot
ExecStart=podman volume export systemd-minecraft-data -o /tmp/minecraft-backup-%Y%m%d.tar
ExecStart=rsync -avz /tmp/minecraft-backup-*.tar user@nas:/backups/minecraft/
StandardOutput=journal
StandardError=journal
```

```ini
# ~/.config/systemd/user/backup-minecraft.timer
[Unit]
Description=Backup Minecraft Every 2 Hours

[Timer]
OnBootSec=5min
OnUnitActiveSec=2h
Persistent=true

[Install]
WantedBy=timers.target
```

**Pure systemd, no bash script.**

---

## Implementation Roadmap

### Phase 1: Core Infrastructure (Priority)

#### Step 1.1: Tailscale Setup (30 min)

**Goal:** Secure admin access

**Tasks:**
1. Install Tailscale on server:
   ```bash
   sudo dnf install -y tailscale
   sudo systemctl enable --now tailscaled
   sudo tailscale up --accept-routes
   ```

2. Get Tailscale IP:
   ```bash
   tailscale ip -4
   # Example: 100.123.45.67
   ```

3. Test access from your device:
   - Install Tailscale on your laptop/phone
   - Join same tailnet
   - Ping server: `ping 100.123.45.67`

**Validation:**
- ✅ Can ping server via Tailscale IP
- ✅ Can SSH via Tailscale IP

---

#### Step 1.2: Cockpit Configuration (15 min)

**Goal:** Verify Cockpit, restrict to Tailscale only

**Tasks:**
1. Check if Cockpit is running:
   ```bash
   sudo systemctl status cockpit.socket
   ```

2. If not running:
   ```bash
   sudo systemctl enable --now cockpit.socket
   ```

3. Configure firewall (Tailscale only):
   ```bash
   # Remove Cockpit from public zone if present
   sudo firewall-cmd --permanent --zone=public --remove-service=cockpit

   # Add Tailscale interface to trusted zone
   sudo firewall-cmd --permanent --zone=trusted --add-source=100.64.0.0/10
   sudo firewall-cmd --permanent --zone=trusted --add-service=cockpit

   sudo firewall-cmd --reload
   ```

4. Access Cockpit:
   - From Tailscale device: `http://100.123.45.67:9090`
   - Login with your server user account

**Validation:**
- ✅ Cockpit accessible via Tailscale IP
- ✅ Cockpit NOT accessible via public IP
- ✅ Can see Podman containers in Cockpit

---

#### Step 1.3: Git Repository Setup (30 min)

**Goal:** Create GitOps repo

**Tasks:**
1. Create repository:
   ```bash
   cd ~/Documents/projects
   mkdir homelab
   cd homelab
   git init
   ```

2. Create directory structure (see [GitOps Repository Structure](#gitops-repository-structure))

3. Create `.gitignore`:
   ```bash
   cat > .gitignore <<'EOF'
   secrets/*.env
   secrets/*.txt
   secrets/*.key
   configs/authelia/users_database.yml
   backups/
   *.local
   EOF
   ```

4. Initial commit:
   ```bash
   git add .
   git commit -m "Initial homelab structure"
   ```

5. (Optional) Push to remote:
   ```bash
   # GitHub, GitLab, Gitea, etc.
   git remote add origin <your-repo-url>
   git push -u origin main
   ```

**Validation:**
- ✅ Directory structure matches plan
- ✅ `.gitignore` in place
- ✅ Initial commit created

---

#### Step 1.4: Podman Secrets Setup (30 min)

**Goal:** Create all required secrets

**Tasks:**
1. Generate secrets:
   ```bash
   # Authelia
   openssl rand -hex 32 | podman secret create authelia-jwt-secret -
   openssl rand -hex 32 | podman secret create authelia-session-secret -
   openssl rand -hex 32 | podman secret create authelia-storage-key -

   # Cloudflare (if using DNS challenge)
   echo "your-cloudflare-api-token" | podman secret create cloudflare-api-token -

   # Discord webhook
   echo "https://discord.com/api/webhooks/..." | podman secret create minecraft-discord-webhook -
   ```

2. Verify:
   ```bash
   podman secret ls
   ```

3. Document in `secrets/README.md` (already in git repo)

**Validation:**
- ✅ All secrets created
- ✅ `podman secret ls` shows secrets
- ✅ No secrets committed to git

---

#### Step 1.5: Network & Volumes Setup (15 min)

**Goal:** Create Podman network and volumes

**Tasks:**
1. Create Quadlet files:
   ```bash
   mkdir -p ~/.config/containers/systemd/{networks,volumes,containers}
   ```

2. Create network Quadlet:
   ```bash
   cat > ~/.config/containers/systemd/networks/homelab.network <<'EOF'
   [Network]
   NetworkName=homelab
   Driver=bridge

   [Install]
   WantedBy=default.target
   EOF
   ```

3. Reload systemd:
   ```bash
   systemctl --user daemon-reload
   systemctl --user start homelab-network.service
   ```

4. Verify:
   ```bash
   podman network ls
   # Should see 'homelab' network
   ```

**Validation:**
- ✅ Network visible in `podman network ls`
- ✅ Network visible in Cockpit

---

#### Step 1.6: Deploy Caddy (30 min)

**Goal:** Reverse proxy with auto-HTTPS

**Tasks:**
1. Create Caddyfile in git repo:
   ```bash
   mkdir -p ~/Documents/projects/homelab/configs/caddy
   # See Caddyfile example in Authentication Flow section
   ```

2. Create Caddy Quadlet:
   ```bash
   # See Complete Quadlet Examples section
   ```

3. Copy Quadlet to systemd:
   ```bash
   cp ~/Documents/projects/homelab/quadlets/containers/phase1-critical/caddy.container \
      ~/.config/containers/systemd/containers/
   ```

4. Deploy:
   ```bash
   systemctl --user daemon-reload
   systemctl --user enable --now caddy.service
   ```

5. Check logs:
   ```bash
   journalctl --user -u caddy.service -f
   ```

6. Test:
   ```bash
   curl https://yourdomain.com
   # Should see 404 or redirect (normal, no routes yet)
   ```

**Validation:**
- ✅ Caddy running in Cockpit
- ✅ HTTPS certificate obtained automatically
- ✅ Domain resolves to your server

---

#### Step 1.7: Deploy Authelia (45 min)

**Goal:** SSO authentication

**Tasks:**
1. Create Authelia config in git repo (see Authentication Flow section)

2. Create users database:
   ```bash
   # Generate password hash
   podman run --rm authelia/authelia:latest \
     authelia crypto hash generate argon2 --password 'YourPassword'

   # Create users_database.yml (NOT in git)
   # See template in Authentication Flow section
   ```

3. Create Authelia Quadlet (see Complete Quadlet Examples)

4. Copy to systemd and deploy:
   ```bash
   cp ~/Documents/projects/homelab/quadlets/containers/phase1-critical/authelia.container \
      ~/.config/containers/systemd/containers/

   systemctl --user daemon-reload
   systemctl --user enable --now authelia.service
   ```

5. Update Caddyfile to include auth.yourdomain.com

6. Reload Caddy:
   ```bash
   systemctl --user restart caddy.service
   ```

7. Test:
   - Visit `https://auth.yourdomain.com`
   - Should see Authelia login page

**Validation:**
- ✅ Authelia accessible at `https://auth.yourdomain.com`
- ✅ Can login with test user
- ✅ 2FA setup works (optional for testing)

---

#### Step 1.8: Deploy Minecraft (1 hour)

**Goal:** Game server with public access

**Tasks:**
1. Configure router port forwarding:
   - Forward TCP 25565 to server LAN IP

2. Configure DNS:
   - A record: `mc.yourdomain.com` → Your public IP

3. Configure firewall:
   ```bash
   sudo firewall-cmd --permanent --add-port=25565/tcp
   sudo firewall-cmd --reload
   ```

4. Create Minecraft Quadlet (see Complete Quadlet Examples)

5. Deploy:
   ```bash
   cp ~/Documents/projects/homelab/quadlets/containers/phase1-critical/minecraft.container \
      ~/.config/containers/systemd/containers/

   systemctl --user daemon-reload
   systemctl --user enable --now minecraft.service
   ```

6. Monitor startup (takes 2-5 minutes):
   ```bash
   journalctl --user -u minecraft.service -f
   ```

7. Test connection:
   - Minecraft client → `mc.yourdomain.com:25565`

**Validation:**
- ✅ Minecraft server running
- ✅ Can connect from external network
- ✅ Prometheus metrics accessible at `:19565/metrics`

---

### Phase 2: Secondary Services (Deploy After Phase 1 Stable)

#### Prometheus, Grafana, Uptime Kuma, Homarr, Affine

**Follow same pattern:**
1. Create Quadlet in git repo
2. Copy to `~/.config/containers/systemd/containers/`
3. Add route to Caddyfile
4. Reload systemd and Caddy
5. Test access via `https://service.yourdomain.com`

---

## Complete Quadlet Examples

### Tailscale (Optional Container Approach)

If you want Tailscale as container instead of host daemon:

```ini
# quadlets/containers/phase1-critical/tailscale.container
[Unit]
Description=Tailscale VPN
After=network-online.target

[Container]
Image=tailscale/tailscale:latest
ContainerName=tailscale
AutoUpdate=registry

Network=host
CapAdd=NET_ADMIN
CapAdd=NET_RAW

Volume=tailscale-state.volume:/var/lib/tailscale:Z

Secret=tailscale-auth-key,type=env,target=TS_AUTHKEY
Environment=TS_HOSTNAME=homelab
Environment=TS_STATE_DIR=/var/lib/tailscale

[Service]
Restart=always

[Install]
WantedBy=default.target
```

**Recommendation:** Use host Tailscale daemon (simpler).

---

### Caddy

```ini
# quadlets/containers/phase1-critical/caddy.container
[Unit]
Description=Caddy Reverse Proxy
After=network-online.target homelab-network.service

[Container]
Image=docker.io/library/caddy:latest
ContainerName=caddy
AutoUpdate=registry

Network=homelab.network
PublishPort=80:80
PublishPort=443:443
PublishPort=443:443/udp
PublishPort=2019:2019

Volume=%h/Documents/projects/homelab/configs/caddy/Caddyfile:/etc/caddy/Caddyfile:Z,ro
Volume=caddy-data.volume:/data:Z
Volume=caddy-config.volume:/config:Z

# Optional: Cloudflare API token for DNS challenge
Secret=cloudflare-api-token,type=env,target=CLOUDFLARE_API_TOKEN

[Service]
Restart=always

[Install]
WantedBy=default.target
```

---

### Authelia

```ini
# quadlets/containers/phase1-critical/authelia.container
[Unit]
Description=Authelia SSO
After=network-online.target homelab-network.service

[Container]
Image=docker.io/authelia/authelia:latest
ContainerName=authelia
AutoUpdate=registry

Network=homelab.network
PublishPort=9091:9091

# Config directory (contains configuration.yml and users_database.yml)
Volume=%h/Documents/projects/homelab/configs/authelia:/config:Z

# Secrets (injected as environment variables)
Secret=authelia-jwt-secret,type=env,target=AUTHELIA_JWT_SECRET
Secret=authelia-session-secret,type=env,target=AUTHELIA_SESSION_SECRET
Secret=authelia-storage-key,type=env,target=AUTHELIA_STORAGE_ENCRYPTION_KEY

Environment=TZ=America/New_York

[Service]
Restart=always

[Install]
WantedBy=default.target
```

---

### Minecraft

```ini
# quadlets/containers/phase1-critical/minecraft.container
[Unit]
Description=Minecraft Pixelmon Server
After=network-online.target homelab-network.service

[Container]
Image=docker.io/itzg/minecraft-server:java11
ContainerName=minecraft-papa
AutoUpdate=registry

Network=homelab.network
PublishPort=25565:25565
PublishPort=19565:19565

Volume=minecraft-data.volume:/data:Z

# Base configuration
Environment=EULA=TRUE
Environment=TYPE=FORGE
Environment=VERSION=1.16.5
Environment=MEMORY=4G
Environment=INIT_MEMORY=2G
Environment=FORGE_VERSION=36.2.39
Environment=ENABLE_ROLLING_LOGS=true

# Operators
Environment=OPS=YourMinecraftUsername

# Prometheus metrics
Environment=ENABLE_METRICS=true
Environment=METRICS_PORT=19565

# Discord webhook (via Podman secret)
Secret=minecraft-discord-webhook,type=env,target=DISCORD_WEBHOOK

# Resource limits
MemoryMax=5G
MemoryHigh=4.5G

[Service]
Restart=always
TimeoutStartSec=600

[Install]
WantedBy=default.target
```

---

### Prometheus

```ini
# quadlets/containers/phase2-services/prometheus.container
[Unit]
Description=Prometheus Metrics Collector
After=network-online.target homelab-network.service

[Container]
Image=docker.io/prom/prometheus:latest
ContainerName=prometheus
AutoUpdate=registry

Network=homelab.network
PublishPort=9090:9090

Volume=%h/Documents/projects/homelab/configs/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:Z,ro
Volume=prometheus-data.volume:/prometheus:Z

Environment=TZ=America/New_York

# Run as non-root (Prometheus user in image)
User=65534:65534

[Service]
Restart=always

[Install]
WantedBy=default.target
```

---

### Grafana

```ini
# quadlets/containers/phase2-services/grafana.container
[Unit]
Description=Grafana Dashboards
After=prometheus.service

[Container]
Image=docker.io/grafana/grafana:latest
ContainerName=grafana
AutoUpdate=registry

Network=homelab.network
PublishPort=3000:3000

Volume=grafana-data.volume:/var/lib/grafana:Z

Environment=GF_SERVER_ROOT_URL=https://grafana.yourdomain.com
Environment=GF_SECURITY_ADMIN_PASSWORD__FILE=/run/secrets/grafana_admin_password
Environment=GF_INSTALL_PLUGINS=

Secret=grafana-admin-password,type=mount,target=/run/secrets/grafana_admin_password

[Service]
Restart=always

[Install]
WantedBy=default.target
```

---

### Uptime Kuma

```ini
# quadlets/containers/phase2-services/uptime-kuma.container
[Unit]
Description=Uptime Kuma Monitoring
After=network-online.target homelab-network.service

[Container]
Image=docker.io/louislam/uptime-kuma:latest
ContainerName=uptime-kuma
AutoUpdate=registry

Network=homelab.network
PublishPort=3001:3001

Volume=uptime-kuma-data.volume:/app/data:Z

Environment=TZ=America/New_York

[Service]
Restart=always

[Install]
WantedBy=default.target
```

---

### Homarr

```ini
# quadlets/containers/phase2-services/homarr.container
[Unit]
Description=Homarr Dashboard
After=network-online.target homelab-network.service

[Container]
Image=ghcr.io/ajnart/homarr:latest
ContainerName=homarr
AutoUpdate=registry

Network=homelab.network
PublishPort=7575:7575

Volume=homarr-configs.volume:/app/data/configs:Z
Volume=homarr-icons.volume:/app/public/icons:Z
Volume=homarr-data.volume:/data:Z

# Optional: Podman socket for container status
Volume=/run/user/%U/podman/podman.sock:/var/run/docker.sock:Z,ro

[Service]
Restart=always

[Install]
WantedBy=default.target
```

**Note:** `%U` expands to your user ID at runtime.

---

### Affine

```ini
# quadlets/containers/phase2-services/affine.container
[Unit]
Description=Affine Productivity Suite
After=network-online.target homelab-network.service

[Container]
Image=ghcr.io/toeverything/affine:stable
ContainerName=affine
AutoUpdate=registry

Network=homelab.network
PublishPort=3010:3010

Volume=affine-data.volume:/root/.affine/storage:Z

Environment=NODE_ENV=production
Environment=AFFINE_SERVER_PORT=3010

[Service]
Restart=always

[Install]
WantedBy=default.target
```

---

## Deployment Script (Optional Automation)

```bash
#!/bin/bash
# scripts/deploy.sh
# Deploy Quadlets from git repo to systemd

set -e

REPO_DIR="$HOME/Documents/projects/homelab"
SYSTEMD_DIR="$HOME/.config/containers/systemd"

# Ensure systemd directory exists
mkdir -p "$SYSTEMD_DIR"/{networks,volumes,containers}

# Copy Quadlets
echo "Deploying Quadlets..."
rsync -av --delete "$REPO_DIR/quadlets/networks/" "$SYSTEMD_DIR/networks/"
rsync -av --delete "$REPO_DIR/quadlets/volumes/" "$SYSTEMD_DIR/volumes/"
rsync -av --delete "$REPO_DIR/quadlets/containers/" "$SYSTEMD_DIR/containers/"

# Reload systemd
echo "Reloading systemd..."
systemctl --user daemon-reload

echo "Deployment complete!"
echo "Start services with: systemctl --user start <service>.service"
```

**Usage:**
```bash
cd ~/Documents/projects/homelab
git pull  # Get latest changes
./scripts/deploy.sh
systemctl --user restart caddy.service  # Restart changed services
```

---

## Summary: Key Differences from Original Plan

### What Changed

| Aspect | Old Plan | New Plan |
|--------|----------|----------|
| **Migration** | Migrate from existing | Fresh start |
| **Secrets** | Environment variables | Podman secrets |
| **Orchestration** | Bash scripts + systemd | Quadlets only |
| **Version Control** | Some files in git | Everything in git (GitOps) |
| **Admin Access** | Public Cockpit or SSH tunnel | Tailscale VPN only |
| **User Access** | Public with auth | Public with Authelia SSO |
| **Minecraft Access** | PlayIt.gg tunnel | Port forwarding or Cloudflare |
| **Priority** | Deploy everything | Phase 1: Auth + Minecraft |

### What Stayed the Same

- ✅ Podman (rootless)
- ✅ Cockpit GUI
- ✅ Caddy + Authelia stack
- ✅ Service selection (Minecraft, Prometheus, Grafana, etc.)
- ✅ Discord integrations

---

## Next Steps

1. **Review this plan** - Ask questions about anything unclear
2. **Start Phase 1, Step 1.1** - Set up Tailscale
3. **Follow implementation roadmap** - One step at a time
4. **Test thoroughly** - Each service before moving to next
5. **Deploy Phase 2** - After Phase 1 is stable

**When ready to start, say:** "Let's begin Phase 1, Step 1.1"

---

**End of GitOps Homelab Plan**

*Last Updated: 2026-05-02*
