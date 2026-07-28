#!/bin/bash

cd /home/vector/projects/dify/docker

docker compose ps | grep "Up" >/dev/null

if [ $? -ne 0 ]; then
    docker compose up -d
fi
