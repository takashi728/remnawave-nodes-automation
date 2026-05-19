#!/bin/bash
# Simple firewall helper

NODE_PORT=${1:-2222}
PANEL_IP=${2:-}

ufw allow 443/tcp

if [ -n "$PANEL_IP" ]; then
    ufw allow from "$PANEL_IP" to any port $NODE_PORT
else
    echo "Add your Panel IP manually: ufw allow from PANEL_IP to any port $NODE_PORT"
fi

ufw --force enable
echo "Firewall configured."
