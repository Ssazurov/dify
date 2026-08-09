#!/bin/bash
# Dify Backup Script
# Run manually: bash /home/vector/dify/docker/scripts/backup.sh
# Or add to crontab: 0 2 * * * /home/vector/dify/docker/scripts/backup.sh

BACKUP_DIR="/home/vector/dify/backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

echo "Starting Dify backup at $DATE..."

# Backup PostgreSQL
echo "Backing up PostgreSQL..."
docker exec docker-db_postgres-1 pg_dump -U postgres dify > "$BACKUP_DIR/dify_db_$DATE.sql"
if [ $? -eq 0 ]; then
    echo "✅ PostgreSQL backup saved to $BACKUP_DIR/dify_db_$DATE.sql"
    gzip "$BACKUP_DIR/dify_db_$DATE.sql"
    echo "✅ Compressed to dify_db_$DATE.sql.gz"
else
    echo "❌ PostgreSQL backup failed"
fi

# Backup Redis (optional - mostly cache)
echo "Backing up Redis..."
docker exec docker-redis-1 redis-cli SAVE > /dev/null 2>&1
docker cp docker-redis-1:/data/dump.rdb "$BACKUP_DIR/dify_redis_$DATE.rdb" 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✅ Redis backup saved"
fi

# Backup App Storage
echo "Backing up App Storage..."
docker run --rm -v dify_app_storage:/data -v "$BACKUP_DIR:/backup" alpine tar czf "/backup/dify_app_storage_$DATE.tar.gz" -C /data .
if [ $? -eq 0 ]; then
    echo "✅ App Storage backup saved"
fi

# List backups
echo ""
echo "Current backups:"
ls -lh "$BACKUP_DIR" | tail -10

# Keep only last 7 days
find "$BACKUP_DIR" -type f -mtime +7 -delete
echo "✅ Removed backups older than 7 days"

echo ""
echo "Backup complete!"