# Homelab Architecture Plan - Quadlet Migration

**Last Updated:** 2026-05-02
**System:** 6-core, 16GB RAM, 512GB Storage
**Approach:** Podman Quadlets + Systemd + Cockpit GUI

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Hardware Specifications](#hardware-specifications)
3. [Architecture Overview](#architecture-overview)
4. [Service Stack](#service-stack)
5. [Discord Integration Architecture](#discord-integration-architecture)
6. [Quadlet Migration Strategy](#quadlet-migration-strategy)
7. [CRITIQUE: Design Analysis](#critique-design-analysis)
8. [SUGGESTIONS: Things to Consider](#suggestions-things-to-consider)
9. [GOTCHAS: Potential Issues](#gotchas-potential-issues)
10. [Implementation Phases](#implementation-phases)
11. [Example Quadlet Files](#example-quadlet-files)
12. [Reference Commands](#reference-commands)

---

## Executive Summary

### Goals
- Migrate from manual systemd units to Podman Quadlets
- Deploy Cockpit for web-based container management
- Add Uptime Kuma for service monitoring
- Integrate comprehensive Discord notifications
- Implement reverse proxy (Caddy) + SSO (Authelia)
- Deploy productivity (Affine) and dashboard (Homarr) apps
- Maintain existing Minecraft, Prometheus, Grafana services
- Keep system lean and efficient

### Key Decisions Made
- ✅ **Container Runtime:** Podman (rootless) - keeping existing choice
- ✅ **Orchestration:** Quadlet (.container files) - modern approach
- ✅ **GUI:** Cockpit + Podman plugin - only GUI with Quadlet support
- ✅ **Reverse Proxy:** Caddy - simplest for beginners, auto-HTTPS
- ✅ **Authentication:** Authelia - lightweight SSO with 2FA
- ✅ **Monitoring:** Uptime Kuma + existing Prometheus/Grafana stack
- ✅ **Notifications:** Discord webhooks - zero overhead, simple
- ✅ **DDNS:** Cloudflare Tunnel - no port forwarding needed

### Timeline Estimate
- **Phase 1** (Foundation): 30 minutes
- **Phase 2** (Migration): 1-2 hours
- **Phase 3** (Networking): 1 hour
- **Phase 4** (New Apps): 1 hour
- **Phase 5** (Integration): 1 hour
- **Total:** 4-6 hours (can be done over multiple sessions)

---

## Hardware Specifications

### Your System
```
CPU:     6 cores (assumed 12 threads)
RAM:     16GB
Storage: 512GB
OS:      Fedora Linux (based on git commits)
Network: Assume 1Gbps LAN
```

### Resource Budget

| Service | RAM Usage | CPU Usage | Storage | Notes |
|---------|-----------|-----------|---------|-------|
| **Existing Services** |
| Minecraft Server | 4GB | 2-4 cores | ~10GB | As configured |
| Prometheus | 200MB | 0.1 core | ~5GB | 15d retention |
| Grafana | 200MB | 0.1 core | ~1GB | Dashboards |
| **New Infrastructure** |
| Caddy | 30MB | 0.05 core | 100MB | Reverse proxy |
| Authelia | 100MB | 0.1 core | 100MB | SSO + 2FA |
| Cloudflare Tunnel | 40MB | 0.05 core | 50MB | DDNS |
| Cockpit | 50MB | 0.1 core | 200MB | Management UI |
| **New Applications** |
| Uptime Kuma | 50MB | 0.1 core | ~1GB | Monitoring |
| Homarr | 50MB | 0.05 core | 200MB | Dashboard |
| Affine | 300MB | 0.2 core | ~2GB | Productivity |
| **System Overhead** |
| Podman | 50MB | - | - | Runtime |
| OS + Services | ~2GB | 1 core | ~20GB | Base system |
| **TOTAL** | **~7.1GB** | **~4 cores** | **~40GB** | Peak usage |
| **Available** | **8.9GB** | **2 cores** | **472GB** | For tinkering |

### Analysis
- ✅ **RAM:** Comfortable headroom (56% utilization)
- ✅ **CPU:** Plenty of cores for burst loads
- ✅ **Storage:** Massive space for data, backups, experiments
- ✅ **Scaling:** Can add 3-4 more medium services easily

---

## Architecture Overview

### Network Topology

```
                          Internet
                             |
                    Cloudflare DNS
                             |
            +----------------+----------------+
            |                                 |
    Cloudflare Tunnel                  Direct Connection
    (Web Services)                     (Minecraft :25565)
            |                                 |
            v                                 v
    +-----------------------------------------------+
    |          Caddy Reverse Proxy (HTTPS)          |
    +-----------------------------------------------+
                         |
                         v
    +-----------------------------------------------+
    |        Authelia (SSO Authentication)          |
    +-----------------------------------------------+
                         |
        +----------------+------------------+
        |                |                  |
        v                v                  v
    [Homarr]        [Affine]           [Grafana]
    [Uptime Kuma]   [Other Apps]
        |
        +------ All connected via Podman Network: homelab
                |
                v
        [Prometheus] <--- Scrapes metrics from:
                          - Minecraft (via exporter)
                          - Uptime Kuma (/metrics)
                          - Caddy (/metrics)
                          - cAdvisor (container stats)
```

### Service Dependencies

```
Podman Network (homelab.network)
  ↓
Prometheus.service
  ↓
├── Grafana.service
├── Minecraft.service → backup-minecraft.timer
└── Uptime-Kuma.service
      ↓
    Authelia.service
      ↓
    Caddy.service
      ↓
    ├── Homarr.service
    └── Affine.service
```

### Directory Structure

```
~/.config/containers/systemd/
├── networks/
│   └── homelab.network              # Shared network for all containers
│
├── volumes/
│   ├── minecraft-data.volume        # Minecraft world data
│   ├── prometheus-data.volume       # Prometheus metrics DB
│   ├── grafana-data.volume          # Grafana dashboards
│   ├── uptime-kuma-data.volume      # Uptime Kuma DB
│   ├── affine-data.volume           # Affine workspace
│   ├── authelia-data.volume         # Authelia user DB
│   └── caddy-data.volume            # Caddy certificates
│
└── containers/
    ├── minecraft.container
    ├── prometheus.container
    ├── grafana.container
    ├── uptime-kuma.container
    ├── authelia.container
    ├── caddy.container
    ├── homarr.container
    ├── affine.container
    └── cloudflared.container        # Optional: Cloudflare tunnel

~/applications/
├── minecraft/config/                # Existing Minecraft configs
├── prometheus/prometheus.yml        # Prometheus scrape config
├── caddy/Caddyfile                  # Reverse proxy routes
├── authelia/configuration.yml       # SSO configuration
└── backup/                          # Backup destination
```

---

## Service Stack

### Core Infrastructure

#### 1. Cockpit (Management GUI)
- **Purpose:** Web UI for managing Quadlet containers, system monitoring
- **Access:** `https://<server-ip>:9090`
- **Features:**
  - View all Quadlet containers with "service" badge
  - Start/stop/restart containers via systemd
  - View logs, resource usage, terminal access
  - System monitoring (CPU, RAM, disk, network)
- **Installation:** `sudo dnf install cockpit cockpit-podman`
- **Enable:** `sudo systemctl enable --now cockpit.socket`

#### 2. Caddy (Reverse Proxy)
- **Purpose:** HTTPS termination, routing, automatic Let's Encrypt certificates
- **Image:** `docker.io/library/caddy:latest`
- **Ports:** 80, 443
- **Config:** `~/applications/caddy/Caddyfile`
- **Why Caddy?**
  - Automatic HTTPS (zero config)
  - Simple Caddyfile syntax
  - Integrates easily with Authelia
  - Built-in Prometheus metrics

#### 3. Authelia (SSO + 2FA)
- **Purpose:** Single sign-on, two-factor authentication for all services
- **Image:** `docker.io/authelia/authelia:latest`
- **Port:** 9091
- **Features:**
  - TOTP (Google Authenticator, Authy)
  - WebAuthn (hardware keys, biometrics)
  - Password policies
  - Session management
- **Why Authelia over Authentik?**
  - Much lighter (~100MB vs ~500MB)
  - Simpler config for homelab
  - Integrates perfectly with Caddy

#### 4. Cloudflare Tunnel
- **Purpose:** Expose services to internet without port forwarding
- **Image:** `docker.io/cloudflare/cloudflared:latest`
- **Alternative:** Traditional DDNS (DuckDNS) + port forwarding
- **Advantages:**
  - Works behind CGNAT/firewall
  - Free DDoS protection
  - Automatic DNS updates
  - No exposed public IP
- **Disadvantage:** Minecraft may need separate tunnel (TCP/UDP)

### Monitoring Stack

#### 5. Prometheus (Existing - Migrating to Quadlet)
- **Purpose:** Metrics collection, time-series database
- **Current:** Manual systemd unit
- **Migration:** Convert to Quadlet
- **Scrape Targets:**
  - Minecraft exporter (`:19565/metrics`)
  - Uptime Kuma (`:3001/metrics`)
  - Caddy (`:2019/metrics`)
  - cAdvisor (`:8080/metrics`) - optional container metrics
- **Retention:** 15 days (adjustable)

#### 6. Grafana (Existing - Migrating to Quadlet)
- **Purpose:** Visualization, dashboards
- **Features:**
  - Import community dashboards
  - Custom queries
  - Alert rules (can send to Discord via webhook)
- **Integrations:**
  - Prometheus datasource
  - Authelia SSO (configure OIDC)

#### 7. Uptime Kuma (NEW)
- **Purpose:** Service uptime monitoring, status pages
- **Image:** `docker.io/louislam/uptime-kuma:latest`
- **Port:** 3001
- **Features:**
  - Monitor HTTP/HTTPS, TCP, Ping, DNS, Docker containers
  - Discord webhook notifications (built-in)
  - Prometheus metrics exporter
  - Public/private status pages
  - 20-second check intervals
  - SSL certificate expiry monitoring
- **Monitors to Configure:**
  - Minecraft server (TCP port 25565)
  - Caddy (HTTPS check on your domain)
  - Authelia (HTTPS)
  - Homarr, Affine, Grafana (HTTPS)
  - External websites (optional)
  - SSL certificate expiry

### Applications

#### 8. Homarr (NEW)
- **Purpose:** Unified dashboard, service launcher
- **Image:** `ghcr.io/ajnart/homarr:latest`
- **Port:** 7575
- **Features:**
  - Beautiful UI for accessing all services
  - Weather, calendar, RSS feeds
  - Docker container status (via Podman API)
  - Integration with *arr apps (if you add later)
  - Custom widgets

#### 9. Affine (NEW)
- **Purpose:** Productivity suite (Notion alternative)
- **Image:** `ghcr.io/toeverything/affine:stable`
- **Port:** 3010
- **Features:**
  - Note-taking, docs, wikis
  - Real-time collaboration
  - Offline-first, end-to-end encrypted
  - Whiteboard, tables, kanban
- **Storage:** Requires PostgreSQL or SQLite (built-in)

#### 10. Minecraft Server (Existing - Migrating to Quadlet)
- **Purpose:** Pixelmon game server
- **Current:** Complex run script + systemd unit + PlayIt.gg tunnel
- **Migration:** Simplify to single Quadlet file
- **Keep:**
  - Discord startup notifications
  - Prometheus exporter
  - Backup timer (convert to Quadlet timer)
- **Consider:** Replace PlayIt.gg with Cloudflare Tunnel or direct port forward

---

## Discord Integration Architecture

### Overview
All notifications route through Discord webhooks (no bot needed).

### Webhook Setup
1. Create Discord server or use existing
2. Create channels: `#uptime-alerts`, `#backup-logs`, `#system-alerts`, `#minecraft-events`
3. For each channel: Settings → Integrations → Webhooks → New Webhook
4. Copy webhook URLs (keep secure!)

### Integration Points

#### 1. Uptime Kuma → Discord (Service Up/Down)
- **Setup:** Built-in Discord notification in Uptime Kuma UI
- **Triggers:**
  - Service goes down
  - Service comes back up
  - SSL certificate expiring soon
- **Example Notification:**
  ```
  🔴 DOWN: minecraft.yourdomain.com
  Status: Offline (timeout)
  Duration: 2 minutes
  ```

#### 2. Backup Script → Discord (Existing, Keep)
- **Current:** Already implemented in `backup_minecraft_server.sh`
- **Triggers:**
  - Backup success
  - Backup failure
- **Keep:** Your existing Discord webhook integration

#### 3. Prometheus Alertmanager → Discord (System Alerts)
- **Setup:** Deploy Alertmanager container, configure webhook receiver
- **Triggers:**
  - CPU > 80% for 5 minutes
  - RAM > 90% for 5 minutes
  - Disk > 85%
  - Container crash/restart
- **Example Alert:**
  ```
  ⚠️ WARNING: High CPU Usage
  Host: homelab-server
  Value: 87% (threshold: 80%)
  Duration: 6 minutes
  ```

#### 4. Minecraft → Discord (Player Events)
- **Option A:** Use Discord Minecraft plugin
  - Install DiscordSRV or similar mod
  - Sends player join/leave, chat relay, server status
- **Option B:** Parse Minecraft logs with script
  - Watch log file for events
  - Send webhook on specific patterns
- **Events:**
  - Player joined/left server
  - Server started/stopped
  - Server crash
  - Performance warnings (TPS drops)

#### 5. Grafana → Discord (Optional Dashboard Alerts)
- **Setup:** Configure Discord webhook as contact point
- **Use Cases:**
  - Threshold alerts from dashboards
  - Scheduled reports
- **Consider:** May be redundant with Prometheus Alertmanager

### Discord Webhook Template

```bash
# Generic webhook sender function
send_discord_alert() {
    local webhook_url="$1"
    local title="$2"
    local description="$3"
    local color="$4"  # Decimal color: green=3066993, red=15158332, yellow=16776960

    curl -H "Content-Type: application/json" \
         -X POST \
         -d "{
           \"embeds\": [{
             \"title\": \"$title\",
             \"description\": \"$description\",
             \"color\": $color,
             \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\"
           }]
         }" \
         "$webhook_url"
}

# Usage examples
send_discord_alert "$WEBHOOK_URL" "✅ Backup Complete" "Minecraft world backed up successfully" 3066993
send_discord_alert "$WEBHOOK_URL" "🔴 Service Down" "Grafana is unreachable" 15158332
```

---

## Quadlet Migration Strategy

### Why Quadlet?

#### Advantages Over Current Systemd Units
1. **Simpler Syntax:** Declarative .container files vs complex ExecStart commands
2. **Auto-Regeneration:** Podman auto-updates systemd units when .container changes
3. **Dependency Management:** `Network=homelab.network` auto-creates dependencies
4. **No Manual Scripting:** No need for separate `run_container.sh` scripts
5. **Auto-Updates:** `AutoUpdate=registry` enables automated image pulls
6. **Better Organization:** All configs in `~/.config/containers/systemd/`
7. **Cockpit Integration:** Full GUI visibility and control

#### Comparison: Old vs New

**Old Approach (Current):**
```
run_minecraft_container.sh (40 lines)
  → Creates container once with podman create
startup_minecraft_server.service (25 lines)
  → Runs startup script with podman start
startup_minecraft_server.sh (30 lines)
  → Starts container + PlayIt tunnel + Discord notification

Total: 3 files, ~95 lines, manual coordination
```

**New Approach (Quadlet):**
```
minecraft.container (30 lines)
  → Declarative definition, auto-generates systemd unit

Total: 1 file, ~30 lines, automatic systemd integration
```

### Migration Process

#### Step 1: Backup Current Setup
```bash
# Backup systemd units
mkdir -p ~/homelab-migration-backup
cp -r ~/.config/systemd/user ~/homelab-migration-backup/systemd-old

# Backup container scripts
cp -r ~/applications ~/homelab-migration-backup/applications-old

# Export container configs (for reference)
podman inspect minecraft-papa > ~/homelab-migration-backup/minecraft-papa-inspect.json
podman inspect prometheus > ~/homelab-migration-backup/prometheus-inspect.json
podman inspect grafana > ~/homelab-migration-backup/grafana-inspect.json
```

#### Step 2: Create Quadlet Directory Structure
```bash
mkdir -p ~/.config/containers/systemd/{networks,volumes,containers}
```

#### Step 3: Create Network Quadlet
```bash
cat > ~/.config/containers/systemd/networks/homelab.network <<'EOF'
[Network]
NetworkName=homelab
Driver=bridge
EOF
```

#### Step 4: Convert One Service at a Time
**Recommendation:** Start with Prometheus (simplest), then Grafana, then Minecraft (most complex)

#### Step 5: Enable and Test
```bash
# Reload systemd to pick up new Quadlet files
systemctl --user daemon-reload

# Enable and start service
systemctl --user enable --now prometheus.service

# Check status
systemctl --user status prometheus.service
journalctl --user -u prometheus.service -f

# Verify in Cockpit
# Navigate to https://<server-ip>:9090 → Podman
```

#### Step 6: Disable Old Services (After Verification)
```bash
# Stop old service
systemctl --user stop startup-prometheus.service
systemctl --user disable startup-prometheus.service

# Remove old container (Quadlet creates new one)
podman stop prometheus
podman rm prometheus
```

### Using `podlet` for Conversion

`podlet` is a CLI tool that auto-generates Quadlet files from existing containers.

```bash
# Install podlet (Rust tool)
cargo install podlet
# OR
wget https://github.com/k9withabone/podlet/releases/download/v0.3.0/podlet-x86_64-unknown-linux-musl
chmod +x podlet-x86_64-unknown-linux-musl
sudo mv podlet-x86_64-unknown-linux-musl /usr/local/bin/podlet

# Convert existing container to Quadlet
podman inspect minecraft-papa | podlet podman -f - > minecraft.container

# Review and edit the generated file
```

---

## CRITIQUE: Design Analysis

### Strengths ✅

#### 1. **Excellent Foundation**
- ✅ Already using Podman (rootless) - secure by design
- ✅ Systemd integration - production-grade approach
- ✅ Prometheus + Grafana - industry-standard monitoring
- ✅ Automated backups with Discord alerts - proactive operations
- ✅ Environment variable management - 12-factor app principles

#### 2. **Smart Service Choices**
- ✅ Caddy - Perfect for beginners, auto-HTTPS is killer feature
- ✅ Authelia - Right-sized for homelab (vs heavy Authentik/Keycloak)
- ✅ Uptime Kuma - Lightweight, feature-rich, great UI
- ✅ Cloudflare Tunnel - Solves port forwarding pain, free tier sufficient
- ✅ Quadlet - Modern approach, future-proof

#### 3. **Good Resource Planning**
- ✅ Headroom for growth (56% RAM utilization)
- ✅ Not over-engineering for homelab scale
- ✅ Lean service selection

#### 4. **Discord Webhook Strategy**
- ✅ Zero overhead vs running a bot
- ✅ Sufficient for one-way notifications
- ✅ Multiple integration points

### Weaknesses ⚠️

#### 1. **Single Point of Failure**
- ⚠️ **No redundancy:** Single server, if it goes down, everything is offline
- ⚠️ **No failover:** Minecraft server has no backup instance
- ⚠️ **Mitigation:** Acceptable for homelab, but consider UPS for power failures

#### 2. **Backup Strategy Gaps**
- ⚠️ **Minecraft only:** Other services (Grafana dashboards, Uptime Kuma configs, Affine data) not backed up
- ⚠️ **Single destination:** Only backing up to NAS, no off-site backup
- ⚠️ **No disaster recovery test:** Restore process not documented/tested
- ⚠️ **Mitigation:** Extend backup script to include all volumes, test restore procedure

#### 3. **Network Security**
- ⚠️ **No firewall rules documented:** Assuming OS firewall, but not explicit
- ⚠️ **Service exposure:** Cockpit on port 9090 - should be firewalled or behind VPN
- ⚠️ **Minecraft direct exposure:** If using port forwarding, exposes server to DDoS
- ⚠️ **Mitigation:** Document firewall rules, use Cloudflare Tunnel for web services, consider Tailscale for admin access

#### 4. **Monitoring Gaps**
- ⚠️ **No host metrics:** Prometheus not scraping node_exporter (CPU, disk, network of host)
- ⚠️ **No container metrics:** Missing cAdvisor for per-container resource usage
- ⚠️ **No log aggregation:** Logs scattered across journalctl
- ⚠️ **Mitigation:** Add node_exporter and cAdvisor containers

#### 5. **Authentication Concerns**
- ⚠️ **Authelia database:** Using file-based DB, not suitable for multi-user at scale
- ⚠️ **Password reset:** No email configured, can't reset passwords
- ⚠️ **Session management:** Default session timeout might be too long/short
- ⚠️ **Mitigation:** Fine for homelab, configure email SMTP for production use

#### 6. **Resource Contention Risk**
- ⚠️ **Minecraft can starve others:** 4GB allocation could spike higher, no cgroup limits
- ⚠️ **No QoS:** All containers have equal priority
- ⚠️ **Mitigation:** Set memory limits in Quadlet files (`MemoryMax=4G`)

#### 7. **Certificate Management**
- ⚠️ **Let's Encrypt rate limits:** Caddy auto-renewal might hit limits during testing
- ⚠️ **No cert monitoring:** Should monitor cert expiry via Uptime Kuma
- ⚠️ **Mitigation:** Use Caddy's staging environment during testing

### Missing Pieces 🔍

#### 1. **No VPN Access**
- Missing Tailscale/Wireguard for secure remote admin access
- Currently relying on public exposure or SSH tunneling
- **Recommendation:** Add Tailscale container for zero-trust access

#### 2. **No Secrets Management**
- Environment variables stored in plaintext files
- Discord webhooks, API keys exposed in configs
- **Recommendation:** Use Podman secrets or external vault (overkill for homelab)

#### 3. **No Container Update Strategy**
- AutoUpdate=registry is great, but no update schedule
- No testing before production updates
- **Recommendation:** Document `podman auto-update` cron job, staging environment

#### 4. **No Service Level Objectives (SLOs)**
- What's acceptable downtime for Minecraft? Grafana?
- No documented RTO/RPO for backups
- **Recommendation:** Define SLOs per service, adjust monitoring accordingly

#### 5. **No Network Segmentation**
- All containers on single network (homelab)
- Minecraft could theoretically access Authelia DB
- **Recommendation:** Fine for homelab, but consider separate networks for prod/mgmt

---

## SUGGESTIONS: Things to Consider

### Immediate Recommendations (Before Migration)

#### 1. **Add Tailscale VPN**
```ini
# ~/.config/containers/systemd/containers/tailscale.container
[Container]
Image=tailscale/tailscale:latest
Network=host
Volume=/var/lib/tailscale:/var/lib/tailscale
Environment=TS_AUTHKEY=tskey-auth-xxx
Environment=TS_HOSTNAME=homelab
CapAdd=NET_ADMIN
CapAdd=NET_RAW

[Service]
Restart=always

[Install]
WantedBy=default.target
```

**Why?**
- Secure remote access to Cockpit without exposing port 9090
- Access services via `http://homelab.tail-net.ts.net:3000` (Grafana)
- Free tier: 100 devices, unlimited traffic
- Alternative: Wireguard (more DIY)

#### 2. **Extend Backup Strategy**
```bash
# Backup all important volumes
VOLUMES=(
    "minecraft-data"
    "grafana-data"
    "uptime-kuma-data"
    "affine-data"
    "authelia-data"
)

for vol in "${VOLUMES[@]}"; do
    podman volume export systemd-$vol -o /tmp/$vol-backup.tar
    rsync /tmp/$vol-backup.tar $NAS_DESTINATION/
done
```

**Why?**
- Don't lose Grafana dashboards, Uptime Kuma monitors, Affine docs
- Volumes are easy to export/import

#### 3. **Add Host + Container Metrics**
```yaml
# Add to prometheus.yml scrape configs
scrape_configs:
  # Existing
  - job_name: 'minecraft'
    static_configs:
      - targets: ['minecraft-papa:19565']

  # NEW: Host metrics
  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']

  # NEW: Container metrics
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']

  # NEW: Uptime Kuma
  - job_name: 'uptime-kuma'
    static_configs:
      - targets: ['uptime-kuma:3001']
```

Deploy node_exporter and cAdvisor containers:
```ini
# ~/.config/containers/systemd/containers/node-exporter.container
[Container]
Image=quay.io/prometheus/node-exporter:latest
Network=homelab.network
PublishPort=9100:9100
Volume=/:/host:ro,rslave
PodmanArgs=--pid=host

# ~/.config/containers/systemd/containers/cadvisor.container
[Container]
Image=gcr.io/cadvisor/cadvisor:latest
Network=homelab.network
PublishPort=8080:8080
Volume=/:/rootfs:ro
Volume=/var/run:/var/run:ro
Volume=/sys:/sys:ro
Volume=/var/lib/containers:/var/lib/containers:ro
```

**Why?**
- See actual CPU/RAM/disk usage in Grafana
- Track per-container resource consumption
- Identify resource hogs

#### 4. **Set Resource Limits**
Add to all Quadlet .container files:
```ini
[Service]
MemoryMax=512M          # Hard limit
MemoryHigh=400M         # Throttle at 80%
CPUQuota=50%            # Max 50% of one core
```

**Why?**
- Prevent runaway containers from killing server
- Guarantee resources for critical services (Minecraft)

#### 5. **Document Firewall Rules**
```bash
# Firewall configuration (firewalld on Fedora)
sudo firewall-cmd --permanent --add-service=cockpit     # 9090 (restrict to Tailscale later)
sudo firewall-cmd --permanent --add-port=25565/tcp      # Minecraft (if not using tunnel)
sudo firewall-cmd --permanent --add-port=80/tcp         # Caddy HTTP (redirects to HTTPS)
sudo firewall-cmd --permanent --add-port=443/tcp        # Caddy HTTPS
sudo firewall-cmd --reload

# Restrict Cockpit to Tailscale network only (after Tailscale setup)
sudo firewall-cmd --permanent --zone=public --remove-service=cockpit
sudo firewall-cmd --permanent --zone=trusted --add-source=100.64.0.0/10  # Tailscale CGNAT range
sudo firewall-cmd --permanent --zone=trusted --add-service=cockpit
sudo firewall-cmd --reload
```

### Optional Enhancements (Future)

#### 1. **Service Alternatives to Consider**

| Current Choice | Alternative | Why Consider? |
|---------------|-------------|---------------|
| Homarr | Homepage | Lighter, simpler config |
| Affine | Outline | Better multi-user, SSO integration |
| Authelia | Authentik | More features (OIDC provider, LDAP), heavier |
| Caddy | Traefik | Auto-discovery of containers, more complex |
| Uptime Kuma | Healthchecks.io | Simpler cron-based monitoring |

**Recommendation:** Stick with current choices unless specific needs arise

#### 2. **Minecraft Improvements**

- **Mod:** Install DiscordSRV for rich Discord integration
- **Web Map:** Add Dynmap or BlueMap for live world viewer
- **Backup:** Use Restic instead of tar+rsync (incremental, encrypted, deduplication)
- **Performance:** Add Spark profiler for performance monitoring

#### 3. **Productivity Apps to Add**

- **Vaultwarden:** Password manager (Bitwarden-compatible)
- **Paperless-ngx:** Document management (scan/OCR/organize)
- **Nextcloud:** File sync, calendar, contacts (all-in-one)
- **Stirling PDF:** PDF manipulation tools
- **IT Tools:** Developer utilities dashboard

#### 4. **Media Server (If Interested)**

- **Jellyfin:** Media streaming (movies, music, photos)
- **Audiobookshelf:** Audiobook and podcast server
- **Komga:** Comic/manga server
- **Navidrome:** Music streaming (Subsonic API)

**Resource impact:** Each adds 200-500MB RAM

#### 5. **Automation Tools**

- **n8n:** Workflow automation (IFTTT/Zapier alternative)
- **Homepage + *arr integration:** Automate media downloads (Sonarr, Radarr, Prowlarr)
- **Home Assistant:** Smart home integration (if you have IoT devices)

### Cost/Complexity Tradeoffs

#### Simplicity vs Features
- **More simple:** Current plan (7-8 services, single network, Discord webhooks)
- **More features:** Add Tailscale, Traefik auto-discovery, full *arr stack, Nextcloud
- **Tradeoff:** Each service adds complexity, potential failure points, maintenance burden

#### Self-Hosted vs SaaS
- **Self-hosted pro:** Full control, privacy, learning experience, no subscription fees
- **Self-hosted con:** Your responsibility to maintain, update, backup, secure
- **Consider SaaS for:** Email (don't self-host), DNS (Cloudflare free), off-site backups (Backblaze B2)

#### Security vs Convenience
- **More secure:** Tailscale-only access, hardware 2FA keys, no port forwarding, separate networks
- **More convenient:** Simple passwords, public access, shared network, password managers
- **Recommendation:** For homelab, balance is fine. Add layers as you learn.

---

## GOTCHAS: Potential Issues

### Migration Gotchas

#### 1. **Volume Ownership Issues**
**Problem:** Quadlet creates volumes as systemd-minecraft-data, but your data is in ~/applications/minecraft/data
**Solution:** Use bind mounts instead of named volumes for existing data:
```ini
# Instead of:
Volume=minecraft-data.volume:/data

# Use:
Volume=%h/applications/minecraft/data:/data:Z
```
The `:Z` flag is critical for SELinux relabeling on Fedora!

#### 2. **Network Name Conflicts**
**Problem:** Existing `chonkatronic-services` network vs new `homelab` network
**Solution:** Migration strategy:
1. Create `homelab` network
2. Migrate one service at a time to new network
3. Remove old network after all services migrated
```bash
podman network rm chonkatronic-services
```

#### 3. **Port Conflicts**
**Problem:** Old container still running on port 3000, new Grafana Quadlet fails to start
**Solution:** Ensure old services are stopped before enabling Quadlet:
```bash
podman ps -a  # Check for running containers
systemctl --user stop startup-grafana.service
podman stop grafana && podman rm grafana
```

#### 4. **Systemd User Lingering**
**Problem:** Quadlet services don't start on boot because user not logged in
**Solution:** Enable lingering for your user:
```bash
sudo loginctl enable-linger $USER
```

#### 5. **SELinux Denials**
**Problem:** Container can't access volume, SELinux blocking
**Symptoms:** "Permission denied" errors in logs
**Solution:**
```bash
# Check for denials
sudo ausearch -m avc -ts recent

# Add :Z flag to Volume mounts in Quadlet
Volume=/path/to/data:/container/path:Z

# Or temporarily set permissive (NOT recommended for production)
sudo setenforce 0
```

#### 6. **Podman Socket Not Enabled**
**Problem:** Cockpit can't see containers
**Solution:**
```bash
systemctl --user enable --now podman.socket
```

### Runtime Gotchas

#### 7. **Caddy Certificate Challenges**
**Problem:** Let's Encrypt can't verify domain, HTTPS fails
**Causes:**
- Port 80/443 not forwarded (if not using Cloudflare Tunnel)
- DNS not pointing to your IP
- Cloudflare proxy enabled (use DNS challenge instead of HTTP)
**Solution:** Use Caddy DNS challenge with Cloudflare API token:
```
yourdomain.com {
    tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }
    reverse_proxy homarr:7575
}
```

#### 8. **Authelia Configuration Hell**
**Problem:** Authelia syntax errors cause service to crash-loop
**Solution:**
- Validate YAML syntax carefully (indentation matters!)
- Start with minimal config, add features incrementally
- Check logs: `journalctl --user -u authelia.service -f`
- Use Authelia's example configs as base

#### 9. **Prometheus Scrape Failures**
**Problem:** Prometheus can't reach targets on `homelab` network
**Cause:** Prometheus not on same network, container name resolution fails
**Solution:** Ensure Prometheus Quadlet includes:
```ini
Network=homelab.network
```

#### 10. **Backup Timer Not Firing**
**Problem:** Migrated backup to Quadlet timer, but it never runs
**Cause:** Timers require both .timer and .service files, Quadlet doesn't auto-generate timers
**Solution:** Keep backup as separate systemd timer, not Quadlet:
```bash
# Create timer manually
~/.config/systemd/user/backup-minecraft.timer
~/.config/systemd/user/backup-minecraft.service

systemctl --user enable --now backup-minecraft.timer
```

#### 11. **Discord Webhook Rate Limits**
**Problem:** Too many notifications, Discord returns 429 Too Many Requests
**Limits:** 30 requests per 60 seconds per webhook
**Solution:**
- Deduplicate alerts (don't send same alert repeatedly)
- Use different webhooks for different alert types
- Batch notifications (send summary every 5 minutes instead of real-time)

#### 12. **Uptime Kuma False Positives**
**Problem:** Uptime Kuma marks service as down, but it's actually up
**Causes:**
- Timeout too short (service slow to respond)
- Check interval too frequent (service rate-limiting checks)
- Network blip
**Solution:**
- Increase timeout from default 48s to 60s+
- Increase retry count from 1 to 3
- Set "Upside Down Mode" if checking for expected failure

#### 13. **Cloudflare Tunnel Breaking Minecraft**
**Problem:** Minecraft requires UDP, Cloudflare Tunnel only supports TCP/HTTP
**Solution:**
- Keep PlayIt.gg for Minecraft
- OR use Cloudflare Spectrum (paid feature, $5/month)
- OR use traditional port forwarding for Minecraft only

#### 14. **Grafana Datasource Connection Refused**
**Problem:** Grafana can't connect to Prometheus
**Cause:** Using `localhost:2020`, but containers don't share localhost
**Solution:** Use container name: `http://prometheus:9090`

#### 15. **Affine Database Corruption**
**Problem:** Affine won't start, database errors in logs
**Cause:** Using SQLite (default), container crashed during write
**Prevention:**
- Use PostgreSQL for multi-user setups
- Ensure graceful shutdowns (`systemctl --user stop affine`)
- Backup Affine volume regularly

### Security Gotchas

#### 16. **Exposed Admin Interfaces**
**Risk:** Cockpit, Grafana, Uptime Kuma exposed to internet without auth
**Solution:**
- Put all admin tools behind Authelia
- OR restrict to Tailscale network only
- OR use Cloudflare Access (zero-trust proxy)

#### 17. **Weak Authelia Passwords**
**Risk:** Users choose weak passwords, SSO becomes weak link
**Solution:**
- Enable password policies in Authelia:
  ```yaml
  password_policy:
    standard:
      enabled: true
      min_length: 12
      require_uppercase: true
      require_lowercase: true
      require_number: true
      require_special: true
  ```
- Enforce 2FA for admin accounts

#### 18. **Container Escape Risk**
**Risk:** Malicious container gains root on host
**Mitigation:**
- Use rootless Podman (you already are ✅)
- Don't use `--privileged` flag
- Drop unnecessary capabilities
- Keep Podman updated

---

## Implementation Phases

### Phase 1: Foundation Setup (30 minutes)

**Goal:** Install Cockpit, create network, test basic Quadlet

**Tasks:**
1. Install Cockpit
   ```bash
   sudo dnf install -y cockpit cockpit-podman
   sudo systemctl enable --now cockpit.socket
   sudo firewall-cmd --permanent --add-service=cockpit
   sudo firewall-cmd --reload
   ```

2. Access Cockpit
   - Navigate to `https://<server-ip>:9090`
   - Login with your user account
   - Navigate to Podman section

3. Enable user lingering
   ```bash
   sudo loginctl enable-linger $USER
   ```

4. Create Quadlet directory structure
   ```bash
   mkdir -p ~/.config/containers/systemd/{networks,volumes,containers}
   ```

5. Create homelab network Quadlet
   ```bash
   cat > ~/.config/containers/systemd/networks/homelab.network <<'EOF'
   [Network]
   NetworkName=homelab
   Driver=bridge
   EOF
   ```

6. Test Quadlet with simple container
   ```bash
   cat > ~/.config/containers/systemd/containers/hello.container <<'EOF'
   [Container]
   Image=docker.io/library/hello-world:latest
   Network=homelab.network
   EOF

   systemctl --user daemon-reload
   systemctl --user start hello.service
   systemctl --user status hello.service
   ```

7. Verify in Cockpit (should see hello container with "service" badge)

8. Clean up test
   ```bash
   systemctl --user stop hello.service
   rm ~/.config/containers/systemd/containers/hello.container
   systemctl --user daemon-reload
   ```

**Validation:**
- ✅ Cockpit accessible at port 9090
- ✅ Can see Podman containers in Cockpit
- ✅ Test Quadlet container starts successfully
- ✅ Network created and visible

---

### Phase 2: Migrate Existing Services (1-2 hours)

**Goal:** Convert Minecraft, Prometheus, Grafana to Quadlets

#### 2.1: Backup Current State
```bash
mkdir -p ~/homelab-migration-backup
cp -r ~/.config/systemd/user ~/homelab-migration-backup/systemd-old
tar -czf ~/homelab-migration-backup/applications-backup.tar.gz ~/applications
```

#### 2.2: Migrate Prometheus

**Tasks:**
1. Create Prometheus Quadlet (see [Example Quadlet Files](#example-quadlet-files))
2. Reload systemd: `systemctl --user daemon-reload`
3. Stop old service: `systemctl --user stop startup-prometheus.service`
4. Remove old container: `podman stop prometheus && podman rm prometheus`
5. Start new service: `systemctl --user enable --now prometheus.service`
6. Verify: Check Cockpit, check `http://<server-ip>:2020`

#### 2.3: Migrate Grafana

**Tasks:**
1. Create Grafana Quadlet
2. Update Prometheus datasource URL to `http://prometheus:9090`
3. Stop old service
4. Start new service
5. Verify: Login to Grafana, check dashboards work

#### 2.4: Migrate Minecraft (Most Complex)

**Considerations:**
- Keep Discord webhook notifications
- Keep Prometheus exporter
- Keep PlayIt.gg tunnel (or replace with Cloudflare Tunnel)
- Simplify: Combine startup script into Quadlet

**Tasks:**
1. Create Minecraft Quadlet
2. For PlayIt.gg tunnel: Keep as separate service OR run in same pod
3. Stop old service
4. Start new service
5. Test: Connect to Minecraft server, verify players can join

**Option A:** Run PlayIt in same pod
```bash
# Create pod Quadlet instead of container
cat > ~/.config/containers/systemd/pods/minecraft.pod <<'EOF'
[Pod]
PodName=minecraft-pod
Network=homelab.network
PublishPort=25565:25565
PublishPort=19565:19565
EOF

# Minecraft container in pod
cat > ~/.config/containers/systemd/containers/minecraft-server.container <<'EOF'
[Container]
Image=itzg/minecraft-server:java11
Pod=minecraft.pod
# ... other settings
EOF

# PlayIt tunnel in same pod
cat > ~/.config/containers/systemd/containers/playit-tunnel.container <<'EOF'
[Container]
Image=alpine:latest
Pod=minecraft.pod
Volume=%h/applications/minecraft/playit-linux-amd64:/playit:ro
Exec=/playit
EOF
```

**Option B:** Keep PlayIt as systemd service (simpler for migration)

#### 2.5: Migrate Backup Script

**Decision Point:** Keep as systemd timer OR convert to Quadlet?

**Recommendation:** Keep as systemd timer (simpler, works fine)

Update paths if needed:
```bash
# Edit backup_minecraft_server.sh to use new volume paths if changed
# Ensure Discord webhook still works
```

**Validation:**
- ✅ Prometheus accessible and scraping Minecraft
- ✅ Grafana dashboards working
- ✅ Minecraft server accessible, players can join
- ✅ Backups still running on schedule
- ✅ All visible in Cockpit with "service" badges

---

### Phase 3: Reverse Proxy & Security (1 hour)

**Goal:** Deploy Caddy, Authelia, Cloudflare DDNS

#### 3.1: Set Up Cloudflare DNS

**Tasks:**
1. Register domain or use existing
2. Transfer DNS to Cloudflare (free)
3. Add A record pointing to your public IP (if using port forwarding)
4. OR set up Cloudflare Tunnel:
   ```bash
   # Create tunnel in Cloudflare dashboard
   # Get tunnel token

   # Create cloudflared Quadlet
   cat > ~/.config/containers/systemd/containers/cloudflared.container <<'EOF'
   [Container]
   Image=docker.io/cloudflare/cloudflared:latest
   Exec=tunnel --no-autoupdate run --token <YOUR_TOKEN>

   [Service]
   Restart=always

   [Install]
   WantedBy=default.target
   EOF
   ```

#### 3.2: Deploy Caddy

**Tasks:**
1. Create Caddyfile (see examples below)
2. Create Caddy Quadlet
3. Start service
4. Verify: `curl https://yourdomain.com` returns 404 (normal, no route defined yet)

**Basic Caddyfile:**
```caddyfile
# ~/applications/caddy/Caddyfile

{
    email your@email.com  # For Let's Encrypt
    admin off              # Disable admin API
}

# Example: Homarr dashboard
homarr.yourdomain.com {
    reverse_proxy homarr:7575
}

# Add more services as you deploy them
```

#### 3.3: Deploy Authelia

**Tasks:**
1. Create Authelia config (complex, use template)
2. Create Authelia Quadlet
3. Start service
4. Create first user (via CLI or file)

**Minimal Authelia config:**
```yaml
# ~/applications/authelia/configuration.yml
server:
  address: 'tcp://0.0.0.0:9091'

log:
  level: 'info'

authentication_backend:
  file:
    path: '/config/users_database.yml'

access_control:
  default_policy: 'deny'
  rules:
    - domain: '*.yourdomain.com'
      policy: 'one_factor'  # Require login

session:
  secret: 'CHANGE_THIS_TO_RANDOM_STRING'
  domain: 'yourdomain.com'

storage:
  local:
    path: '/config/db.sqlite3'

notifier:
  filesystem:
    filename: '/config/notification.txt'
```

**Create user:**
```bash
# Install authelia CLI or use Docker
podman run --rm -v ~/applications/authelia:/config authelia/authelia:latest \
  authelia crypto hash generate argon2 --password 'YourPasswordHere'

# Add to ~/applications/authelia/users_database.yml:
users:
  yourusername:
    displayname: "Your Name"
    password: "<hash from above>"
    email: your@email.com
    groups:
      - admins
```

#### 3.4: Integrate Caddy + Authelia

**Update Caddyfile:**
```caddyfile
auth.yourdomain.com {
    reverse_proxy authelia:9091
}

homarr.yourdomain.com {
    forward_auth authelia:9091 {
        uri /api/verify?rd=https://auth.yourdomain.com
        copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
    }
    reverse_proxy homarr:7575
}
```

**Validation:**
- ✅ Visit `https://homarr.yourdomain.com` → redirected to Authelia login
- ✅ Login works → redirected back to Homarr
- ✅ HTTPS works (green padlock)

---

### Phase 4: Deploy New Applications (1 hour)

**Goal:** Deploy Uptime Kuma, Homarr, Affine

#### 4.1: Deploy Uptime Kuma

**Tasks:**
1. Create Uptime Kuma Quadlet (see examples)
2. Start service
3. Access UI: `https://uptime.yourdomain.com`
4. Create admin account
5. Configure Discord webhook notification:
   - Settings → Notifications → Add → Discord
   - Paste webhook URL
   - Test notification
6. Add monitors:
   - Minecraft: TCP check on port 25565
   - Caddy: HTTPS check on your domain
   - Grafana: HTTPS check
   - Each service you deploy

#### 4.2: Deploy Homarr

**Tasks:**
1. Create Homarr Quadlet
2. Start service
3. Add to Caddyfile with Authelia
4. Access: `https://homarr.yourdomain.com`
5. Configure dashboard:
   - Add bookmarks for each service
   - Add widgets (weather, calendar, etc.)
   - Configure Docker integration (point to Podman socket)

#### 4.3: Deploy Affine

**Tasks:**
1. Decide: SQLite (simple) or PostgreSQL (robust)?
2. If PostgreSQL, deploy postgres container first
3. Create Affine Quadlet
4. Start service
5. Add to Caddyfile with Authelia
6. Access: `https://docs.yourdomain.com`
7. Create workspace

**Validation:**
- ✅ All services accessible via HTTPS
- ✅ Authelia login required
- ✅ Uptime Kuma monitoring all services
- ✅ Discord notifications working

---

### Phase 5: Monitoring & Integration (1 hour)

**Goal:** Complete monitoring stack, finalize Discord integration

#### 5.1: Update Prometheus Scrape Targets

**Edit prometheus.yml:**
```yaml
scrape_configs:
  - job_name: 'minecraft'
    static_configs:
      - targets: ['minecraft-papa:19565']

  - job_name: 'uptime-kuma'
    static_configs:
      - targets: ['uptime-kuma:3001']
    metrics_path: '/metrics'
    basic_auth:
      username: 'your-api-key-username'
      password: 'your-api-key-password'

  - job_name: 'caddy'
    static_configs:
      - targets: ['caddy:2019']

  # Optional: Host metrics
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
```

Restart Prometheus: `systemctl --user restart prometheus.service`

#### 5.2: Import Grafana Dashboards

**Tasks:**
1. Login to Grafana
2. Import community dashboards:
   - 18278: Uptime Kuma Metrics
   - 1860: Node Exporter Full (if you deployed node-exporter)
   - 14282: Caddy Exporter
3. Create custom dashboard for Minecraft (using existing metrics)

#### 5.3: Deploy Prometheus Alertmanager (Optional)

**Tasks:**
1. Create Alertmanager Quadlet
2. Configure Discord webhook receiver
3. Define alert rules (high CPU, disk space, service down)
4. Test alerts

**Example alert rule:**
```yaml
# alerts.yml
groups:
  - name: system
    interval: 1m
    rules:
      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) > 0.9
        for: 5m
        annotations:
          summary: "Memory usage above 90%"
        labels:
          severity: warning
```

#### 5.4: Configure Minecraft → Discord Integration

**Option A:** Install DiscordSRV mod
1. Download DiscordSRV jar
2. Add to Minecraft mods folder
3. Configure Discord bot token
4. Restart Minecraft

**Option B:** Parse logs with script
```bash
#!/bin/bash
# watch-minecraft-logs.sh
tail -F ~/applications/minecraft/data/logs/latest.log | while read line; do
    if echo "$line" | grep -q "joined the game"; then
        player=$(echo "$line" | sed -n 's/.*\(.*\) joined the game/\1/p')
        send_discord_alert "$WEBHOOK" "🎮 Player Joined" "$player joined Pixelmon server" 3447003
    fi
done
```

Run as systemd service.

#### 5.5: Test All Discord Integrations

**Checklist:**
- [ ] Uptime Kuma sends alert when service goes down
- [ ] Backup script sends success/failure notifications
- [ ] Prometheus Alertmanager sends system alerts (if deployed)
- [ ] Minecraft sends player join/leave events (if configured)
- [ ] Grafana sends dashboard alerts (if configured)

**Validation:**
- ✅ All services monitored in Uptime Kuma
- ✅ Prometheus scraping all targets
- ✅ Grafana dashboards populated
- ✅ Discord notifications working from all sources

---

## Example Quadlet Files

### Network

```ini
# ~/.config/containers/systemd/networks/homelab.network
[Network]
NetworkName=homelab
Driver=bridge
IPv6=false

[Install]
WantedBy=default.target
```

### Volumes

```ini
# ~/.config/containers/systemd/volumes/minecraft-data.volume
[Volume]
VolumeName=minecraft-data

# ~/.config/containers/systemd/volumes/prometheus-data.volume
[Volume]
VolumeName=prometheus-data

# ~/.config/containers/systemd/volumes/grafana-data.volume
[Volume]
VolumeName=grafana-data

# ~/.config/containers/systemd/volumes/uptime-kuma-data.volume
[Volume]
VolumeName=uptime-kuma-data

# ~/.config/containers/systemd/volumes/authelia-data.volume
[Volume]
VolumeName=authelia-data

# ~/.config/containers/systemd/volumes/caddy-data.volume
[Volume]
VolumeName=caddy-data

# ~/.config/containers/systemd/volumes/affine-data.volume
[Volume]
VolumeName=affine-data
```

### Minecraft Server

```ini
# ~/.config/containers/systemd/containers/minecraft.container
[Unit]
Description=Minecraft Pixelmon Server
After=prometheus.service

[Container]
Image=docker.io/itzg/minecraft-server:java11
ContainerName=minecraft-papa
AutoUpdate=registry

# Network
Network=homelab.network
PublishPort=25565:25565
PublishPort=19565:19565

# Volumes (use existing data directory)
Volume=%h/applications/minecraft/data:/data:Z
Volume=%h/applications/minecraft/config:/config:Z

# Environment Variables
Environment=EULA=TRUE
Environment=TYPE=FORGE
Environment=VERSION=1.16.5
Environment=MEMORY=4G
Environment=INIT_MEMORY=2G
Environment=FORGE_VERSION=36.2.39
Environment=ENABLE_ROLLING_LOGS=true

# Prometheus Exporter
Environment=ENABLE_AUTOPAUSE=false
Environment=ENABLE_WHITELIST=false

# Resource Limits
MemoryMax=5G
MemoryHigh=4.5G

[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=default.target
```

### Prometheus

```ini
# ~/.config/containers/systemd/containers/prometheus.container
[Unit]
Description=Prometheus Metrics Collector
After=network-online.target

[Container]
Image=docker.io/bitnami/prometheus:latest
ContainerName=prometheus
AutoUpdate=registry

Network=homelab.network
PublishPort=2020:9090

Volume=%h/applications/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:Z,ro
Volume=prometheus-data.volume:/prometheus:Z

Environment=TZ=America/New_York

[Service]
Restart=always

[Install]
WantedBy=default.target
```

### Grafana

```ini
# ~/.config/containers/systemd/containers/grafana.container
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
Environment=GF_SECURITY_ADMIN_PASSWORD=changeme
Environment=GF_INSTALL_PLUGINS=

User=0:0

[Service]
Restart=always

[Install]
WantedBy=default.target
```

### Uptime Kuma

```ini
# ~/.config/containers/systemd/containers/uptime-kuma.container
[Unit]
Description=Uptime Kuma Monitoring
After=network-online.target

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

### Caddy

```ini
# ~/.config/containers/systemd/containers/caddy.container
[Unit]
Description=Caddy Reverse Proxy
After=network-online.target

[Container]
Image=docker.io/library/caddy:latest
ContainerName=caddy
AutoUpdate=registry

Network=homelab.network
PublishPort=80:80
PublishPort=443:443
PublishPort=2019:2019

Volume=%h/applications/caddy/Caddyfile:/etc/caddy/Caddyfile:Z,ro
Volume=caddy-data.volume:/data:Z
Volume=caddy-data.volume:/config:Z

[Service]
Restart=always

[Install]
WantedBy=default.target
```

### Authelia

```ini
# ~/.config/containers/systemd/containers/authelia.container
[Unit]
Description=Authelia SSO
After=network-online.target

[Container]
Image=docker.io/authelia/authelia:latest
ContainerName=authelia
AutoUpdate=registry

Network=homelab.network
PublishPort=9091:9091

Volume=%h/applications/authelia:/config:Z

Environment=TZ=America/New_York
Environment=AUTHELIA_JWT_SECRET_FILE=/config/secrets/jwt_secret
Environment=AUTHELIA_SESSION_SECRET_FILE=/config/secrets/session_secret
Environment=AUTHELIA_STORAGE_ENCRYPTION_KEY_FILE=/config/secrets/storage_key

[Service]
Restart=always

[Install]
WantedBy=default.target
```

### Homarr

```ini
# ~/.config/containers/systemd/containers/homarr.container
[Unit]
Description=Homarr Dashboard
After=network-online.target

[Container]
Image=ghcr.io/ajnart/homarr:latest
ContainerName=homarr
AutoUpdate=registry

Network=homelab.network
PublishPort=7575:7575

Volume=%h/applications/homarr/configs:/app/data/configs:Z
Volume=%h/applications/homarr/icons:/app/public/icons:Z
Volume=%h/applications/homarr/data:/data:Z

# Optional: Podman socket for container status
Volume=/run/user/1000/podman/podman.sock:/var/run/docker.sock:Z,ro

[Service]
Restart=always

[Install]
WantedBy=default.target
```

### Affine

```ini
# ~/.config/containers/systemd/containers/affine.container
[Unit]
Description=Affine Productivity Suite
After=network-online.target

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

### Cloudflare Tunnel (Optional)

```ini
# ~/.config/containers/systemd/containers/cloudflared.container
[Unit]
Description=Cloudflare Tunnel
After=network-online.target

[Container]
Image=docker.io/cloudflare/cloudflared:latest
ContainerName=cloudflared
AutoUpdate=registry

Network=host

Exec=tunnel --no-autoupdate run --token YOUR_TUNNEL_TOKEN_HERE

[Service]
Restart=always

[Install]
WantedBy=default.target
```

---

## Reference Commands

### Quadlet Management

```bash
# Reload systemd after adding/editing Quadlet files
systemctl --user daemon-reload

# Enable and start service
systemctl --user enable --now prometheus.service

# Check service status
systemctl --user status prometheus.service

# View logs
journalctl --user -u prometheus.service -f

# Restart service
systemctl --user restart prometheus.service

# Stop service
systemctl --user stop prometheus.service

# Disable service (won't start on boot)
systemctl --user disable prometheus.service

# List all Quadlet-managed services
systemctl --user list-units 'quadlet-*' --all
```

### Podman Commands

```bash
# List running containers
podman ps

# List all containers (including stopped)
podman ps -a

# View container logs
podman logs -f minecraft-papa

# Execute command in container
podman exec -it minecraft-papa bash

# Inspect container
podman inspect minecraft-papa

# View container resource usage
podman stats

# List volumes
podman volume ls

# Export volume for backup
podman volume export systemd-minecraft-data -o /tmp/minecraft-backup.tar

# Import volume from backup
podman volume import systemd-minecraft-data /tmp/minecraft-backup.tar

# List networks
podman network ls

# Inspect network
podman network inspect homelab

# Remove unused containers, images, volumes
podman system prune -a --volumes
```

### Auto-Update

```bash
# Manually trigger auto-update for containers with AutoUpdate=registry
podman auto-update

# Check which containers would be updated
podman auto-update --dry-run

# Set up auto-update timer (run daily at 3 AM)
cat > ~/.config/systemd/user/podman-auto-update.timer <<'EOF'
[Unit]
Description=Podman Auto-Update Timer

[Timer]
OnCalendar=daily
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl --user enable --now podman-auto-update.timer
```

### Cockpit

```bash
# Install Cockpit
sudo dnf install -y cockpit cockpit-podman

# Enable Cockpit
sudo systemctl enable --now cockpit.socket

# Check Cockpit status
sudo systemctl status cockpit.socket

# Access Cockpit
# Navigate to: https://<server-ip>:9090
```

### Firewall (firewalld)

```bash
# List active firewall rules
sudo firewall-cmd --list-all

# Open port
sudo firewall-cmd --permanent --add-port=25565/tcp
sudo firewall-cmd --reload

# Remove port
sudo firewall-cmd --permanent --remove-port=25565/tcp
sudo firewall-cmd --reload

# Add service
sudo firewall-cmd --permanent --add-service=cockpit
sudo firewall-cmd --reload
```

### Debugging

```bash
# Check SELinux denials
sudo ausearch -m avc -ts recent

# Check if user lingering is enabled
loginctl show-user $USER | grep Linger

# Enable user lingering
sudo loginctl enable-linger $USER

# View all user services
systemctl --user list-units --type=service

# Check Podman socket
systemctl --user status podman.socket

# Enable Podman socket (needed for Cockpit)
systemctl --user enable --now podman.socket
```

### Backup

```bash
# Backup all Quadlet files
tar -czf ~/homelab-quadlet-backup-$(date +%Y%m%d).tar.gz \
    ~/.config/containers/systemd/

# Backup all volumes
for vol in $(podman volume ls --format '{{.Name}}'); do
    podman volume export $vol -o ~/backups/${vol}-$(date +%Y%m%d).tar
done

# Backup application configs
tar -czf ~/homelab-configs-backup-$(date +%Y%m%d).tar.gz \
    ~/applications/

# Full system backup (to NAS)
rsync -avz --delete \
    ~/.config/containers/systemd/ \
    ~/applications/ \
    $USER@nas:/backups/homelab/
```

---

## Final Notes

### Success Criteria

You'll know the migration is successful when:
- ✅ All services accessible via `https://service.yourdomain.com`
- ✅ Authelia login required for all services
- ✅ Uptime Kuma monitoring all services, sending Discord alerts
- ✅ Grafana dashboards showing metrics from Prometheus
- ✅ Minecraft server accessible, backups running
- ✅ Cockpit shows all Quadlet containers with "service" badge
- ✅ Can start/stop services from Cockpit or CLI
- ✅ Services auto-start on system boot
- ✅ Discord notifications working from multiple sources

### Maintenance Tasks

**Weekly:**
- Check Uptime Kuma for any downtime events
- Review Grafana dashboards for anomalies
- Test backups (restore to temp location)

**Monthly:**
- Run `podman auto-update` to pull latest images
- Review Authelia logs for failed login attempts
- Check disk usage: `df -h`
- Review systemd journal for errors: `journalctl --user -p err -S -7d`

**Quarterly:**
- Update server OS packages: `sudo dnf upgrade`
- Review and update firewall rules
- Test disaster recovery procedure
- Audit user accounts in Authelia

### Next Steps After Migration

1. **Documentation:** Document your setup (this file is a start!)
2. **Testing:** Test failure scenarios (what if container crashes?)
3. **Monitoring:** Tune alert thresholds to reduce noise
4. **Security:** Enable 2FA in Authelia for admin accounts
5. **Expansion:** Add more services as needed (see Suggestions section)
6. **Learning:** Explore Grafana query language, Prometheus alerting
7. **Community:** Share your setup, learn from others (r/selfhosted, r/homelab)

### Resources

- **Podman Quadlet Docs:** https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html
- **Cockpit Project:** https://cockpit-project.org/
- **Caddy Docs:** https://caddyserver.com/docs/
- **Authelia Docs:** https://www.authelia.com/overview/prologue/introduction/
- **Uptime Kuma:** https://github.com/louislam/uptime-kuma
- **Awesome Selfhosted:** https://github.com/awesome-selfhosted/awesome-selfhosted
- **r/selfhosted:** https://reddit.com/r/selfhosted
- **r/homelab:** https://reddit.com/r/homelab

---

**End of Homelab Architecture Plan**

*Last Updated: 2026-05-02*
