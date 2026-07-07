#!/bin/bash
# Auto-start setup script for Dify project
# Run this once after system setup or to reconfigure autostart

set -e

echo "=== Auto-Start Setup ==="

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
    if ! command -v sudo &> /dev/null; then
        echo "ERROR: sudo is required but not available"
        exit 1
    fi
    SUDO="sudo"
else
    SUDO=""
fi

PROJECT_DIR="/home/vector/projects"

echo "Installing Dify Docker service..."
$SUDO cp "$PROJECT_DIR/dify/docker/dify-docker.service" /etc/systemd/system/
$SUDO systemctl daemon-reload
$SUDO systemctl enable dify-docker

echo "Installing WebApp service..."
$SUDO cp "$PROJECT_DIR/webapp-conversation/webapp.service" /etc/systemd/system/
$SUDO systemctl daemon-reload
$SUDO systemctl enable webapp

echo ""
echo "=== Starting services now ==="
$SUDO systemctl start dify-docker
sleep 5
$SUDO systemctl start webapp

echo ""
echo "=== Status check ==="
$SUDO systemctl status dify-docker --no-pager || true
echo ""
$SUDO systemctl status webapp --no-pager || true

echo ""
echo "=== Done! ==="
echo "Services will start automatically after reboot."
echo ""
echo "Useful commands:"
echo "  sudo systemctl status dify-docker"
echo "  sudo systemctl status webapp"
echo "  sudo systemctl restart dify-docker"
echo "  sudo systemctl restart webapp"