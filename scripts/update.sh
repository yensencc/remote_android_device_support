#!/usr/bin/env bash
# Re-renders configs from .env and restarts the stack (also picks up renewed TLS
# certificates in the MDM's keystore). Pinned image versions come from .env.
set -euo pipefail
cd "$(dirname "$0")/.."
./install.sh --no-ufw
docker compose up -d --force-recreate hmdm janus
