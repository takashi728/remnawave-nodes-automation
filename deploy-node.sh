#!/bin/bash
set -e

# ============================================
# Remnawave Node Deployment Script
# Usage: sudo ./deploy-node.sh <DOMAIN> [NODE_PORT] [SECRET_KEY] [PANEL_IP]
# Example: sudo ./deploy-node.sh node42.example.com 2222 "supersecret" "203.0.113.10"
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

echo "=== Remnawave Node Deployment for $DOMAIN ==="

# --- 1. Install Docker if missing ---
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
fi

# --- 2. Create directories ---
mkdir -p "$INSTALL_DIR" "$CERT_DIR" "$LOG_DIR"
cd "$INSTALL_DIR"

# --- 3. Install acme.sh if missing ---
if [ ! -f /root/.acme.sh/acme.sh ]; then
    echo "Installing acme.sh..."
    curl https://get.acme.sh | sh -s email=admin@$DOMAIN
fi

# --- 4. Issue certificate (standalone) ---
# Note: If port 443 is in use, stop services first or switch to DNS challenge
if [ ! -f "$CERT_DIR/fullchain.pem" ]; then
    echo "Issuing Let's Encrypt certificate for $DOMAIN ..."
    /root/.acme.sh/acme.sh --issue -d "$DOMAIN" \
        --standalone \
        --key-file "$CERT_DIR/privkey.key" \
        --fullchain-file "$CERT_DIR/fullchain.pem" || {
        echo "Certificate issuance failed. Try DNS challenge or free port 443 temporarily."
        exit 1
    }
else
    echo "Certificate already exists."
fi

# --- 5. Setup renewal hook ---
/root/.acme.sh/acme.sh install-cert -d "$DOMAIN" \
    --key-file "$CERT_DIR/privkey.key" \
    --fullchain-file "$CERT_DIR/fullchain.pem" \
    --renew-hook "cd $INSTALL_DIR && docker compose restart remnanode || true"

# --- 6. Prompt for SECRET_KEY if not provided ---
if [ -z "$SECRET_KEY" ]; then
    read -p "Enter SECRET_KEY from Remnawave Panel: " SECRET_KEY
fi

if [ -z "$SECRET_KEY" ]; then
    echo "SECRET_KEY is required."
    exit 1
fi

# --- 7. Generate docker-compose.yml ---
cat > docker-compose.yml << 'EOF'
services:
  remnanode:
    container_name: remnanode
    image: remnawave/node:latest
    restart: always
    network_mode: host
    environment:
      - NODE_PORT=${NODE_PORT}
      - SECRET_KEY=${SECRET_KEY}
    volumes:
      - ./certs:/var/lib/remnawave/configs/xray/ssl:ro
      - ${LOG_DIR}:/var/log/remnanode

  # Default lightweight fallback (nginx). Replace with Excalidraw or Matrix as needed.
  fallback:
    container_name: fallback
    image: nginx:alpine
    restart: always
    network_mode: host
    ports:
      - "9443:80"
    volumes:
      - ./fallback-html:/usr/share/nginx/html:ro
EOF

# Create simple fallback page
mkdir -p fallback-html
cat > fallback-html/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html>
<head><title>Service</title></head>
<body style="font-family:sans-serif; text-align:center; padding:50px;">
  <h1>Service Temporarily Unavailable</h1>
  <p>This domain is used for secure proxy services.</p>
</body>
</html>
HTMLEOF

# --- 8. Setup firewall ---
if command -v ufw &> /dev/null; then
    echo "Configuring UFW..."
    ufw allow 443/tcp
    if [ -n "$PANEL_IP" ]; then
        ufw allow from "$PANEL_IP" to any port ${NODE_PORT}
    else
        echo "WARNING: No PANEL_IP provided. Manually allow ${NODE_PORT} from your Panel IP."
    fi
    ufw --force enable
fi

# --- 9. Start containers ---
echo "Starting containers..."
docker compose up -d

docker compose ps

echo ""
echo "=== Deployment Complete for $DOMAIN ==="
echo "Next steps:"
echo "1. Go to Remnawave Panel and finish adding/editing the node (select Config Profile)."
echo "2. Test fallback: https://$DOMAIN"
echo "3. Test proxy connection using the node domain."
echo ""
echo "To update later: cd $INSTALL_DIR && docker compose pull && docker compose up -d"
