#!/bin/bash
set -e

DOMAIN="$1"
NODE_PORT="${2:-2222}"
SECRET_KEY="$3"

if [ -z "$DOMAIN" ]; then
    echo "Usage: sudo $0 <domain> [2222] [SECRET_KEY]"
    echo "(Create the node in Remnawave Panel first and copy the generated docker-compose.yml)"
    exit 1
fi

INSTALL_DIR="/opt/remnanode"
CERT_DIR="$INSTALL_DIR/certs"
LOG_DIR="/var/log/remnanode"

 echo "=== Setting up Remnawave Node for $DOMAIN ==="

mkdir -p "$INSTALL_DIR" "$CERT_DIR" "$LOG_DIR"
cd "$INSTALL_DIR"

# Install Docker if missing
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker || true
fi

# Install acme.sh if missing
if [ ! -f ~/.acme.sh/acme.sh ]; then
    curl https://get.acme.sh | sh
    source ~/.bashrc 2>/dev/null || true
fi

# Issue certificate
if [ ! -f "$CERT_DIR/fullchain.pem" ]; then
    echo "Issuing Let's Encrypt certificate..."
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" \
        --standalone \
        --key-file "$CERT_DIR/privkey.key" \
        --fullchain-file "$CERT_DIR/fullchain.pem"
fi

# Get SECRET_KEY if not provided
if [ -z "$SECRET_KEY" ]; then
    read -sp "Paste SECRET_KEY from Remnawave Panel: " SECRET_KEY
    echo
fi

if [ -z "$SECRET_KEY" ]; then
    echo "SECRET_KEY is required!"
    exit 1
fi

# Generate proper docker-compose.yml with remnanode + fallback
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

  # Fallback service (real web app for camouflage)
  fallback:
    image: excalidraw/excalidraw:latest
    restart: always
    network_mode: host
    ports:
      - "9443:80"
EOF

# Set proper reload hook for certificate renewal
~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
    --key-file "$CERT_DIR/privkey.key" \
    --fullchain-file "$CERT_DIR/fullchain.pem" \
    --reloadcmd "cd $INSTALL_DIR && docker compose restart remnanode || true"

# Start
 docker compose up -d
docker compose ps

echo ""
echo "✅ Node setup complete for $DOMAIN"
echo "Fallback (Excalidraw) running on internal port 9443"
echo "Test by visiting: https://$DOMAIN"
echo ""
echo "Important: Make sure you created the node in Remnawave Panel and assigned a Config Profile."
