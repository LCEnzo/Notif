#!/bin/sh
set -eu

DB_PATH="${SQLITE_PATH:-/app/data/db.sqlite3}"
BACKUP_DIR="${BACKUP_DIR:-$(dirname "$DB_PATH")/backups}"
KEEP="${BACKUP_KEEP:-10}"

mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/db-$TIMESTAMP.sqlite3"

sqlite3 "$DB_PATH" ".backup '$BACKUP_FILE'"

# Rotate: keep only the $KEEP most recent backups
ls -1t "$BACKUP_DIR"/db-*.sqlite3 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -f

echo "Backed up to $BACKUP_FILE (keeping $KEEP most recent)"
