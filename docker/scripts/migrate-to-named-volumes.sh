#!/bin/bash
# Migrate from bind mounts to named volumes for data persistence

set -e

echo "=== Migrating to Named Volumes ==="

cd /home/vector/dify/docker

# Stop containers
echo "Stopping containers..."
docker compose down

# Create named volumes
echo "Creating named volumes..."
docker volume create dify_db_data
docker volume create dify_redis_data
docker volume create dify_weaviate_data
docker volume create dify_app_storage

# Copy data from bind mounts to named volumes
echo "Copying data..."
docker run --rm -v dify/docker/volumes/db/data:/from -v dify_db_data:/to alpine cp -r /from/* /to/
docker run --rm -v dify/docker/volumes/redis/data:/from -v dify_redis_data:/to alpine cp -r /from/* /to/
docker run --rm -v dify/docker/volumes/weaviate:/from -v dify_weaviate_data:/to alpine cp -r /from/* /to/
docker run --rm -v dify/docker/volumes/app/storage:/from -v dify_app_storage:/to alpine cp -r /from/* /to/

# Backup old volumes
echo "Backing up old volumes..."
mv volumes/db/data volumes/db/data_old
mv volumes/redis/data volumes/redis/data_old
mv volumes/weaviate volumes/weaviate_old
mv volumes/app/storage volumes/app/storage_old

# Update docker-compose.yaml to use named volumes
echo "Updating docker-compose.yaml..."

# Use sed to replace bind mounts with named volumes
sed -i 's|./volumes/db/data:|dify_db_data:|g' docker-compose.yaml
sed -i 's|./volumes/redis/data:|dify_redis_data:|g' docker-compose.yaml
sed -i 's|./volumes/weaviate:|dify_weaviate_data:|g' docker-compose.yaml
sed -i 's|./volumes/app/storage:|dify_app_storage:|g' docker-compose.yaml

echo "=== Starting containers with named volumes ==="
docker compose up -d

echo "=== Done ==="
echo "Named volumes created:"
docker volume ls | grep dify_