#!/bin/bash
# Helper script for advanced ACME (DNS challenge example)
# Usage: ./scripts/setup-acme.sh yourdomain.com

DOMAIN=$1

if [ -z "$DOMAIN" ]; then
    echo "Usage: $0 <domain>"
    exit 1
fi

# Example for Cloudflare DNS challenge (set CF_Token in env)
/root/.acme.sh/acme.sh --issue \
    --dns dns_cf \
    -d "$DOMAIN" \
    --key-file /opt/remnanode/certs/privkey.key \
    --fullchain-file /opt/remnanode/certs/fullchain.pem
