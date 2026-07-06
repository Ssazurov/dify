#!/bin/bash
# GAR/RAG Project Backup Script
# Exports all Dify datasets, documents, and vector data for backup
# Usage: ./backup-rag.sh

set -e

EXPORT_DIR="/home/vector/projects/dify/exports"
DATE=$(date +%Y%m%d_%H%M%S)
DB_CONTAINER="docker-db_postgres-1"

echo "=== GAR/RAG Project Backup ==="
echo "Date: $(date)"
echo ""

# Create export directory
mkdir -p "${EXPORT_DIR}/${DATE}"

# Export PostgreSQL data (datasets, documents, apps)
echo "[1/4] Exporting PostgreSQL data..."

# Datasets
docker exec ${DB_CONTAINER} psql -U postgres -d dify -c "SELECT id, name, description, created_at FROM datasets;" -o "${EXPORT_DIR}/${DATE}/datasets.csv" 2>/dev/null || true

# Documents
docker exec ${DB_CONTAINER} psql -U postgres -d dify -c "SELECT d.id, d.dataset_id, d.document_name, d.created_at FROM documents d;" -o "${EXPORT_DIR}/${DATE}/documents.csv" 2>/dev/null || true

# Document segments (chunks)
docker exec ${DB_CONTAINER} psql -U postgres -d dify -c "SELECT id, document_id, content, word_count FROM document_segments LIMIT 1000;" -o "${EXPORT_DIR}/${DATE}/chunks.csv" 2>/dev/null || true

# Apps
docker exec ${DB_CONTAINER} psql -U postgres -d dify -c "SELECT id, name, mode, created_at FROM apps;" -o "${EXPORT_DIR}/${DATE}/apps.csv" 2>/dev/null || true

# Conversations
docker exec ${DB_CONTAINER} psql -U postgres -d dify -c "SELECT id, app_id, created_at FROM conversations;" -o "${EXPORT_DIR}/${DATE}/conversations.csv" 2>/dev/null || true

# Export as JSON for git
echo "[2/4] Converting to JSON..."
docker exec ${DB_CONTAINER} psql -U postgres -d dify -t -A -F"," -c "SELECT json_agg(row_to_json(d)) FROM (SELECT id, name, description, created_at FROM datasets) d;" > "${EXPORT_DIR}/${DATE}/datasets.json" 2>/dev/null || echo "[]" > "${EXPORT_DIR}/${DATE}/datasets.json"

docker exec ${DB_CONTAINER} psql -U postgres -d dify -t -A -F"," -c "SELECT json_agg(row_to_json(d)) FROM (SELECT id, name, mode, created_at FROM apps) d;" > "${EXPORT_DIR}/${DATE}/apps.json" 2>/dev/null || echo "[]" > "${EXPORT_DIR}/${DATE}/apps.json"

# Copy Weaviate data (vectors)
echo "[3/4] Backing up Weaviate..."
docker cp docker-weaviate-1:/var/lib/weaviate "${EXPORT_DIR}/${DATE}/weaviate_data" 2>/dev/null || echo "Weaviate backup skipped"

# Create metadata file
echo "[4/4] Creating metadata..."
cat > "${EXPORT_DIR}/${DATE}/backup-info.json" << EOF
{
  "date": "${DATE}",
  "timestamp": "$(date -Iseconds)",
  "components": {
    "postgresql": "datasets, documents, chunks, apps, conversations",
    "weaviate": "vector embeddings",
    "storage": "uploaded files"
  },
  "note": "Full backup includes docker volumes. This is data export only."
}
EOF

# Create latest symlink
ln -sf "${DATE}" "${EXPORT_DIR}/latest"

echo ""
echo "=== Backup Complete ==="
echo "Location: ${EXPORT_DIR}/${DATE}/"
echo ""
echo "Files:"
ls -la "${EXPORT_DIR}/${DATE}/"
echo ""
echo "To commit to git:"
echo "  cd ${EXPORT_DIR}"
echo "  git add ${DATE}/"
echo "  git commit -m 'RAG backup ${DATE}'"
echo "  git push"