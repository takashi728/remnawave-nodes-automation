#!/bin/bash
set -e

DOMAIN="$1"
NODE_PORT="${2:-2222}"
PANEL_IP="${3:-}"

if [ -z "$DOMAIN" ]; then
    echo "Usage: sudo $0 <domain> [2222] [PANEL_IP]"
    exit 1
fi

INSTALL_DIR="/opt/remnanode"
CERT_DIR="$INSTALL_DIR/certs"
LOG_DIR="/var/log/remnanode"

 echo "=== Deploying Remnawave Node for $DOMAIN ==="

# 1. Docker
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker || true
fi

mkdir -p "$INSTALL_DIR" "$CERT_DIR" "$LOG_DIR"
cd "$INSTALL_DIR"

# 2. acme.sh
if [ ! -f ~/.acme.sh/acme.sh ]; then
    curl https://get.acme.sh | sh
    source ~/.bashrc 2>/dev/null || true
fi

# 3. Issue cert if missing
if [ ! -f "$CERT_DIR/fullchain.pem" ]; then
    echo "Issuing certificate..."
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" \
        --standalone \
        --key-file "$CERT_DIR/privkey.key" \
        --fullchain-file "$CERT_DIR/fullchain.pem"
fi

# 4. Ask for SECRET_KEY securely
if [ -z "$SECRET_KEY" ]; then
    read -sp "Paste SECRET_KEY from Remnawave Panel: " SECRET_KEY
    echo
fi

if [ -z "$SECRET_KEY" ]; then
    echo "SECRET_KEY is required!"
    exit 1
fi

# 5. Generate docker-compose.yml with REAL expanded values
cat > docker-compose.yml << EOF
services:
  remnanode:
    image: remnawave/node:latest
    restart: always
    network_mode: host
    environment:
      - NODE_PORT=$NODE_PORT
      - SECRET_KEY=$SECRET_KEY
    volumes:
      - ./certs:/var/lib/remnawave/configs/xray/ssl:ro
      - $LOG_DIR:/var/log/remnanode

  fallback:
    image: excalidraw/excalidraw:latest
    restart: always
    network_mode: host
    ports:
      - "9443:80"
EOF

# 6. Set reload hook (now safe because compose file exists)
~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
    --key-file "$CERT_DIR/privkey.key" \
    --fullchain-file "$CERT_DIR/fullchain.pem" \
    --reloadcmd "cd $INSTALL_DIR && docker compose restart remnanode || true"

# 7. Firewall
if command -v ufw &> /dev/null; then
    ufw allow 443/tcp comment 'Remnawave'
    if [ -n "$PANEL_IP" ]; then
        ufw allow from "$PANEL_IP" to any port $NODE_PORT comment 'Panel'
    fi
    ufw --force enable
fi

# 8. Start containers
echo "Starting containers..."
docker compose up -d
docker compose ps

echo ""
echo "✅ Deployment complete for $DOMAIN"
echo "Test: https://$DOMAIN"
