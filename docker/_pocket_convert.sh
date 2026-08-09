#!/bin/bash
for f in /home/vector/dify/docker/intake/incoming/*.pdf; do
  docker compose run --rm \
    -v "$(pwd)/shard_tables.py:/app/shard_tables.py" \
    docling-intake \
    python /app/shard_tables.py \
    "$f" /data/processed/ \
    --doc-name "$(basename "$f" .pdf)" \
    --product "DIFY" \
    --doc-type "Manual" \
    --version "-" \
    --device cuda
done