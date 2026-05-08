#!/bin/bash
# Restic backup script for Podman volumes
# Backs up homelab volumes to NAS using restic with Discord notifications

set -e

# Configuration from environment variables
RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-}"
RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-/run/secrets/restic_repository_password}"
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"
DISCORD_USER_ID="${DISCORD_USER_ID:-}"
BACKUP_TAG="${BACKUP_TAG:-homelab}"
LOG_FILE="${LOG_FILE:-/var/log/restic-backup.log}"

# Backup timestamp
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
TIMESTAMP_SHORT=$(date +%Y%m%d-%H%M%S)

# Function to send Discord notification
send_discord_alert() {
    local message="$1"
    local color="$2"  # decimal color: 65280 = green, 16711680 = red, 16776960 = yellow
    local username="Restic Backup 💾"
    local avatar_url="https://restic.net/img/logo.png"

    if [ -z "$DISCORD_WEBHOOK_URL" ]; then
        echo "Warning: Discord webhook not configured, skipping notification"
        return 0
    fi

    local mention=""
    if [ -n "$DISCORD_USER_ID" ]; then
        mention="<@${DISCORD_USER_ID}>"
    fi

    local payload=$(cat <<EOF
{
  "username": "$username",
  "avatar_url": "$avatar_url",
  "content": "$mention",
  "embeds": [{
    "title": "Homelab Backup Status",
    "description": "$message",
    "color": $color,
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "footer": {
      "text": "Restic Backup System"
    }
  }]
}
EOF
    )

    curl -H "Content-Type: application/json" \
         -d "$payload" \
         "$DISCORD_WEBHOOK_URL" \
         --silent --show-error || echo "Failed to send Discord notification"
}

# Function to log messages
log() {
    local message="$1"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $message" | tee -a "$LOG_FILE"
}

# Function to initialize restic repository if needed
init_repository() {
    log "Checking if restic repository exists..."
    if ! restic snapshots --quiet 2>/dev/null; then
        log "Repository doesn't exist, initializing..."
        restic init
        log "✓ Repository initialized"
    else
        log "✓ Repository exists"
    fi
}

# Function to backup a volume
backup_volume() {
    local volume_name="$1"
    local mount_point="/backup-source/$volume_name"

    log "Backing up volume: $volume_name"
    log "  Mount point: $mount_point"

    if [ ! -d "$mount_point" ]; then
        log "  ⚠ Mount point not found, skipping..."
        return 1
    fi

    # Backup with restic
    restic backup "$mount_point" \
        --tag "$BACKUP_TAG" \
        --tag "$volume_name" \
        --host "$(hostname)" \
        --verbose 2>&1 | tee -a "$LOG_FILE"

    local exit_code=${PIPESTATUS[0]}

    if [ $exit_code -eq 0 ]; then
        log "  ✓ Backup completed: $volume_name"
        return 0
    else
        log "  ✗ Backup failed: $volume_name (exit code: $exit_code)"
        return 1
    fi
}

# Main backup process
main() {
    log "========================================"
    log "Starting restic backup: $TIMESTAMP"
    log "========================================"
    log ""
    log "Repository: $RESTIC_REPOSITORY"
    log "Backup tag: $BACKUP_TAG"
    log ""

    # Verify required environment variables
    if [ -z "$RESTIC_REPOSITORY" ]; then
        log "ERROR: RESTIC_REPOSITORY not set"
        send_discord_alert "❌ Backup failed: RESTIC_REPOSITORY not configured" 16711680
        exit 1
    fi

    if [ ! -f "$RESTIC_PASSWORD_FILE" ]; then
        log "ERROR: Restic password file not found: $RESTIC_PASSWORD_FILE"
        send_discord_alert "❌ Backup failed: Password file not found" 16711680
        exit 1
    fi

    # Initialize repository if needed
    init_repository

    # List of volumes to backup (mounted at /backup-source/<volume-name>)
    VOLUMES=(
        "minecraft-data"
        "prometheus-data"
        "grafana-data"
        "caddy-data"
        "caddy-config"
    )

    # Track success/failure
    local total_volumes=${#VOLUMES[@]}
    local successful_backups=0
    local failed_backups=0
    local failed_volumes=()

    # Backup each volume
    for volume in "${VOLUMES[@]}"; do
        if backup_volume "$volume"; then
            ((successful_backups++))
        else
            ((failed_backups++))
            failed_volumes+=("$volume")
        fi
        log ""
    done

    # Cleanup old snapshots (keep last 30 daily, 12 weekly, 12 monthly)
    log "Running maintenance: forget old snapshots..."
    restic forget \
        --keep-daily 30 \
        --keep-weekly 12 \
        --keep-monthly 12 \
        --tag "$BACKUP_TAG" \
        --prune \
        --verbose 2>&1 | tee -a "$LOG_FILE"
    log ""

    # Check repository integrity (quick check)
    log "Checking repository integrity..."
    restic check --read-data-subset=5% 2>&1 | tee -a "$LOG_FILE"
    log ""

    # Summary
    log "========================================"
    log "Backup Summary"
    log "========================================"
    log "Total volumes: $total_volumes"
    log "Successful: $successful_backups"
    log "Failed: $failed_backups"

    # Get repository stats
    log ""
    log "Repository Statistics:"
    restic stats --mode raw-data 2>&1 | tee -a "$LOG_FILE"

    log ""
    log "========================================"
    log "Backup completed: $(date +"%Y-%m-%d %H:%M:%S")"
    log "========================================"

    # Send Discord notification
    if [ $failed_backups -eq 0 ]; then
        local message="✅ **Backup Successful**\n\n"
        message+="📦 Volumes backed up: $successful_backups/$total_volumes\n"
        message+="🕒 Completed: $TIMESTAMP\n"
        message+="📍 Repository: \`$RESTIC_REPOSITORY\`"
        send_discord_alert "$message" 65280  # Green
    else
        local message="⚠️ **Backup Completed with Errors**\n\n"
        message+="✅ Successful: $successful_backups\n"
        message+="❌ Failed: $failed_backups\n"
        message+="📛 Failed volumes: ${failed_volumes[*]}\n"
        message+="🕒 Completed: $TIMESTAMP\n"
        message+="📍 Repository: \`$RESTIC_REPOSITORY\`"
        send_discord_alert "$message" 16776960  # Yellow
    fi

    # Exit with error if any backups failed
    if [ $failed_backups -gt 0 ]; then
        exit 1
    fi
}

# Run main function
main
