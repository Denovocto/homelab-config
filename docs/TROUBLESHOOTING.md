# Troubleshooting Guide

Common issues and solutions for the homelab setup.

## Service Won't Start

### Check Service Status

```bash
systemctl --user status service-name.service
```

### View Logs

```bash
# View recent logs
journalctl --user -u service-name.service -n 50

# Follow logs in real-time
journalctl --user -u service-name.service -f

# View logs from specific time
journalctl --user -u service-name.service --since "1 hour ago"
```

### Common Issues

#### Missing Secret

**Error:** `secret not found: authelia-jwt-secret`

**Solution:**
```bash
# Create the missing secret
openssl rand -hex 32 | podman secret create authelia-jwt-secret -

# Restart the service
systemctl --user restart authelia.service
```

#### Network Not Found

**Error:** `network homelab not found`

**Solution:**
```bash
# Check if network exists
podman network ls

# If missing, start the network service
systemctl --user start homelab-network.service

# Verify
podman network ls | grep homelab

# Restart the failing service
systemctl --user restart service-name.service
```

#### Volume Not Found

**Error:** `volume minecraft-data not found`

**Solution:**
```bash
# Check if volume exists
podman volume ls

# If missing, create it (Quadlets should auto-create, but manual creation works too)
podman volume create minecraft-data

# Or start the volume service if using Quadlet volumes
systemctl --user start minecraft-data-volume.service

# Restart the failing service
systemctl --user restart minecraft.service
```

#### Port Already in Use

**Error:** `bind: address already in use`

**Solution:**
```bash
# Find what's using the port (example: port 25565)
sudo ss -tlnp | grep 25565

# Stop the conflicting service
systemctl --user stop other-service.service

# Or kill the process
sudo kill <PID>

# Start your service
systemctl --user start minecraft.service
```

## Networking Issues

### Can't Access Service from Internet

**Checklist:**

1. **Check firewall:**
   ```bash
   sudo firewall-cmd --list-all
   ```
   Should show ports 80, 443, 25565 open.

2. **Check router port forwarding:**
   - Log into router admin panel
   - Verify ports are forwarded to server's LAN IP
   - Verify server's LAN IP hasn't changed (use static IP or DHCP reservation)

3. **Check DNS:**
   ```bash
   # Verify DNS record points to your public IP
   dig yourdomain.com +short

   # Check your public IP
   curl ifconfig.me
   ```

4. **Check if service is listening:**
   ```bash
   # For Caddy (HTTP/HTTPS)
   sudo ss -tlnp | grep -E ':(80|443)'

   # For Minecraft
   sudo ss -tlnp | grep 25565
   ```

### Can't Access Service Locally

**Checklist:**

1. **Check if container is running:**
   ```bash
   podman ps | grep service-name
   ```

2. **Check container logs:**
   ```bash
   podman logs service-name
   ```

3. **Test connectivity:**
   ```bash
   # Test HTTP
   curl http://localhost:80

   # Test Minecraft
   nc -zv localhost 25565
   ```

4. **Check network connectivity:**
   ```bash
   # List containers on homelab network
   podman network inspect homelab
   ```

## Authelia Issues

### Can't Login

**Symptom:** Login page loads but credentials don't work.

**Solutions:**

1. **Check password hash:**
   ```bash
   # Verify users_database.yml exists
   ls -l configs/authelia/users_database.yml

   # Regenerate password hash
   podman run --rm authelia/authelia:latest \
     authelia crypto hash generate argon2 --password 'YourPassword'

   # Update users_database.yml with new hash
   # Restart Authelia
   systemctl --user restart authelia.service
   ```

2. **Check Authelia logs:**
   ```bash
   journalctl --user -u authelia.service -f
   ```

3. **Verify secrets are set:**
   ```bash
   podman secret ls | grep authelia
   ```

### Redirect Loop

**Symptom:** Browser keeps redirecting between app and auth page.

**Solutions:**

1. **Check Caddy configuration:**
   ```bash
   # Verify forward_auth settings in Caddyfile
   cat configs/caddy/Caddyfile

   # Restart Caddy
   systemctl --user restart caddy.service
   ```

2. **Check domain configuration:**
   - Ensure `session.domain` in Authelia config matches your domain
   - Ensure all subdomains use the same root domain

3. **Clear browser cookies:**
   - Clear cookies for your domain
   - Try incognito/private browsing

## Caddy Issues

### HTTPS Certificate Not Working

**Symptom:** Browser shows "Not Secure" or certificate errors.

**Solutions:**

1. **Check Caddy logs:**
   ```bash
   journalctl --user -u caddy.service -f
   ```

2. **Verify DNS:**
   ```bash
   # DNS must point to your server for ACME challenge
   dig yourdomain.com +short
   ```

3. **Check ports 80 and 443:**
   ```bash
   # Must be accessible from internet for ACME challenge
   sudo firewall-cmd --list-ports
   ```

4. **Use DNS challenge (if HTTP challenge fails):**
   - Add Cloudflare API token secret
   - Update Caddyfile to use `tls { dns cloudflare {env.CLOUDFLARE_API_TOKEN} }`

### Can't Reload Caddyfile

**Symptom:** Changes to Caddyfile not taking effect.

**Solution:**
```bash
# Restart Caddy service
systemctl --user restart caddy.service

# Check for syntax errors
podman exec caddy caddy validate /etc/caddy/Caddyfile
```

## Minecraft Issues

### Server Won't Start

**Check logs:**
```bash
journalctl --user -u minecraft.service -f
```

**Common issues:**

1. **Not enough memory:**
   ```bash
   # Check available memory
   free -h

   # Reduce MEMORY env var in minecraft.container
   # Edit quadlets/containers/phase1-critical/minecraft.container
   # Change Environment=MEMORY=4G to lower value
   ```

2. **EULA not accepted:**
   ```bash
   # Verify EULA=TRUE in minecraft.container
   grep EULA quadlets/containers/phase1-critical/minecraft.container
   ```

3. **Port conflict:**
   ```bash
   # Check if port 25565 is in use
   sudo ss -tlnp | grep 25565
   ```

### Players Can't Connect

**Checklist:**

1. **Server running:**
   ```bash
   systemctl --user status minecraft.service
   ```

2. **Port forwarded:**
   - Router forwarding TCP 25565 to server
   - Firewall allows port 25565

3. **Correct address:**
   - Use `mc.yourdomain.com:25565` or `your-public-ip:25565`

4. **Whitelist:**
   ```bash
   # If whitelist is enabled, add players
   podman exec minecraft-papa rcon-cli whitelist add PlayerName
   ```

### World Corruption

**Recovery:**

```bash
# Stop server
systemctl --user stop minecraft.service

# Restore from backup
cd ~/Documents/projects/minecraft-server-tools/backups

# Find latest backup
ls -lh minecraft-data*.tar.gz

# Extract to temporary location
mkdir -p /tmp/minecraft-restore
tar xzf minecraft-data_YYYYMMDD-HHMMSS.tar.gz -C /tmp/minecraft-restore

# Remove corrupted volume
podman volume rm minecraft-data

# Create new volume
podman volume create minecraft-data

# Import backup
cat /tmp/minecraft-restore/minecraft-data.tar | podman volume import minecraft-data -

# Start server
systemctl --user start minecraft.service
```

## Prometheus/Grafana Issues

### No Data in Grafana

**Solutions:**

1. **Check Prometheus is scraping:**
   - Visit `http://localhost:9090/targets`
   - Should show Minecraft target as "UP"

2. **Check Minecraft metrics:**
   ```bash
   curl http://localhost:19565/metrics
   ```

3. **Add Prometheus as data source in Grafana:**
   - Grafana → Configuration → Data Sources → Add data source
   - Select Prometheus
   - URL: `http://prometheus:9090`
   - Save & Test

## Systemd Issues

### Service Doesn't Start on Boot

**Solution:**
```bash
# Enable linger for user services
loginctl enable-linger $USER

# Enable service
systemctl --user enable service-name.service

# Verify
systemctl --user is-enabled service-name.service
```

### Permission Denied

**Symptom:** `Failed to connect to bus: Permission denied`

**Solution:**
```bash
# Ensure you're running as the correct user
whoami

# Check if user has systemd session
loginctl user-status $USER

# Enable linger
loginctl enable-linger $USER
```

## Podman Issues

### Auto-update Not Working

**Solution:**
```bash
# Enable Podman auto-update timer
systemctl --user enable --now podman-auto-update.timer

# Check timer status
systemctl --user status podman-auto-update.timer

# Manually trigger update
podman auto-update

# Restart updated containers
systemctl --user restart service-name.service
```

### Rootless Podman Port Binding

**Symptom:** Can't bind to ports < 1024.

**Solution:**
```bash
# Check current port range
cat /proc/sys/net/ipv4/ip_unprivileged_port_start

# Allow binding to lower ports (as root)
echo 80 | sudo tee /proc/sys/net/ipv4/ip_unprivileged_port_start

# Make persistent
echo "net.ipv4.ip_unprivileged_port_start=80" | sudo tee /etc/sysctl.d/99-unprivileged-port.conf
sudo sysctl --system
```

## General Debugging

### Check All Services

```bash
# List all user services
systemctl --user list-units --type=service | grep -E '(caddy|authelia|minecraft|prometheus|grafana|homelab)'

# Check which are running
systemctl --user list-units --type=service --state=running
```

### View All Container Logs

```bash
# All containers
podman ps -a

# Logs for specific container
podman logs container-name

# Follow logs
podman logs -f container-name
```

### Restart Everything

```bash
# Stop all services
systemctl --user stop caddy.service authelia.service minecraft.service prometheus.service grafana.service

# Wait a moment
sleep 5

# Start in order
systemctl --user start homelab-network.service
systemctl --user start caddy.service
systemctl --user start authelia.service
systemctl --user start minecraft.service
systemctl --user start prometheus.service
systemctl --user start grafana.service
```

## Getting More Help

### Enable Debug Logging

For most services, you can enable debug logging by adding environment variables:

```ini
# In Quadlet file
Environment=LOG_LEVEL=debug
```

Then restart the service and check logs.

### Useful Commands

```bash
# System resources
htop
df -h
free -h

# Network connectivity
ping -c 4 8.8.8.8
curl -I https://google.com

# Podman system info
podman info
podman system df

# Systemd user info
systemctl --user status
loginctl user-status $USER
```

## Reporting Issues

When asking for help, include:

1. Service name and version
2. Relevant logs (`journalctl --user -u service-name.service -n 100`)
3. System info (`uname -a`, `podman version`)
4. What you've already tried
5. Full error messages

## Additional Resources

- [Podman Documentation](https://docs.podman.io/)
- [Systemd Documentation](https://www.freedesktop.org/software/systemd/man/)
- [Authelia Documentation](https://www.authelia.com/docs/)
- [Caddy Documentation](https://caddyserver.com/docs/)
- [Minecraft Server Documentation](https://github.com/itzg/docker-minecraft-server)
