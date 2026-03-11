#!/bin/bash

# **METEOR SERVER - BACKUP SCRIPT**
# Production backup solution for Meteor server data

set -euo pipefail

# Configuration
METEOR_DATA="/var/lib/meteor"
BACKUP_DIR="/backup/meteor"
RETENTION_DAYS=30
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="meteor_backup_${TIMESTAMP}"

# Logging
LOG_FILE="/var/log/meteor/backup.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE"
    exit 1
}

# Create backup directory
mkdir -p "$BACKUP_DIR"

log "Starting Meteor backup: $BACKUP_NAME"

# Create snapshot (if server supports it)
if command -v redis-cli &> /dev/null; then
    log "Triggering server snapshot..."
    redis-cli -h 127.0.0.1 -p 6379 BGSAVE || log "Warning: Could not trigger background save"
    sleep 5
fi

# Create compressed backup
log "Creating compressed backup..."
tar -czf "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" \
    -C "$METEOR_DATA" \
    --exclude="*.tmp" \
    --exclude="*.pid" \
    . || error "Backup creation failed"

# Verify backup integrity
log "Verifying backup integrity..."
if tar -tzf "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" > /dev/null; then
    log "Backup verification successful"
else
    error "Backup verification failed"
fi

# Calculate backup size
BACKUP_SIZE=$(du -h "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" | cut -f1)
log "Backup completed: ${BACKUP_NAME}.tar.gz (${BACKUP_SIZE})"

# Cleanup old backups
log "Cleaning up backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -name "meteor_backup_*.tar.gz" -mtime +$RETENTION_DAYS -delete

log "Backup process completed successfully"

# Optional: Upload to cloud storage
# aws s3 cp "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" "s3://meteor-backups/"
# gsutil cp "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" "gs://meteor-backups/"
