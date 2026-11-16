#!/usr/bin/env bash
# Stops and removes the containers and nginx sites. Keeps ./data, .env and the
# certificates unless --purge is given (which deletes ALL MDM data irreversibly).
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose down
rm -f /etc/nginx/sites-enabled/remote-support-*.conf /etc/nginx/sites-available/remote-support-*.conf
nginx -t -q && systemctl reload nginx
if [[ "${1:-}" == "--purge" ]]; then
  read -r -p "Delete ALL MDM data in $(pwd)/data? Type DELETE: " ok
  [[ "$ok" == "DELETE" ]] && rm -rf data generated && echo "Data deleted."
fi
