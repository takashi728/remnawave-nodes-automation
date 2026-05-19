#!/bin/bash
set -e

DOMAIN="$1"
NODE_PORT="${2:-2222}"
SECRET_KEY="$3"
PANEL_IP="${4:-}"
FALLBACK_TYPE="${5:-excalidraw}"   # excalidraw, hedgedoc, nginx

if [ -z "$DOMAIN" ]; then
    echo "Usage: $0 <domain> [port] [secret] [panel_ip] [fallback_type]"
    echo "Fallback types: excalidraw (default), hedgedoc, nginx"
    exit 1
fi

INSTALL_DIR="/opt/remnanode"
CERT_DIR="$INSTALL_DIR/certs"
LOG_DIR="/var/log/remnanode"

echo "=== Deploying Remnawave Node for $DOMAIN ==="
echo "Fallback: $FALLBACK_TYPE"

# Docker
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker || true
fi

mkdir -p "$INSTALL_DIR" "$CERT_DIR" "$LOG_DIR"
cd "$INSTALL_DIR"

# acme.sh
if [ ! -f ~/.acme.sh/acme.sh ]; then
    curl https://get.acme.sh | sh
fi

if [ ! -f "$CERT_DIR/fullchain.pem" ]; then
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone \
        --key-file "$CERT_DIR/privkey.key" \
        --fullchain-file "$CERT_DIR/fullchain.pem"
fi

~/.acme.sh/acme.sh install-cert -d "$DOMAIN" \
    --key-file "$CERT_DIR/privkey.key" \
    --fullchain-file "$CERT_DIR/fullchain.pem" \
    --renew-hook "cd $INSTALL_DIR && docker compose restart remnanode || true"

if [ -z "$SECRET_KEY" ]; then
    read -sp "SECRET_KEY from Panel: " SECRET_KEY; echo
fi

# Generate docker-compose based on fallback type
case "$FALLBACK_TYPE" in
  excalidraw)
    cat > docker-compose.yml << 'EOF'
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
    ;;

  hedgedoc)
    cat > docker-compose.yml << 'EOF'
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

  fallback:
    image: quay.io/hedgedoc/hedgedoc:latest
    restart: always
    network_mode: host
    ports:
      - "9443:80"
    environment:
      - CMD_DOMAIN=$DOMAIN
EOF
    ;;

  nginx|*)
    cat > docker-compose.yml << 'EOF'
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

  fallback:
    image: nginx:alpine
    restart: always
    network_mode: host
    ports:
      - "9443:80"
    volumes:
      - ./fallback-html:/usr/share/nginx/html:ro
EOF
    ;;
esac

# Create nice fallback content for nginx
if [ "$FALLBACK_TYPE" = "nginx" ]; then
  mkdir -p fallback-html
  cat > fallback-html/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html><head><title>Collaborative Workspace</title></head>
<body style="font-family:system-ui;text-align:center;padding:60px;background:#f8f9fa">
<h1>Secure Collaborative Environment</h1>
<p>This infrastructure supports real-time collaboration tools.</p>
</body></html>
HTMLEOF
fi

# Firewall
if command -v ufw &> /dev/null; then
    ufw allow 443/tcp
    [ -n "$PANEL_IP" ] && ufw allow from "$PANEL_IP" to any port $NODE_PORT
    ufw --force enable
fi

docker compose up -d
docker compose ps

echo ""
echo "✅ Node deployed successfully!"
echo "Fallback ($FALLBACK_TYPE) running on internal port 9443"
echo "Test: https://$DOMAIN"
