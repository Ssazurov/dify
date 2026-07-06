#!/bin/bash
# Dify Backup Script
# Usage: ./backup.sh [backup-dir]
# Creates tar.gz archive of all Dify volumes

set -e

BACKUP_DIR="${1:-/home/vector/backups}"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="dify-backup-${DATE}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Dify Backup Script ==="
echo "Date: $(date)"
echo "Backup directory: ${BACKUP_DIR}"
echo ""

# Create backup directory if not exists
mkdir -p "${BACKUP_DIR}"

# Stop Dify containers
echo "[1/4] Stopping Dify containers..."
cd "${SCRIPT_DIR}"
docker compose down

# Create backup archive
echo "[2/4] Creating backup archive..."
tar -czf "${BACKUP_DIR}/${BACKUP_NAME}-volumes.tar.gz" \
    volumes/ \
    .env

# Also backup docker-compose files (non-sensitive)
tar -czf "${BACKUP_DIR}/${BACKUP_NAME}-config.tar.gz" \
    docker-compose.yaml \
    docker-compose.middleware.yaml \
    .env.example

# Restart Dify
echo "[3/4] Restarting Dify containers..."
docker compose up -d

# Create symlink to latest backup
echo "[4/4] Creating latest backup symlink..."
ln -sf "${BACKUP_NAME}-volumes.tar.gz" "${BACKUP_DIR}/dify-backup-latest-volumes.tar.gz"
ln -sf "${BACKUP_NAME}-config.tar.gz" "${BACKUP_DIR}/dify-backup-latest-config.tar.gz"

echo ""
echo "=== Backup Complete ==="
echo "Volumes: ${BACKUP_DIR}/${BACKUP_NAME}-volumes.tar.gz"
echo "Config:  ${BACKUP_DIR}/${BACKUP_NAME}-config.tar.gz"
echo "Size:    $(du -h ${BACKUP_DIR}/${BACKUP_NAME}-volumes.tar.gz | cut -f1)"
echo ""
echo "To restore: tar -xzf ${BACKUP_DIR}/${BACKUP_NAME}-volumes.tar.gz -C ${SCRIPT_DIR}/"