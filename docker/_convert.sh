#!/bin/bash
vector@MSI:~/dify/docker$            docker compose run --rm   -v "$(pwd)/shard_tables.py:/app/shard_tables.py"   docling-intake   /data/incoming/AG.pdf   /data/processed/AG1.md   --doc-name "RN1"   --product "DIFY"   --doc-type "Инструкция"   --version "-"   --device cuda

  
docker compose run --rm   -v "$(pwd)/shard_tables.py:/app/shard_tables.py"   docling-intake   /data/incoming/rn.pdf   /data/processed/rn1.md   --doc-name "RN1"   --product "DIFY"   --doc-type "Инструкция"   --version "-"   --device cuda



docker compose run --rm   -v "$(pwd)/shard_tables.py:/app/shard_tables.py"   docling-intake   /data/incoming/sample.docx   /data/processed/sample_docx.md   --doc-name "RN1"   --product "DIFY"   --doc-type "Инструкция"   --version "-"   --device cuda


curl -X POST "http://localhost/console/api/datasets/04fe27b3-920e-4ab4-9ef8-d52d702f96b1/documents/create-by-file" \
  -H "Authorization: Bearer dataset-NgGU785tRSMT3VRahc5qPmGj" \
  -F "file=@./intake/incoming/AG.pdf" \
  -F "name=тест_docling" \
  -F "process_rule={\"mode\":\"custom\",\"rules\":{\"segmentation\":{\"separator\":\"\\n\",\"max_tokens\":500}}}"
  