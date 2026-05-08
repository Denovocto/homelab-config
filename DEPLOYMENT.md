# Deployment Guide

This document explains how to deploy the homelab configuration from this repository to your target server.

## Path Configuration Strategy

This repository uses a **hybrid approach** combining fixed default paths with configurable overrides:

### Option 1: Default Path (Recommended)

The simplest deployment uses the default path `~/homelab-config` on the target server:

```bash
# On target server
git clone <your-repo-url> ~/homelab-config
cd ~/homelab-config
./scripts/bootstrap.sh
```

All Quadlet files are configured to use `%h/homelab-config/...` paths, where `%h` expands to the user's home directory at runtime.

### Option 2: Custom Path (Advanced)

If you need to deploy to a different location, you can override the path:

```bash
# Clone to custom location
git clone <your-repo-url> /opt/homelab
cd /opt/homelab

# Configure custom path (choose one method):

# Method A: User-specific config
echo 'export HOMELAB_REPO_DIR="/opt/homelab"' > ~/.config/homelab.env

# Method B: System-wide config
echo 'export HOMELAB_REPO_DIR="/opt/homelab"' | sudo tee /etc/homelab.env

# Method C: One-time environment variable
export HOMELAB_REPO_DIR="/opt/homelab"
./scripts/bootstrap.sh
```

**Important:** When using a custom path, you must update all Quadlet files manually to reference your custom path instead of `%h/homelab-config`.

## How It Works

### Scripts (`bootstrap.sh`, `deploy.sh`)

Scripts check for configuration in this order:
1. `~/.config/homelab.env` (user config)
2. `/etc/homelab.env` (system config)
3. `$HOMELAB_REPO_DIR` environment variable
4. **Default:** `~/homelab-config` if none of the above exist

### Quadlet Files (Container Definitions)

Quadlet files use **systemd path expansion**:
- `%h` expands to the user's home directory
- `%h/homelab-config` → `/home/username/homelab-config` at runtime

**Note:** Quadlet files do NOT read environment variables or config files. They use fixed paths with systemd expansion only.

## Recommended Deployment Workflow

### On Target Server

```bash
# 1. Clone repository to default location
git clone <your-repo-url> ~/homelab-config
cd ~/homelab-config

# 2. Run bootstrap (sets up directories, checks prerequisites)
./scripts/bootstrap.sh

# 3. Create secrets (see docs/SECRETS_SETUP.md)
openssl rand -hex 32 | podman secret create authelia-jwt-secret -
openssl rand -hex 32 | podman secret create authelia-session-secret -
openssl rand -hex 32 | podman secret create authelia-storage-key -
echo "your-password" | podman secret create grafana-admin-password -

# 4. Configure Authelia users
cp configs/authelia/users_database.yml.template configs/authelia/users_database.yml
# Edit and add users with password hashes
nano configs/authelia/users_database.yml

# 5. Update domain in Caddyfile
nano configs/caddy/Caddyfile
# Replace 'yourdomain.com' with your actual domain

# 6. Deploy Quadlets
./scripts/deploy.sh

# 7. Enable and start services
./scripts/enable-all-services.sh

# 8. Verify services are running
systemctl --user status minecraft.service
systemctl --user status prometheus.service
systemctl --user status grafana.service
```

## Path Reference

### Current Development Directory
```
~/Documents/projects/minecraft-server-tools/  # Your current dev location
```

### Target Server Deployment (Default)
```
~/homelab-config/  # Recommended target location
├── quadlets/      # Copied to ~/.config/containers/systemd/
├── configs/       # Referenced directly by containers
├── scripts/       # Used for deployment
└── docs/          # Documentation
```

### Systemd Runtime Paths
```
~/.config/containers/systemd/  # Quadlet definitions
  ├── networks/
  ├── volumes/
  └── containers/

~/.config/systemd/user/        # Systemd timers
  └── restic-backup.timer
```

## Prometheus Configuration

The Prometheus container is configured to:

1. **Load config** from `~/homelab-config/configs/prometheus/prometheus.yml`
2. **Load environment** from `~/homelab-config/configs/prometheus/prometheus.env`
3. **Store data** in a Podman volume `prometheus-data`
4. **Scrape targets** defined in prometheus.yml:
   - `minecraft-papa:19565` - Minecraft metrics
   - `localhost:9090` - Prometheus self-monitoring

### prometheus.yml Key Points

```yaml
global:
  scrape_interval: 30s

scrape_configs:
  - job_name: "minecraft"
    static_configs:
      - targets: ["minecraft-papa:19565"]
        labels:
          server_name: "minecraft-papa"
```

The container name `minecraft-papa` is used for DNS resolution within the `homelab` Podman network.

## Troubleshooting

### Error: Repository not found at ~/homelab-config

**Cause:** Repository not cloned to expected location.

**Solution:**
```bash
# Option A: Clone to default location
git clone <your-repo-url> ~/homelab-config

# Option B: Configure custom path
echo 'export HOMELAB_REPO_DIR="/your/actual/path"' > ~/.config/homelab.env
```

### Error: Volume paths not found in container

**Cause:** Quadlet file references path that doesn't exist.

**Solution:** Ensure repository is at `~/homelab-config` or update Quadlet files to match your custom path.

### Services fail to start after deployment

**Check logs:**
```bash
journalctl --user -u prometheus.service -n 50
```

**Common issues:**
- Missing secrets: `podman secret ls`
- Wrong paths: Verify `~/homelab-config` exists
- Network not ready: `podman network ls | grep homelab`

## Migration from Development to Production

If you're currently developing in `~/Documents/projects/minecraft-server-tools`:

```bash
# On production server
git clone <your-repo-url> ~/homelab-config

# Or create symlink (temporary workaround)
ln -s ~/Documents/projects/minecraft-server-tools ~/homelab-config
```

## See Also

- [SECRETS_SETUP.md](docs/SECRETS_SETUP.md) - Secret management
- [IMPLEMENTATION_GUIDE.md](docs/IMPLEMENTATION_GUIDE.md) - Step-by-step guide
- [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) - Common issues
