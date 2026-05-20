#!/bin/bash
set -e

DOMAIN="$1"
NODE_PORT="${2:-2222}"
SECRET_KEY="$3"

if [ -z "$DOMAIN" ]; then
    echo "Usage: sudo $0 <domain> [2222] [SECRET_KEY]"
    echo "Create the node in Remnawave Panel first to get SECRET_KEY"
    exit 1
fi

INSTALL_DIR="/opt/remnanode"
NGINX_DIR="$INSTALL_DIR/nginx"
CERT_DIR="$NGINX_DIR"
LOG_DIR="/var/log/remnanode"

 echo "=== Setting up Remnawave Node + Stealth Fallback for $DOMAIN ==="

mkdir -p "$INSTALL_DIR" "$NGINX_DIR" "$LOG_DIR"
cd "$INSTALL_DIR"

# 1. Install Docker
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker || true
fi

# 2. Install acme.sh
if [ ! -f ~/.acme.sh/acme.sh ]; then
    curl https://get.acme.sh | sh
fi

# 3. Issue certificate
if [ ! -f "$CERT_DIR/fullchain.pem" ]; then
    echo "Issuing certificate (standalone on port 8443)..."
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" \
        --standalone \
        --tlsport 8443 \
        --key-file "$CERT_DIR/privkey.key" \
        --fullchain-file "$CERT_DIR/fullchain.pem"
fi

# 4. Get SECRET_KEY
if [ -z "$SECRET_KEY" ]; then
    read -sp "Paste SECRET_KEY from Remnawave Panel: " SECRET_KEY
    echo
fi

if [ -z "$SECRET_KEY" ]; then
    echo "SECRET_KEY required"
    exit 1
fi

# 5. Generate docker-compose with correct certificate path for Remnawave
cat > docker-compose.yml << 'EOF'
services:
  remnanode:
    image: remnawave/node:latest
    restart: always
    network_mode: host
    environment:
      - NODE_PORT=${NODE_PORT}
      - SECRET_KEY=${SECRET_KEY}
    volumes:
      - ./nginx:/var/lib/remnawave/configs/xray/ssl:ro
      - ${LOG_DIR}:/var/log/remnanode

  fallback:
    image: excalidraw/excalidraw:latest
    restart: always
    networks:
      - remna

  nginx:
    image: nginx:alpine
    restart: always
    ports:
      - "9443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/fullchain.pem:/etc/nginx/ssl/fullchain.pem:ro
      - ./nginx/privkey.key:/etc/nginx/ssl/privkey.key:ro
    networks:
      - remna
    depends_on:
      - fallback

networks:
  remna:
    driver: bridge
EOF

# 6. Create nginx config
cat > nginx/nginx.conf << 'NGINXEOF'
events { worker_connections 1024; }

http {
    server {
        listen 443 ssl;
        server_name _;

        ssl_certificate /etc/nginx/ssl/fullchain.pem;
        ssl_certificate_key /etc/nginx/ssl/privkey.key;

        location / {
            proxy_pass http://fallback:80;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
NGINXEOF

# 7. Set reload hook
~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
    --key-file "$CERT_DIR/privkey.key" \
    --fullchain-file "$CERT_DIR/fullchain.pem" \
    --reloadcmd "cd $INSTALL_DIR && docker compose restart nginx || true"

# 8. Start
echo "Starting containers..."
docker compose up -d
docker compose ps

echo ""
echo "✅ Setup complete for $DOMAIN"
echo "Fallback available on https://$DOMAIN:9443"
echo "Test: https://$DOMAIN:9443"
