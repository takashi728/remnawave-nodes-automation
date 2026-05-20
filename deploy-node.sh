#!/bin/bash
set -e

DOMAIN="$1"
NODE_PORT="${2:-2222}"
SECRET_KEY="$3"
EMAIL="${4:-admin@$DOMAIN}"

if [ -z "$DOMAIN" ]; then
    echo "Usage: sudo $0 <domain> [2222] [SECRET_KEY] [email]"
    exit 1
fi

INSTALL_DIR="/opt/remnanode"
NGINX_DIR="$INSTALL_DIR/nginx"
CERT_DIR="$NGINX_DIR"
LOG_DIR="/var/log/remnanode"

 echo "=== Setting up Remnawave Node for $DOMAIN ==="

mkdir -p "$INSTALL_DIR" "$NGINX_DIR" "$LOG_DIR"
cd "$INSTALL_DIR"

# 1. Docker
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker || true
fi

# 2. Install acme.sh
if [ ! -f ~/.acme.sh/acme.sh ]; then
    curl https://get.acme.sh | sh -s email="$EMAIL"
fi

# 3. Force Let's Encrypt (avoid ZeroSSL default)
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt

# 4. Register account if needed
~/.acme.sh/acme.sh --register-account -m "$EMAIL" || true

# 5. Issue certificate
if [ ! -f "$CERT_DIR/fullchain.pem" ]; then
    echo "Issuing Let's Encrypt certificate..."
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" \
        --standalone \
        --tlsport 8443 \
        --key-file "$CERT_DIR/privkey.key" \
        --fullchain-file "$CERT_DIR/fullchain.pem"
fi

# 6. Get SECRET_KEY
if [ -z "$SECRET_KEY" ]; then
    read -sp "Paste SECRET_KEY from Remnawave Panel: " SECRET_KEY
    echo
fi

if [ -z "$SECRET_KEY" ]; then
    echo "SECRET_KEY required"
    exit 1
fi

# 7. Generate docker-compose
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

# 8. Nginx config
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

# 9. Reload hook
~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
    --key-file "$CERT_DIR/privkey.key" \
    --fullchain-file "$CERT_DIR/fullchain.pem" \
    --reloadcmd "cd $INSTALL_DIR && docker compose restart nginx || true"

# 10. Start
echo "Starting containers..."
docker compose up -d
docker compose ps

echo ""
echo "✅ Done for $DOMAIN"
echo "Test: https://$DOMAIN:9443"
