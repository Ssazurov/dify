#!/bin/bash

echo "=== TIME ==="
date

echo
echo "=== DOCKER ==="
docker ps --format "table {{.Names}}\t{{.Status}}"

echo
echo "=== DIFY HTTP ==="
curl -I http://localhost 2>/dev/null | head -5