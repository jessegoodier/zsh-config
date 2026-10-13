#!/usr/bin/env bash
set -euo pipefail
HOME_DIR="${HOME:?HOME is not set}"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="$HOME_DIR/Library/Logs/zsh-config-backup.log"
KEEP=30

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG_FILE"
}

# Scheduled runs stay in the log file. A terminal run also prints the result.
say() {
    if [ -t 1 ]; then
        echo "$@"
    fi
}

fail() {
    log "FAILED: $*"
    echo "FAILED: $*" >&2
    exit 1
}

# Pick the OneDrive account that already stores these backups. Do not create it.
cloud_root="$HOME_DIR/Library/CloudStorage"
found=()
onedrives=()
for dir in "$cloud_root"/OneDrive*; do
    [ -d "$dir" ] || continue
    onedrives+=("$dir")
    if [ -d "$dir/backups/zsh-config-backups" ]; then
        found+=("$dir/backups/zsh-config-backups")
    fi
done

if [ "${#found[@]}" -eq 1 ]; then
    DEST_DIR="${found[0]}"
elif [ "${#found[@]}" -gt 1 ]; then
    echo "Multiple OneDrive folders already contain backups/zsh-config-backups:" >&2
    printf '  %s\n' "${found[@]}" >&2
    fail "multiple OneDrive folders contain backups/zsh-config-backups"
else
    echo "No OneDrive folder already contains backups/zsh-config-backups." >&2
    echo "Looked in: $cloud_root/OneDrive*/backups/zsh-config-backups" >&2
    if [ "${#onedrives[@]}" -eq 0 ]; then
        echo "No OneDrive folders found under $cloud_root." >&2
    else
        echo "OneDrive folders found:" >&2
        printf '  %s\n' "${onedrives[@]}" >&2
        echo "Create backups/zsh-config-backups in the OneDrive you want to use, then re-run." >&2
    fi
    fail "no OneDrive folder contains backups/zsh-config-backups"
fi

timestamp="$(date +%Y-%m-%d_%H%M%S)"
archive="$DEST_DIR/zsh-config-backup_${timestamp}.tgz"

if tar --exclude=".venv" --exclude=".git" --exclude="target" -czf "$archive" -C "$(dirname "$SRC_DIR")" "$(basename "$SRC_DIR")"; then
    size="$(du -h "$archive" | cut -f1)"
    log "created $archive ($size)"
    say "created $archive ($size)"
else
    rm -f "$archive"
    fail "could not create $archive"
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
