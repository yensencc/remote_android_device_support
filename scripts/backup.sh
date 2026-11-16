#!/usr/bin/env bash
# Daily backup: MDM database dump + uploaded files + secrets, kept for 14 days.
# Cron (installed by install.sh is not assumed):  15 3 * * * /opt/remote-support/scripts/backup.sh
# Copy backups OFF this server too (they contain secrets: store them encrypted).
set -euo pipefail
cd "$(dirname "$0")/.."
DEST="${BACKUP_DIR:-/var/backups/remote-support}"
STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DEST" && chmod 700 "$DEST"
docker compose exec -T postgresql pg_dump -U hmdm -d hmdm --clean | gzip > "$DEST/hmdm-db-$STAMP.sql.gz"
tar -czf "$DEST/hmdm-files-$STAMP.tar.gz" data/hmdm-work/files data/hmdm-work/plugins .env 2>/dev/null || true
chmod 600 "$DEST"/*-"$STAMP".*
find "$DEST" -type f -mtime +14 -delete
echo "Backup written to $DEST ($STAMP)"
