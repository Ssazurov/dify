#!/bin/bash
# Auto-commit script for Dify and webapp-conversation
# Run via cron: 0 */2 * * * /path/to/auto-commit.sh
# Or manually: ./auto-commit.sh

set -e

PROJECTS_DIR="/home/vector/projects"
LOG_FILE="/home/vector/projects/tmp/auto-commit.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Starting auto-commit ==="

# Commit Dify changes
log "Checking dify..."
cd "${PROJECTS_DIR}/dify"
if [ -n "$(git status --porcelain)" ]; then
    git add -A
    git commit -m "Auto-save $(date '+%Y-%m-%d %H:%M:%S')"
    git push origin main
    log "Dify: committed and pushed"
else
    log "Dify: no changes"
fi

# Commit webapp-conversation changes
log "Checking webapp-conversation..."
cd "${PROJECTS_DIR}/webapp-conversation"
if [ -n "$(git status --porcelain)" ]; then
    git add -A
    git commit -m "Auto-save $(date '+%Y-%m-%d %H:%M:%S')"
    git push origin main
    log "webapp-conversation: committed and pushed"
else
    log "webapp-conversation: no changes"
fi

# RAG Backup (daily at 3am)
log "Running RAG backup..."
cd "${PROJECTS_DIR}/dify/docker"
./backup-rag.sh

# Commit RAG exports
cd "${PROJECTS_DIR}/dify/exports"
if [ -n "$(git status --porcelain)" ]; then
    git add -A
    git commit -m "RAG backup $(date '+%Y-%m-%d')"
    git push origin main
    log "RAG exports: committed and pushed"
else
    log "RAG exports: no changes"
fi

log "=== Auto-commit complete ==="
echo "" >> "$LOG_FILE"