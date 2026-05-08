# Homelab GitOps Configuration

A Homelab setup using Podman Quadlets for containerized services. Features a Minecraft Pixelmon server, SSO authentication, monitoring, and more

### Core Principles

- **GitOps:** All infrastructure as code, version controlled
- **Declarative:** Podman Quadlets instead of bash scripts
- **Secure:** Podman secrets, Authelia SSO, Tailscale VPN
- **Modular:** Phased deployment (critical services first)
- **Reproducible:** Build from scratch anytime

## 🏗️ Architecture

```
Internet
  │
  ├─→ Public Access (80/443, 25565)
  │   ├─→ Caddy (Reverse Proxy)
  │   │   ├─→ Authelia (SSO)
  │   │   │   ├─→ Web Apps (protected)
  │   │   │   └─→ Dashboards (protected)
  │   │   └─→ Minecraft (direct)
  │
  └─→ Admin Access (Tailscale VPN)
      └─→ Cockpit (Management UI)
```

## 📦 Services

### Phase 1: Critical Services
- **Tailscale** - Secure admin VPN access
- **Caddy** - Reverse proxy with auto-HTTPS
- **Authelia** - Single Sign-On & 2FA
- **Minecraft** - Pixelmon server (1.16.5 Forge)
- **Cockpit** - Web management UI

### Phase 2: Secondary Services
- **Prometheus** - Metrics collection
- **Grafana** - Monitoring dashboards
- **Restic** - Automated encrypted backups to NAS with Discord notifications
- **Uptime Kuma** - Service monitoring
- **Homarr** - Service dashboard
- **Affine** - Productivity suite

## 📁 Repository Structure

```
.
├── quadlets/                    # Podman Quadlet definitions
│   ├── networks/                # Network definitions
│   ├── volumes/                 # Volume definitions
│   ├── timers/                  # Systemd timers (e.g., backup schedules)
│   └── containers/              # Container definitions
│       ├── phase1-critical/     # Essential services
│       └── phase2-services/     # Optional services (incl. restic)
│
├── configs/                     # Service configurations
│   ├── caddy/                   # Caddyfile
│   ├── authelia/                # SSO configuration
│   ├── prometheus/              # Metrics config
│   ├── restic/                  # Backup configuration
│   └── minecraft/               # Server properties
│
├── secrets/                     # Secret templates (NOT in git)
│   ├── README.md                # Secret creation guide
│   └── secrets.env.template     # Required secrets list
│
├── scripts/                     # Deployment automation
│   ├── bootstrap.sh             # Initial setup
│   ├── deploy.sh                # Deploy Quadlets
│   ├── enable-all-services.sh   # Enable all services for auto-start
│   └── restic-backup.sh         # Restic backup script
│
├── docs/                        # Documentation
│   ├── ARCHITECTURE.md          # Original homelab plan
│   ├── IMPLEMENTATION_GUIDE.md  # Step-by-step deployment
│   ├── SECRETS_SETUP.md         # Secrets management
│   └── TROUBLESHOOTING.md       # Common issues
│
├── logs/                        # Service logs (NOT in git)
└── backups/                     # Volume backups (NOT in git)
```

## 🚀 Quick Start

### Prerequisites

- Fedora Server (or similar systemd-based distro)
- Podman installed
- Git installed
- Internet connection
- (Optional) Domain name for public services

### Installation

1. **Clone the repository:**
   ```bash
   # Option 1: Default location (recommended)
   git clone <repository-url> ~/homelab-config
   cd ~/homelab-config

   # Option 2: Custom location (requires configuration)
   git clone <repository-url> ~/path/to/custom/location
   cd ~/path/to/custom/location

   # If using custom location, configure the path:
   echo 'export HOMELAB_REPO_DIR="$HOME/path/to/custom/location"' > ~/.config/homelab.env
   ```

2. **Run bootstrap script:**
   ```bash
   ./scripts/bootstrap.sh
   ```

3. **Create required secrets:**
   ```bash
   # Follow the guide
   cat secrets/README.md

   # Generate Authelia secrets
   openssl rand -hex 32 | podman secret create authelia-jwt-secret -
   openssl rand -hex 32 | podman secret create authelia-session-secret -
   openssl rand -hex 32 | podman secret create authelia-storage-key -

   # Create Grafana password
   echo "your-secure-password" | podman secret create grafana-admin-password -
   ```

4. **Configure Authelia users:**
   ```bash
   # Copy template
   cp configs/authelia/users_database.yml.template configs/authelia/users_database.yml

   # Generate password hash
   podman run --rm authelia/authelia:latest \
     authelia crypto hash generate argon2 --password 'YourPassword'

   # Edit users_database.yml and add users with hashes
   nano configs/authelia/users_database.yml
   ```

5. **Update domain in Caddyfile:**
   ```bash
   # Replace 'yourdomain.com' with your actual domain
   nano configs/caddy/Caddyfile
   ```

6. **Enable and start services (auto-start on boot):**
   ```bash
   # Deploy Quadlets
   ./scripts/deploy.sh

   # Option A: Enable all services at once (recommended)
   ./scripts/enable-all-services.sh

   # Option B: Enable services individually
   systemctl --user enable --now homelab-network.service
   systemctl --user enable --now caddy.service
   systemctl --user enable --now authelia.service
   systemctl --user enable --now minecraft.service
   systemctl --user enable --now prometheus.service
   systemctl --user enable --now grafana.service
   systemctl --user enable --now restic-backup.timer
   ```

   **Note:** Services will automatically start on boot thanks to systemd's `WantedBy=default.target` in the Quadlet definitions. User linger is enabled by `bootstrap.sh`.

## 🔒 Security

### Secrets Management

- **Podman Secrets:** Encrypted at rest, ephemeral in containers
- **Never in Git:** Actual secret values never committed
- **Documented:** Templates show what's needed without exposing values

### Access Control

- **Public Services:** Protected by Authelia SSO
- **Admin Access:** Tailscale VPN only (Cockpit)
- **Firewall:** Only necessary ports open (80, 443, 25565)
- **Rootless Podman:** All containers run as non-root user

### Authentication Flow

```
User → https://app.yourdomain.com
  ↓
Caddy checks authentication
  ↓
No valid session? → Redirect to Authelia
  ↓
User logs in (username/password + optional 2FA)
  ↓
Session cookie set → Access granted
```

## 📊 Monitoring

- **Prometheus:** Scrapes metrics from Minecraft and system
- **Grafana:** Visualizes metrics with dashboards
- **Uptime Kuma:** Monitors service availability
- **Systemd Logs:** `journalctl --user -u service-name.service`

## 🎮 Minecraft Server

### Specs
- **Version:** 1.16.5 (Forge 36.2.39)
- **Modpack:** Pixelmon Reforged
- **Memory:** 4GB allocated (5GB max)
- **Ports:** 25565 (game), 19565 (metrics)

### Connecting
```
Server Address: mc.yourdomain.com:25565
```

### Admin Commands
```bash
# Console access
podman exec -it minecraft-papa rcon-cli

# View logs
journalctl --user -u minecraft.service -f

# Backup all volumes (including world)
systemctl --user start restic-backup.service
```

## 🛠️ Management

### Service Management

```bash
# Check service status
systemctl --user status minecraft.service

# Restart service
systemctl --user restart caddy.service

# Stop service
systemctl --user stop prometheus.service

# View logs (follow mode)
journalctl --user -u authelia.service -f

# View recent logs
journalctl --user -u minecraft.service -n 100

# List running services
systemctl --user list-units --type=service --state=running | grep -E '(homelab|caddy|authelia|minecraft|prometheus|grafana)'

# List enabled services (auto-start on boot)
systemctl --user list-unit-files --type=service --state=enabled | grep -E '(homelab|caddy|authelia|minecraft|prometheus|grafana)'

# Enable service for auto-start on boot
systemctl --user enable minecraft.service

# Disable auto-start on boot
systemctl --user disable minecraft.service

# Enable and start immediately
systemctl --user enable --now grafana.service
```

### Container Management

```bash
# List running containers
podman ps

# View container logs
podman logs -f minecraft-papa

# Execute command in container
podman exec -it minecraft-papa bash
```

### Backup & Restore

Restic provides encrypted, deduplicated backups to your NAS with Discord notifications:

```bash
# Configure restic (first time only)
cp configs/restic/restic.env.template configs/restic/restic.env
nano configs/restic/restic.env  # Set RESTIC_REPOSITORY and other settings

# Create required secrets (see secrets/README.md)
openssl rand -base64 32 | podman secret create restic-repository-password -

# Deploy restic backup service and timer
./scripts/deploy.sh

# Enable automatic daily backups at 2:00 AM
systemctl --user enable --now restic-backup.timer

# Check timer status
systemctl --user list-timers | grep restic

# Manually trigger a backup
systemctl --user start restic-backup.service

# View backup logs
journalctl --user -u restic-backup.service -f
```

See [configs/restic/README.md](configs/restic/README.md) for detailed setup and restore instructions.

### Updates

```bash
# Pull latest from git
git pull

# Deploy updated Quadlets
./scripts/deploy.sh

# Restart affected services
systemctl --user restart service-name.service

# Update container images
podman auto-update
systemctl --user restart service-name.service
```

## 📚 Documentation

- **[IMPLEMENTATION_GUIDE.md](docs/IMPLEMENTATION_GUIDE.md)** - Full deployment walkthrough
- **[SECRETS_SETUP.md](docs/SECRETS_SETUP.md)** - Secrets management guide
- **[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** - Common issues and solutions
- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** - Original homelab plan

## 🐛 Troubleshooting

### Service won't start
```bash
# Check status
systemctl --user status service-name.service

# View logs
journalctl --user -u service-name.service -n 50
```

### Missing secrets
```bash
# List secrets
podman secret ls

# Create missing secret
echo "value" | podman secret create secret-name -
```

### Network issues
```bash
# Check network exists
podman network ls | grep homelab

# Restart network
systemctl --user restart homelab-network.service
```

See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for more solutions.

## 📝 License

See [LICENSE](LICENSE) file.

## 🙏 Acknowledgments

- [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server) - Minecraft container image
- [Authelia](https://www.authelia.com/) - SSO solution
- [Caddy](https://caddyserver.com/) - Web server
- [Podman](https://podman.io/) - Container runtime