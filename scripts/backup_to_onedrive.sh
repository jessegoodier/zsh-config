#!/usr/bin/env bash
set -euo pipefail
HOME_DIR="/Users/jesse"
SRC_DIR="$HOME_DIR/git-jesse/zsh-config"
DEST_DIR="$HOME_DIR/Library/CloudStorage/OneDrive-IBM/backups/zsh-config-backups"
LOG_FILE="$HOME_DIR/Library/Logs/zsh-config-backup.log"
KEEP=30

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG_FILE"
}

mkdir -p "$DEST_DIR"

timestamp="$(date +%Y-%m-%d_%H%M%S)"
archive="$DEST_DIR/zsh-config-backup_${timestamp}.tgz"

if tar --exclude=".venv" --exclude=".git" --exclude="target" -czf "$archive" -C "$(dirname "$SRC_DIR")" "$(basename "$SRC_DIR")"; then
    size="$(du -h "$archive" | cut -f1)"
    log "created $archive ($size)"
else
    log "FAILED to create $archive"
    rm -f "$archive"
    exit 1
fi

# Retention: keep the most recent $KEEP archives, delete the rest.
# A read loop instead of mapfile, which macOS bash 3.2 does not provide.
count=0
while IFS= read -r old; do
    count=$((count + 1))
    if [ "$count" -gt "$KEEP" ]; then
        rm -f "$old"
        log "removed old backup $old"
    fi
done < <(ls -1t "$DEST_DIR"/zsh-config-backup_*.tgz 2>/dev/null)
