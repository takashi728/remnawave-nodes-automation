# Remnawave Nodes Automation

Automated deployment scripts for **80+ Remnawave Nodes**.

**Focus**: Per-node domains + ACME SSL certificates + VLESS + xHTTP + TLS + Fallback (on port 9443).

**Panel setup is excluded** — create nodes in the Remnawave Panel UI first to obtain `SECRET_KEY`.

## Features
- One-command (or scripted) deployment per node
- Automatic ACME (Let's Encrypt) certificate issuance & renewal
- Docker-based fallback service (lightweight nginx example + ready for Excalidraw / Matrix)
- Secure firewall rules (only Panel IP can reach node management port)
- Designed for mass deployment (80+ nodes)
- `DOMAIN` as primary input variable

## Quick Start

### 1. Prerequisites on each Node server
```bash
# Run as root
apt update && apt install -y curl ufw
```

### 2. Create Node in Panel first
1. Go to your Remnawave Panel → **Nodes → Management** → **+ Create new node**
2. Fill in the details (use your node domain or IP)
3. Note down:
   - `NODE_PORT` (default 2222)
   - `SECRET_KEY` (generated)

### 3. Deploy a Node
```bash
# Clone this repo
git clone https://github.com/takashi728/remnawave-nodes-automation.git
cd remnawave-nodes-automation

# Make executable
chmod +x deploy-node.sh

# Deploy with your domain (example)
sudo ./deploy-node.sh node42.example.com 2222 "your-secret-key-here" "YOUR_PANEL_IP"
```

**Arguments**:
- `$1` **DOMAIN** (required) — e.g. `node42.example.com`
- `$2` **NODE_PORT** (optional, default `2222`)
- `$3` **SECRET_KEY** (optional, will prompt if missing)
- `$4` **PANEL_IP** (optional, for firewall)

## What the script does
1. Installs Docker (if missing)
2. Creates `/opt/remnanode` directory
3. Installs & runs `acme.sh` for Let's Encrypt certificate
4. Generates `docker-compose.yml` with:
   - `remnawave/node` container (with your certs mounted)
   - Fallback service (nginx on port 9443 by default)
5. Configures UFW firewall
6. Starts the containers
7. Prints next steps (add node in Panel UI if not done)

## Customization
- Edit `templates/docker-compose.node.yml` to change fallback or add volumes
- For **Excalidraw** or **Matrix** as fallback: replace the fallback service in the generated compose
- Use DNS-01 challenge in `deploy-node.sh` for fully automated multi-node deployments

## Scaling to 80+ Nodes
- Run the script on each new VPS
- Or wrap it in Ansible / simple loop script
- All nodes can share the same Config Profile in Remnawave Panel

## Important Notes
- Run as **root**
- Port 443 must be free during initial ACME issuance (or use DNS challenge)
- After deployment, visit `https://your-domain.com` — you should see the fallback page
- Renewals are handled automatically via acme.sh hook

## File Structure
```
.
├── README.md
├── deploy-node.sh          # Main deployment script (DOMAIN variable)
├── templates/
│   ├── docker-compose.node.yml
│   └── fallback.nginx.conf
├── scripts/
│   ├── setup-acme.sh
│   └── setup-firewall.sh
└── LICENSE
```

## License
MIT
