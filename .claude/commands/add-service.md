You are helping the user add a new containerized service to their homelab GitOps configuration.

## Guided Wizard Process

Follow these steps to guide the user through adding a new service:

### Step 1: Gather Service Information

Ask the user these questions using the AskUserQuestion tool:

1. **Service Phase:**
   - "Is this a critical service (Phase 1) or a secondary service (Phase 2)?"
   - Options:
     - Phase 1 (Critical): Essential services that must always run
     - Phase 2 (Secondary): Optional services for enhanced functionality

2. **Service Type:**
   - "What type of service are you adding?"
   - Options:
     - Web Application: HTTP service with reverse proxy integration
     - Generic Container: Any other containerized service

3. **Basic Service Details:**
   - Service name (lowercase, hyphen-separated, e.g., "uptime-kuma")
   - Container name (should match service name or have descriptive suffix)
   - Docker/Podman image (full image URL, e.g., "docker.io/user/image:tag")
   - Port mappings (if any, format: "host:container")

### Step 2: Generate Quadlet Template

Based on the service type, generate the appropriate Quadlet file:

#### For Web Applications:

```ini
[Unit]
Description={Service Description}
After=network-online.target homelab-network.service caddy.service

[Container]
Image={docker-image}
ContainerName={container-name}
AutoUpdate=registry

# Network
Network=homelab.network
# Optional: PublishPort=8080:8080  # If you need external access

# Volumes (add as needed)
# Volume={service-name}-data.volume:/data:Z
# Volume=%h/homelab-config/configs/{service-name}/{service-name}.conf:/etc/{service-name}/config.conf:Z,ro

# Environment configuration
EnvironmentFile=%h/homelab-config/configs/{service-name}/{service-name}.env

# Resource Limits (adjust based on service needs)
MemoryMax=2G
MemoryHigh=1.5G

[Service]
Restart=always

[Install]
WantedBy=default.target
```

#### For Generic Containers:

```ini
[Unit]
Description={Service Description}
After=network-online.target homelab-network.service

[Container]
Image={docker-image}
ContainerName={container-name}
AutoUpdate=registry

# Network
Network=homelab.network
# PublishPort={host-port}:{container-port}

# Volumes (add as needed)
# Volume={service-name}-data.volume:/data:Z

# Environment configuration
EnvironmentFile=%h/homelab-config/configs/{service-name}/{service-name}.env

# Resource Limits (adjust based on service needs)
MemoryMax=1G
MemoryHigh=800M

[Service]
Restart=always

[Install]
WantedBy=default.target
```

### Step 3: Create Configuration Structure

Guide the user to create:

1. **Quadlet file:**
   ```bash
   # Create file at:
   quadlets/containers/phase{1,2}-{critical,services}/{service-name}.container
   ```

2. **Config directory:**
   ```bash
   mkdir -p configs/{service-name}
   ```

3. **Environment file template:**
   ```bash
   # Create: configs/{service-name}/{service-name}.env
   # Add service-specific environment variables
   ```

### Step 4: Additional Components (Ask First)

Ask if the user needs:

1. **Persistent Volume:**
   - If yes, create volume definition at `quadlets/volumes/{service-name}-data.volume`
   ```ini
   [Volume]
   VolumeName={service-name}-data

   [Install]
   WantedBy=default.target
   ```

2. **Podman Secrets:**
   - If yes, guide user to create secrets:
   ```bash
   echo "secret-value" | podman secret create {service-name}-secret-name -
   ```
   - Add to Quadlet:
   ```ini
   Secret={service-name}-secret-name,type=env,target=ENV_VAR_NAME
   ```

3. **Caddy Integration (Web Apps Only):**
   - If yes, provide Caddyfile snippet:
   ```
   {service-name}.yourdomain.com {
       reverse_proxy {container-name}:8080

       forward_auth authelia:9091 {
           uri /api/verify?rd=https://auth.yourdomain.com
           copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
       }
   }
   ```

### Step 5: Deployment Instructions

Provide the deployment commands:

```bash
# 1. Deploy the new Quadlet
./scripts/deploy.sh

# 2. Reload systemd to recognize new service
systemctl --user daemon-reload

# 3. Enable and start the service
systemctl --user enable --now {service-name}.service

# 4. Verify service is running
systemctl --user status {service-name}.service

# 5. Check logs if needed
journalctl --user -u {service-name}.service -f
```

### Step 6: Verification Checklist

Provide this checklist:

- [ ] Service is running: `systemctl --user status {service-name}.service`
- [ ] No errors in logs: `journalctl --user -u {service-name}.service -n 50`
- [ ] Container is healthy: `podman ps | grep {container-name}`
- [ ] Network connectivity: `podman exec {container-name} ping -c 2 google.com`
- [ ] Service responds (if web): `curl http://localhost:{port}`

## Important Reminders

1. **Always use `%h/homelab-config` paths** in Quadlet files
2. **Set resource limits** (MemoryMax, MemoryHigh) to keep services lean
3. **Use proper dependencies** in `After=` directive
4. **Add `:Z` suffix** to volume mounts for SELinux
5. **Never commit secrets** to git - use podman secrets
6. **Follow naming conventions:**
   - Service names: lowercase-with-hyphens
   - Container names: match service name or descriptive
   - Volume names: {service-name}-data
   - Config paths: configs/{service-name}/

## Example Questions Flow

**Claude:** "Let's add a new service to your homelab! I'll ask you a few questions to generate the right configuration."

**[Ask Questions via AskUserQuestion tool]**

**Claude:** "Based on your answers, I'll create a {service-type} service named {service-name} in Phase {phase}."

**[Generate and show Quadlet template]**

**Claude:** "Now let me create the necessary files and directories for you..."

**[Use Write tool to create files]**

**Claude:** "Service configuration created! Here are the next steps to deploy it..."

**[Provide deployment commands]**
