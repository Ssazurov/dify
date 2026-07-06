#!/bin/bash
# Dify Apps Export Script
# Exports all apps/workflows to JSON for git version control
# Usage: ./export-apps.sh

set -e

DIFY_URL="${CONSOLE_API_URL:-http://10.138.45.35}"
API_KEY="${DIFY_API_KEY:-}"
EXPORT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../exports" && pwd)"

echo "=== Dify Apps Export Script ==="
echo "Dify URL: ${DIFY_URL}"
echo "Export directory: ${EXPORT_DIR}"
echo ""

# Check API key
if [ -z "$API_KEY" ]; then
    echo "ERROR: DIFY_API_KEY not set"
    echo "Set it with: export DIFY_API_KEY='your-api-key'"
    exit 1
fi

# Create export directory
mkdir -p "${EXPORT_DIR}"

# Get apps list
echo "[1/3] Fetching apps list..."
APPS=$(curl -s -X GET "${DIFY_URL}/console/api/v1/apps" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json")

# Check if request was successful
if ! echo "$APPS" | grep -q '"data"'; then
    echo "ERROR: Failed to fetch apps. Check API key and URL."
    echo "Response: $APPS"
    exit 1
fi

# Extract app IDs and names
echo "$APPS" | jq -r '.data[] | "\(.id) \(.name) \(.mode)"' | while read -r id name mode; do
    echo "  - ${name} (${mode}): ${id}"
    
    # Export app as YAML (includes workflows)
    echo "[2/3] Exporting ${name}..."
    curl -s -X POST "${DIFY_URL}/console/api/v1/apps/${id}/export" \
        -H "Authorization: Bearer ${API_KEY}" \
        -H "Content-Type: application/json" \
        -o "${EXPORT_DIR}/${name}.yaml"
    
    if [ -s "${EXPORT_DIR}/${name}.yaml" ]; then
        echo "    Saved: ${EXPORT_DIR}/${name}.yaml"
    else
        echo "    ERROR: Empty file, skipping"
        rm -f "${EXPORT_DIR}/${name}.yaml"
    fi
done

# Export datasets (knowledge bases)
echo "[3/3] Fetching datasets..."
DATASETS=$(curl -s -X GET "${DIFY_URL}/console/api/v1/datasets" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json")

echo "$DATASETS" | jq -r '.data[] | "\(.id) \(.name)"' | while read -r id name; do
    echo "  - Dataset: ${name}"
    
    # Export dataset documents metadata (not full content)
    curl -s -X GET "${DIFY_URL}/console/api/v1/datasets/${id}/documents" \
        -H "Authorization: Bearer ${API_KEY}" \
        -H "Content-Type: application/json" \
        -o "${EXPORT_DIR}/dataset-${name}.json" 2>/dev/null || true
done

echo ""
echo "=== Export Complete ==="
echo "Files saved to: ${EXPORT_DIR}"
ls -la "${EXPORT_DIR}"
echo ""
echo "To commit to git:"
echo "  cd ${EXPORT_DIR}"
echo "  git add ."
echo "  git commit -m 'Export Dify apps $(date +%Y-%m-%d)'"