# Restic Backup Configuration

This directory contains configuration for the restic backup system.

## Quick Start

1. **Copy the template:**
   ```bash
   cp configs/restic/restic.env.template configs/restic/restic.env
   ```

2. **Edit `restic.env` with your NAS details:**
   ```bash
   nano configs/restic/restic.env
   ```

3. **Create required Podman secrets:**
   ```bash
   # Restic repository password
   openssl rand -base64 32 | podman secret create restic-repository-password -

   # SSH key for SFTP (if using SFTP)
   ssh-keygen -t ed25519 -f ~/.ssh/restic_nas_key -C "restic-backup"
   podman secret create restic-ssh-key ~/.ssh/restic_nas_key

   # Discord webhook (for notifications)
   echo "https://discord.com/api/webhooks/..." | podman secret create restic-discord-webhook -
   echo "your-discord-user-id" | podman secret create discord-user-id -
   ```

4. **Add SSH public key to your NAS** (if using SFTP):
   ```bash
   # Display the public key
   cat ~/.ssh/restic_nas_key.pub

   # Add this to your NAS user's ~/.ssh/authorized_keys
   ```

5. **Generate SSH known_hosts** (if using SFTP):
   ```bash
   ssh-keyscan -H your-nas-ip-or-hostname > configs/restic/known_hosts
   ```

## Repository Types

### Option 1: SFTP (Recommended)

**Best for:** NAS with SSH access

**Setup:**
1. Enable SSH on your NAS
2. Create a dedicated backup user
3. Generate SSH key pair (see Quick Start)
4. Add public key to NAS authorized_keys

**Configuration in `restic.env`:**
```bash
RESTIC_REPOSITORY=sftp:backup-user@192.168.1.100:/volume1/backups/homelab-restic
```

**Pros:**
- Encrypted in transit (SSH)
- Works over network
- Most NAS systems support SSH

**Cons:**
- Requires SSH access to NAS

---

### Option 2: NFS Mount

**Best for:** NAS with NFS shares

**Setup:**
1. Create NFS share on NAS
2. Mount NFS share on host (will be bind-mounted to container)
3. Configure repository to use local path

**Mount NFS on host:**
```bash
# Create mount point
sudo mkdir -p /mnt/nas-backups

# Mount NFS (add to /etc/fstab for persistence)
sudo mount -t nfs nas.local:/volume1/backups /mnt/nas-backups
```

**Configuration in `restic.env`:**
```bash
RESTIC_REPOSITORY=/mnt/nas/restic-backups
```

**Update Quadlet to mount NFS:**
Add to `quadlets/containers/phase2-services/restic.container`:
```ini
Volume=/mnt/nas-backups:/mnt/nas:Z
```

**Pros:**
- Fast (local filesystem performance)
- Simple setup

**Cons:**
- Requires NFS configuration
- Host must mount NFS share

---

### Option 3: SMB/CIFS (via mount)

**Best for:** NAS with SMB/Samba shares (Windows-compatible)

**Setup:**
1. Create SMB share on NAS
2. Mount SMB share on host
3. Configure repository to use local path

**Mount SMB on host:**
```bash
# Install cifs-utils
sudo dnf install cifs-utils

# Create credentials file
sudo mkdir -p /root/.smb
sudo bash -c 'cat > /root/.smb/nas-credentials <<EOF
username=backup-user
password=your-password
domain=WORKGROUP
EOF'
sudo chmod 600 /root/.smb/nas-credentials

# Create mount point
sudo mkdir -p /mnt/nas-backups

# Mount SMB (add to /etc/fstab for persistence)
sudo mount -t cifs //nas.local/backups /mnt/nas-backups -o credentials=/root/.smb/nas-credentials,uid=1000,gid=1000
```

**Configuration in `restic.env`:**
```bash
RESTIC_REPOSITORY=/mnt/nas/restic-backups
```

**Update Quadlet to mount SMB:**
Add to `quadlets/containers/phase2-services/restic.container`:
```ini
Volume=/mnt/nas-backups:/mnt/nas:Z
```

**Pros:**
- Works with Windows NAS
- Wide compatibility

**Cons:**
- Requires SMB configuration
- Need to store credentials

---

### Option 4: restic REST Server

**Best for:** Running restic-rest-server on your NAS (in Docker/Podman)

**Setup on NAS:**
```bash
# Run restic REST server on NAS
podman run -d \
  --name restic-rest-server \
  -p 8000:8000 \
  -v /volume1/backups:/data \
  docker.io/restic/rest-server:latest \
  --path /data
```

**Configuration in `restic.env`:**
```bash
RESTIC_REPOSITORY=rest:http://192.168.1.100:8000/homelab
```

**Pros:**
- Optimized for restic
- Supports append-only mode
- Simple HTTP protocol

**Cons:**
- Requires running additional service on NAS
- Network-based (slower than local)

---

## Testing Your Configuration

After setting up, test the backup manually:

```bash
# Start the backup container manually
systemctl --user start restic-backup.service

# Check logs
journalctl --user -u restic-backup.service -f
```

The first run will:
1. Initialize the restic repository
2. Backup all volumes
3. Send Discord notification with results

## Backup Schedule

Backups are scheduled using systemd timers:

```bash
# Check timer status
systemctl --user status restic-backup.timer

# View next scheduled run
systemctl --user list-timers | grep restic

# Manually trigger backup
systemctl --user start restic-backup.service
```

Default schedule: **Daily at 2:00 AM**

To change the schedule, edit `quadlets/timers/restic-backup.timer`

## Restoring from Backup

### List available snapshots:
```bash
podman run --rm \
  -v minecraft-data.volume:/backup-source/minecraft-data:Z \
  -e RESTIC_REPOSITORY="sftp:user@nas:/path" \
  -e RESTIC_PASSWORD_FILE=/run/secrets/restic_repository_password \
  --secret restic-repository-password \
  --secret restic-ssh-key \
  docker.io/restic/restic:latest \
  snapshots
```

### Restore specific snapshot:
```bash
podman run --rm \
  -v minecraft-data.volume:/backup-source/minecraft-data:Z \
  -e RESTIC_REPOSITORY="sftp:user@nas:/path" \
  -e RESTIC_PASSWORD_FILE=/run/secrets/restic_repository_password \
  --secret restic-repository-password \
  --secret restic-ssh-key \
  docker.io/restic/restic:latest \
  restore <snapshot-id> --target /backup-source/minecraft-data
```

## Security Notes

- Repository is encrypted with password from `restic-repository-password` secret
- SSH keys stored as Podman secrets (encrypted at rest)
- Credentials never committed to git
- Use strong passwords for restic repository
- Backup the restic repository password in a password manager!

## Troubleshooting

### Connection refused (SFTP)
- Verify SSH is enabled on NAS
- Check SSH port (default 22)
- Test SSH connection: `ssh -i ~/.ssh/restic_nas_key backup-user@nas`
- Verify public key is in NAS authorized_keys

### Permission denied (NFS/SMB)
- Check mount permissions
- Verify user has write access
- Check SELinux labels (`:Z` flag on volumes)

### Repository locked
- Another backup might be running
- Or previous backup crashed
- Unlock: `restic unlock`

### Out of space
- Check NAS storage
- Clean old snapshots: `restic forget --keep-last 10 --prune`

## Files in this Directory

- `restic.env.template` - Template configuration (copy to `restic.env`)
- `restic.env` - Your actual configuration (git-ignored, DO NOT COMMIT)
- `known_hosts` - SSH known hosts for SFTP (optional but recommended)
- `README.md` - This file
