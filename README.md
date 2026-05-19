# Remnawave Nodes Automation

**Stealth-focused deployment for 80+ Remnawave Nodes**

Each node uses its own domain + real-looking web application as fallback for maximum camouflage.

## Recommended Stealth Fallbacks (2026)

| Fallback       | Stealth Level | Resource Usage | Recommendation      | Description                          |
|----------------|---------------|----------------|---------------------|--------------------------------------|
| **Excalidraw** | Excellent     | Very Low       | **Best choice**     | Professional collaborative whiteboard |
| **HedgeDoc**   | Excellent     | Low            | Strong alternative  | Real-time collaborative Markdown notes |
| nginx (improved) | Good        | Minimal        | Lightweight         | Clean landing page                   |

**Excalidraw** is now the recommended default for best stealth.

## Quick Deploy with Excalidraw (Recommended)

```bash
sudo ./deploy-node.sh node42.example.com 2222 "YOUR_SECRET" "YOUR_PANEL_IP" excalidraw
```

## Features
- Real web applications as fallback (not fake pages)
- Official Docker images (Excalidraw, HedgeDoc, nginx)
- ACME SSL with auto-renewal
- Easy to scale to 80+ nodes
- DOMAIN as primary input variable

## How to Deploy

```bash
git clone https://github.com/takashi728/remnawave-nodes-automation.git
cd remnawave-nodes-automation
chmod +x deploy-node.sh

# Deploy with Excalidraw (recommended)
sudo ./deploy-node.sh node42.example.com excalidraw

# Or with HedgeDoc
sudo ./deploy-node.sh node42.example.com hedgedoc
```

The 5th argument now accepts the fallback type: `excalidraw`, `hedgedoc`, or `nginx`.

See full instructions below.