#!/bin/bash
set -e

# ============================================
# Remnawave Node Deployment Script
# Primary input: DOMAIN (e.g. node42.example.com)
# Usage: sudo ./deploy-node.sh node42.example.com [2222] ["your-secret"] ["panel-ip"]
# ============================================

DOMAIN="$1"
NODE_PORT="${2:-2222}"
SECRET_KEY="$3"
PANEL_IP="${4:-}"

if [ -z "$DOMAIN" ]; then
    echo "Error: DOMAIN is required"
    echo "Usage: $0 <domain> [node_port] [secret_key] [panel_ip]"
    exit 1
fi

INSTALL_DIR="/opt/remnanode"
CERT_DIR="$INSTALL_DIR/certs"
LOG_DIR="/var/log/remnanode"

echo "=== Remnawave Node Deployment ==="
echo "Domain: $DOMAIN"

# Install Docker
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker || true
fi

mkdir -p "$INSTALL_DIR" "$CERT_DIR" "$LOG_DIR"
cd "$INSTALL_DIR"

# acme.sh
if [ ! -f ~/.acme.sh/acme.sh ]; then
    curl https://get.acme.sh | sh
fi

# Issue certificate
if [ ! -f "$CERT_DIR/fullchain.pem" ]; then
    echo "Issuing certificate for $DOMAIN (standalone mode)..."
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" \
        --standalone \
        --key-file "$CERT_DIR/privkey.key" \
        --fullchain-file "$CERT_DIR/fullchain.pem" || {
        echo "Failed. Try DNS challenge or temporarily stop other services on port 443."
        exit 1
    }
fi

# Renewal hook
~/.acme.sh/acme.sh install-cert -d "$DOMAIN" \
    --key-file "$CERT_DIR/privkey.key" \
    --fullchain-file "$CERT_DIR/fullchain.pem" \
    --renew-hook "cd $INSTALL_DIR && docker compose restart remnanode || true"

# SECRET_KEY prompt
if [ -z "$SECRET_KEY" ]; then
    read -sp "Paste SECRET_KEY from Panel: " SECRET_KEY
    echo
fi

if [ -z "$SECRET_KEY" ]; then
    echo "SECRET_KEY required"
    exit 1
fi

# Generate docker-compose.yml (variables expanded)
cat > docker-compose.yml << 'COMPOSEEOF'
services:
  remnanode:
    container_name: remnanode
    image: remnawave/node:latest
    restart: always
    network_mode: host
    environment:
      - NODE_PORT=PLACEHOLDER_NODE_PORT
      - SECRET_KEY=PLACEHOLDER_SECRET
    volumes:
      - ./certs:/var/lib/remnawave/configs/xray/ssl:ro
      - /var/log/remnanode:/var/log/remnanode

  fallback:
    container_name: fallback
    image: nginx:alpine
    restart: always
    network_mode: host
    ports:
      - "9443:80"
    volumes:
      - ./fallback-html:/usr/share/nginx/html:ro
COMPOSEEOF

# Replace placeholders
sed -i "s/PLACEHOLDER_NODE_PORT/$NODE_PORT/g" docker-compose.yml
sed -i "s/PLACEHOLDER_SECRET/$SECRET_KEY/g" docker-compose.yml

# Fallback HTML
mkdir -p fallback-html
cat > fallback-html/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html><head><title>Service</title></head>
<body style="text-align:center;font-family:sans-serif;padding:40px">
<h1>Secure Infrastructure</h1>
<p>This domain is active for proxy services.</p>
</body></html>
HTMLEOF

# Firewall
if command -v ufw &> /dev/null; then
    ufw allow 443/tcp
    [ -n "$PANEL_IP" ] && ufw allow from "$PANEL_IP" to any port $NODE_PORT
    ufw --force enable
fi

# Start
echo "Starting services..."
docker compose up -d
docker compose ps

echo ""
echo "✅ Node for $DOMAIN is ready!"
echo "Visit https://$DOMAIN to test fallback."
echo "Complete setup in Remnawave Panel UI."
