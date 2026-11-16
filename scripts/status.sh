#!/usr/bin/env bash
# Quick health check: containers, memory, listening ports, certificate expiry.
set -uo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
docker compose ps
echo; free -h
echo; ss -tulpn | grep -E ':(80|443|8080|8088|8188|31000)\b' 
for d in "$MDM_DOMAIN" "$REMOTE_DOMAIN"; do
  printf '%s cert expires: ' "$d"
  openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$d/cert.pem" 2>/dev/null | cut -d= -f2
  printf '%s https: ' "$d"; curl -s -o /dev/null -w '%{http_code}\n' "https://$d/"
done
