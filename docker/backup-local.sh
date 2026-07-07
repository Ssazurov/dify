#!/bin/bash
# Quick backup script - copies project to backup directory

set -e

PROJECT_DIR="/home/vector/projects"
BACKUP_DIR="${1:-/home/vector/backups}"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')

echo "Creating backup..."

mkdir -p "$BACKUP_DIR"

# Backup project files (excluding node_modules, .git, volumes)
rsync -av \
    --exclude='node_modules' \
    --exclude='.git' \
    --exclude='dify/docker/volumes' \
    --exclude='dify/docker/.env' \
    --exclude='webapp-conversation/.next' \
    "$PROJECT_DIR" "$BACKUP_DIR/backup_${TIMESTAMP}"

echo "Backup created: $BACKUP_DIR/backup_${TIMESTAMP}"
echo "Done!"