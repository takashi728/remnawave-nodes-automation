#!/bin/bash
set -e

DOMAIN="$1"
NODE_PORT="${2:-2222}"
SECRET_KEY="$3"
PANEL_IP="${4:-}"
FALLBACK_TYPE="${5:-excalidraw}"

if [ -z "$DOMAIN" ]; then
    echo "Usage: $0 <domain> [port] [secret] [panel_ip] [fallback: excalidraw|hedgedoc|nginx]"
    exit 1
fi

INSTALL_DIR="/opt/remnanode"
CERT_DIR="$INSTALL_DIR/certs"
LOG_DIR="/var/log/remnanode"

echo "=== Deploying Remnawave Node for $DOMAIN ==="
echo "Fallback: $FALLBACK_TYPE"

# 1. Docker
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker || true
fi

mkdir -p "$INSTALL_DIR" "$CERT_DIR" "$LOG_DIR"
cd "$INSTALL_DIR"

# 2. acme.sh
if [ ! -f ~/.acme.sh/acme.sh ]; then
    echo "Installing acme.sh..."
    curl https://get.acme.sh | sh -s email=admin@$DOMAIN
    source ~/.bashrc 2>/dev/null || true
fi

# 3. Issue cert (with renew-hook)
if [ ! -f "$CERT_DIR/fullchain.pem" ]; then
    echo "Issuing certificate for $DOMAIN..."
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" \
        --standalone \
        --key-file "$CERT_DIR/privkey.key" \
        --fullchain-file "$CERT_DIR/fullchain.pem" \
        --renew-hook "cd $INSTALL_DIR && docker compose restart remnanode || true"
else
    echo "Certificate already exists."
fi

# 4. Install cert + reload hook (FIXED: added --)
~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
    --key-file "$CERT_DIR/privkey.key" \
    --fullchain-file "$CERT_DIR/fullchain.pem" \
    --reloadcmd "cd $INSTALL_DIR && docker compose restart remnanode || true"

# 5. SECRET_KEY
if [ -z "$SECRET_KEY" ]; then
    read -sp "Enter SECRET_KEY from Remnawave Panel: " SECRET_KEY
    echo
fi

if [ -z "$SECRET_KEY" ]; then
    echo "SECRET_KEY is required!"
    exit 1
fi

# 6. Generate docker-compose
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
  *)
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

    mkdir -p fallback-html
    cat > fallback-html/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html><head><title>Secure Service</title></head>
<body style="font-family:system-ui;text-align:center;padding:60px">
<h1>Secure Collaborative Infrastructure</h1>
<p>This domain powers real web services.</p>
</body></html>
HTMLEOF
    ;;
esac

# 7. Firewall
if command -v ufw &> /dev/null; then
    ufw allow 443/tcp comment 'Remnawave'
    if [ -n "$PANEL_IP" ]; then
        ufw allow from "$PANEL_IP" to any port $NODE_PORT comment 'Panel'
    fi
    ufw --force enable
fi

# 8. Start
echo "Starting containers..."
docker compose up -d
docker compose ps

echo ""
echo "✅ Deployment complete for $DOMAIN"
echo "Fallback: $FALLBACK_TYPE on internal port 9443"
echo "Test: https://$DOMAIN"
