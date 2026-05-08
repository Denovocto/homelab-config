# Custom Instructions for This Repository

When working in this repository, follow these principles and conventions:

## Core Principles

### 1. GitOps First
- **Prefer declarative over imperative:** Use Podman Quadlets (systemd unit files) instead of bash scripts for service management
- **Version everything:** All configuration changes should be made in git, never directly on the server
- **Single source of truth:** The git repository is the definitive configuration; server state derives from it

### 2. Path Convention
- **Default deployment path:** `~/homelab-config` on target server
- **Path override:** Users can set `HOMELAB_REPO_DIR` environment variable via:
  - `~/.config/homelab.env`
  - `/etc/homelab.env`
  - Direct environment variable
- **In Quadlet files:** Always use `%h/homelab-config/...` for paths
  - `%h` = systemd expansion for user home directory
  - Example: `EnvironmentFile=%h/homelab-config/configs/service/service.env`
- **In bash scripts:** Use `${HOMELAB_REPO_DIR:-$HOME/homelab-config}` pattern

### 3. Security Awareness
- **NEVER create actual secrets in git:** Only create templates (`.template` or `.example` suffix)
- **Always use Podman secrets:** For sensitive data (passwords, API keys, tokens)
  - Create: `podman secret create secret-name -`
  - Reference in Quadlet: `Secret=secret-name,type=env,target=ENV_VAR`
- **Protect environment files:** Files ending in `.env` should never contain secrets, only non-sensitive config
- **Never read or suggest reading:**
  - `secrets/` directory
  - `*.env` files (except `.env.template` or `.env.example`)
  - `*.key`, `*.secret` files

### 4. Systemd Patterns
- **Always specify dependencies:**
  ```ini
  [Unit]
  After=network-online.target homelab-network.service
  ```
- **Use proper service ordering:**
  - Network services: `After=network-online.target`
  - Homelab services: `After=homelab-network.service`
  - Dependent services: `After=other-service.service`
- **Auto-start configuration:**
  ```ini
  [Install]
  WantedBy=default.target
  ```
- **Use systemd path expansion:**
  - `%h` = home directory
  - `%t` = runtime directory
  - `%S` = state directory

### 5. Minimal Bash Scripting
- **Avoid complex bash scripts:** Bash scripts should only be used for:
  - Deployment (copying Quadlet files to systemd directories)
  - Bootstrap (one-time initialization)
  - Simple automation (triggering existing systemd services)
- **Service management via systemd:** Never create bash scripts to start/stop/restart services
  - Use: `systemctl --user {start|stop|restart} service.service`
  - Not: Custom bash scripts with `podman start/stop`
- **Let systemd handle orchestration:** Dependencies, restart policies, resource limits - all in Quadlet files

### 6. Lean Services
- **Always set resource limits:**
  ```ini
  [Container]
  MemoryMax=2G      # Hard limit (OOM kill if exceeded)
  MemoryHigh=1.5G   # Soft limit (throttle if exceeded)
  ```
- **Keep containers efficient:**
  - Use official images when possible
  - Avoid running unnecessary processes
  - Set appropriate memory limits based on service needs
- **Enable auto-updates:**
  ```ini
  [Container]
  AutoUpdate=registry
  ```

## Specific Conventions

### Quadlet File Structure
```ini
[Unit]
Description=Clear service description
After=network-online.target homelab-network.service

[Container]
Image=docker.io/user/image:tag
ContainerName=descriptive-name
AutoUpdate=registry
Network=homelab.network
Volume=%h/homelab-config/configs/service:/config:Z
EnvironmentFile=%h/homelab-config/configs/service/service.env
MemoryMax=2G
MemoryHigh=1.5G

[Service]
Restart=always

[Install]
WantedBy=default.target
```

### Volume Mounts
- **Always use `:Z` suffix:** For SELinux labeling (required on Fedora)
- **Use `:ro` for read-only:** Config files that shouldn't be modified
- **Example:**
  - `Volume=%h/homelab-config/configs/caddy/Caddyfile:/etc/caddy/Caddyfile:Z,ro`
  - `Volume=service-data.volume:/data:Z`

### Naming Conventions
- **Service names:** lowercase-with-hyphens (e.g., `uptime-kuma`, `authelia`)
- **Container names:** match service name or descriptive (e.g., `minecraft-papa`)
- **Volume names:** `{service-name}-data` (e.g., `grafana-data`, `prometheus-data`)
- **Network name:** `homelab` (generates `homelab-network.service`)

### Container Network
- **All services connect to:** `homelab.network`
- **DNS resolution:** Containers can reach each other by container name
  - Example: Prometheus scrapes `minecraft-papa:19565`
- **Publish ports only when needed:** For external access or monitoring

## When Suggesting Changes

### DO:
- Suggest edits to Quadlet files for service changes
- Recommend appropriate resource limits based on service type
- Explain systemd dependencies and ordering
- Provide deployment commands using existing scripts
- Reference specific files with `file_path:line_number` format
- Use the `/add-service` command for adding new services

### DON'T:
- Create complex bash scripts for service management
- Suggest storing secrets in git or environment files
- Omit resource limits (MemoryMax/MemoryHigh)
- Forget `:Z` suffix on volume mounts (causes SELinux issues)
- Ignore proper `After=` dependencies (causes race conditions)
- Suggest editing files directly on server (breaks GitOps)

## Common Workflows

### Adding a New Service
1. Use `/add-service` command for guided wizard
2. Create Quadlet in `quadlets/containers/phase{1,2}-*/`
3. Create config directory in `configs/service-name/`
4. Create environment file if needed
5. Create secrets if needed
6. Deploy: `./scripts/deploy.sh`
7. Enable: `systemctl --user enable --now service-name.service`

### Troubleshooting
1. Check service status: `systemctl --user status service.service`
2. View logs: `journalctl --user -u service.service -n 100`
3. Check container: `podman ps -a | grep container-name`
4. Verify secrets: `podman secret ls`
5. Verify network: `podman network ls | grep homelab`

### Deployment
1. Edit files in git repository
2. Run: `./scripts/deploy.sh`
3. Restart affected services
4. Verify with `systemctl --user status` and `journalctl`

## Priority Files for Context

When starting a conversation, consider reading these based on the task:
- `.claude/REPOSITORY_GUIDE.md` - Always read this first
- `README.md` - Project overview
- `DEPLOYMENT.md` - For deployment questions
- `docs/TROUBLESHOOTING.md` - For debugging issues
- Specific Quadlet files - For service-specific questions
- Specific config files - For configuration questions

Avoid reading unless necessary:
- Log files
- Backup files
- Secret files
- Large data files
