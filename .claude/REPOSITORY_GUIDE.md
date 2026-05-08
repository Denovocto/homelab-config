# Repository Guide for Claude

Quick reference for understanding and working with this homelab GitOps configuration.

## Quick Architecture Overview

**Technology Stack:**
- **Podman Quadlets** - Declarative container orchestration via systemd
- **Systemd** - Service management, auto-start, dependencies
- **GitOps** - All infrastructure as code, version controlled
- **Rootless Containers** - Security through non-root execution

**Key Services:**
- **Phase 1 (Critical):** Tailscale, Caddy, Authelia, Minecraft, Cockpit
- **Phase 2 (Secondary):** Prometheus, Grafana, Restic, Uptime Kuma, Homarr, Affine

**Network Architecture:**
```
Internet → Caddy (reverse proxy) → Authelia (SSO) → Protected services
         → Minecraft (direct port 25565)
Tailscale VPN → Cockpit (admin access)
```

## Directory Structure Map

```
~/homelab-config/                    # Target deployment path (default)
├── quadlets/                        # Podman Quadlet definitions
│   ├── networks/                    # Network definitions (.network files)
│   ├── volumes/                     # Volume definitions (.volume files)
│   ├── timers/                      # Systemd timers (backup schedules)
│   └── containers/                  # Container definitions (.container files)
│       ├── phase1-critical/         # Essential services
│       └── phase2-services/         # Optional services
│
├── configs/                         # Service configurations (mounted into containers)
│   ├── caddy/                       # Caddyfile (reverse proxy)
│   ├── authelia/                    # SSO configuration + users_database.yml
│   ├── prometheus/                  # prometheus.yml, prometheus.env
│   ├── grafana/                     # grafana.env
│   ├── restic/                      # restic.env (backup config)
│   └── minecraft/                   # minecraft.env (server properties)
│
├── secrets/                         # NOT IN GIT - Secret templates only
│   ├── README.md                    # Secret creation guide
│   └── secrets.env.template         # Required secrets list
│
├── scripts/                         # Deployment automation
│   ├── bootstrap.sh                 # Initial setup (checks, linger enable, deploy)
│   ├── deploy.sh                    # Deploy Quadlets to systemd dirs
│   ├── enable-all-services.sh       # Enable all services for auto-start
│   └── restic-backup.sh             # Restic backup script
│
├── docs/                            # Documentation
│   ├── ARCHITECTURE.md              # Original homelab plan
│   ├── IMPLEMENTATION_GUIDE.md      # Step-by-step deployment
│   ├── SECRETS_SETUP.md             # Secrets management
│   └── TROUBLESHOOTING.md           # Common issues
│
├── .claude/                         # Claude Code configuration
│   ├── REPOSITORY_GUIDE.md          # This file
│   ├── instructions.md              # Custom Claude instructions
│   ├── claude.json                  # Project settings
│   └── commands/                    # Custom slash commands
│       └── add-service.md           # /add-service command
│
├── .claudeignore                    # Files Claude should ignore
├── .env.example                     # Path configuration template
├── DEPLOYMENT.md                    # Deployment guide
└── README.md                        # Main project documentation
```

## Priority Files to Read

When starting a new conversation, read these files first based on the task:

**For Deployment/Setup:**
1. `DEPLOYMENT.md` - Deployment workflow
2. `README.md` - Quick start guide
3. `scripts/bootstrap.sh` - Bootstrap process

**For Adding/Modifying Services:**
1. `quadlets/containers/phase1-critical/*.container` - Example Quadlets
2. `quadlets/networks/homelab.network` - Network definition
3. `configs/*/` - Relevant service config

**For Troubleshooting:**
1. `docs/TROUBLESHOOTING.md` - Common issues
2. `docs/SECRETS_SETUP.md` - Secret management
3. Relevant service logs via `journalctl --user -u service-name.service`

**For Understanding Architecture:**
1. `docs/ARCHITECTURE.md` - Original homelab plan
2. `docs/IMPLEMENTATION_GUIDE.md` - Implementation details
3. This file (`.claude/REPOSITORY_GUIDE.md`)

## Common Task Patterns

### Adding a New Service

1. **Create Quadlet file** in `quadlets/containers/phase{1,2}-*/`
2. **Create config directory** in `configs/service-name/`
3. **Add environment file** as `configs/service-name/service-name.env`
4. **Create secrets** if needed via `podman secret create`
5. **Deploy** with `./scripts/deploy.sh`
6. **Enable** with `systemctl --user enable --now service-name.service`

Use `/add-service` slash command for guided wizard.

### Deploying Configuration Changes

```bash
# 1. Edit files in git repo
# 2. Deploy Quadlets
./scripts/deploy.sh

# 3. Restart affected services
systemctl --user restart service-name.service

# 4. Verify
systemctl --user status service-name.service
journalctl --user -u service-name.service -n 50
```

### Troubleshooting a Service

```bash
# Check status
systemctl --user status service-name.service

# View recent logs
journalctl --user -u service-name.service -n 100

# Follow logs in real-time
journalctl --user -u service-name.service -f

# Check container directly
podman ps -a
podman logs container-name

# Verify secrets exist
podman secret ls

# Verify network exists
podman network ls | grep homelab
```

## Important Conventions

### Path Convention

- **Target deployment path:** `~/homelab-config` (default)
- **Override via:** `HOMELAB_REPO_DIR` environment variable
- **Config locations:** `~/.config/homelab.env` or `/etc/homelab.env`
- **Systemd expansion:** `%h` = user home directory

**Example:**
```ini
# In Quadlet file
EnvironmentFile=%h/homelab-config/configs/service/service.env
Volume=%h/homelab-config/configs/caddy/Caddyfile:/etc/caddy/Caddyfile:Z,ro
```

### Quadlet Naming Convention

- **Networks:** `homelab.network` → generates `homelab-network.service`
- **Volumes:** `service-data.volume` → generates `service-data.volume`
- **Containers:** `service.container` → generates `service.service`

### Systemd Dependencies

Always specify proper dependencies in `[Unit]` section:

```ini
[Unit]
Description=Service Name
After=network-online.target homelab-network.service
```

**Common dependencies:**
- `network-online.target` - Wait for network
- `homelab-network.service` - Wait for Podman network
- `other-service.service` - Wait for another service

### Resource Limits

Define resource limits in `[Container]` section to keep services lean:

```ini
[Container]
MemoryMax=5G        # Hard limit (OOM kill if exceeded)
MemoryHigh=4.5G     # Soft limit (throttle if exceeded)
```

### Auto-Start Configuration

Services auto-start on boot when:
1. `WantedBy=default.target` in `[Install]` section
2. Service is enabled: `systemctl --user enable service.service`
3. User linger enabled: `loginctl enable-linger $USER`

### Security Patterns

**Secrets:**
- NEVER commit actual secrets to git
- Use `podman secret create` for sensitive data
- Reference in Quadlet: `Secret=secret-name,type=env,target=ENV_VAR`

**File Permissions:**
- Use `:Z` suffix for SELinux labeling: `Volume=path:path:Z`
- Use `:ro` suffix for read-only mounts: `Volume=path:path:Z,ro`

**Container User:**
- Specify non-root user when possible: `User=65534:65534`

## Example: Minecraft Quadlet

From `quadlets/containers/phase1-critical/minecraft.container`:

```ini
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

# Environment configuration
EnvironmentFile=%h/homelab-config/configs/minecraft/minecraft.env

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

**Key patterns demonstrated:**
- Proper dependencies (`After=`)
- Network attachment (`Network=homelab.network`)
- Volume mounts with SELinux labels (`:Z`)
- Environment files using `%h` expansion
- Podman secrets for sensitive data
- Resource limits (MemoryMax, MemoryHigh)
- Auto-start configuration (`WantedBy=default.target`)
- Extended timeout for slow-starting service

## GitOps Principles

1. **Declarative over Imperative**
   - Prefer Quadlet files over bash scripts
   - Define desired state, let systemd manage it

2. **Minimal Bash Scripting**
   - Scripts only for: deployment (copying files), bootstrap (one-time setup)
   - Avoid complex logic in scripts
   - Service management via systemd, not scripts

3. **Version Everything**
   - All configs in git
   - Never edit files on server directly
   - Make changes in git, deploy

4. **Lean Services**
   - Set memory limits on all containers
   - Use `AutoUpdate=registry` for automatic image updates
   - Restart policies: `Restart=always` for critical services

## Anti-Patterns to Avoid

- Creating bash scripts to start/stop services (use systemd)
- Storing secrets in git (use podman secrets)
- Hardcoding paths without `%h` expansion
- Missing `After=` dependencies (causes race conditions)
- Forgetting `:Z` on volume mounts (SELinux issues)
- Not setting resource limits (resource exhaustion)
- Editing server files directly (breaks GitOps)
