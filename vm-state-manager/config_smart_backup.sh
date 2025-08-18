#!/bin/bash

# Smart Backup Script
# Intelligent backup that detects changes and asks user what to do

set -e

# Configuration
BUCKET_NAME="${GCP_STATE_BUCKET:-vm-states-india}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TEMP_DIR="/tmp/smart_backup_${TIMESTAMP}"

echo "🧠 Smart Backup: Analyzing changes..."
echo "📦 Bucket: gs://${BUCKET_NAME}"
echo "🕐 Timestamp: ${TIMESTAMP}"

# Create temp directory
mkdir -p "$TEMP_DIR"

# Download latest backup metadata if it exists
LATEST_METADATA="$TEMP_DIR/latest_metadata.json"
if gsutil cp "gs://${BUCKET_NAME}/state_latest_metadata.json" "$LATEST_METADATA" 2>/dev/null; then
    echo "📋 Found previous backup metadata"
    
    # Extract previous file list
    PREV_BACKUP="$TEMP_DIR/prev_backup.tar.gz"
    gsutil cp "gs://${BUCKET_NAME}/state_latest.tar.gz" "$PREV_BACKUP"
    cd "$TEMP_DIR"
    tar -tzf "prev_backup.tar.gz" > prev_files.txt
    cd - >/dev/null
else
    echo "📋 No previous backup found, creating first backup"
    # Run regular backup
    cd "$(dirname "$0")"
    ./upload_state.sh
    exit 0
fi

# Create current file manifest
echo "📋 Creating current file manifest..."
CURRENT_FILES="$TEMP_DIR/current_files.txt"

# Check Jellyfin files
if [ -d "/var/lib/jellyfin" ]; then
    find /var/lib/jellyfin -type f 2>/dev/null | sed 's|^/var/lib/jellyfin|jellyfin|' >> "$CURRENT_FILES"
fi

# Check qBittorrent files
if [ -d "/var/lib/qbittorrent-nox" ]; then
    find /var/lib/qbittorrent-nox -type f 2>/dev/null | sed 's|^/var/lib/qbittorrent-nox|qbittorrent|' >> "$CURRENT_FILES"
fi

# Check user configs
[ -f "$HOME/.bashrc" ] && echo "user_configs/.bashrc" >> "$CURRENT_FILES"
[ -f "$HOME/.tmux.conf" ] && echo "user_configs/.tmux.conf" >> "$CURRENT_FILES"
[ -d "$HOME/.config/nvim" ] && find "$HOME/.config/nvim" -type f | sed "s|^$HOME/|user_configs/|" >> "$CURRENT_FILES"
[ -d "$HOME/.cloudflared" ] && find "$HOME/.cloudflared" -type f | sed "s|^$HOME/||" >> "$CURRENT_FILES"

sort "$CURRENT_FILES" > "$TEMP_DIR/current_sorted.txt"
sort "$TEMP_DIR/prev_files.txt" > "$TEMP_DIR/prev_sorted.txt"

# Find deleted files (in previous backup but not current)
DELETED_FILES="$TEMP_DIR/deleted_files.txt"
comm -23 "$TEMP_DIR/prev_sorted.txt" "$TEMP_DIR/current_sorted.txt" > "$DELETED_FILES"

# Find deleted folders (check for missing directory patterns)
DELETED_FOLDERS="$TEMP_DIR/deleted_folders.txt"
if [ -s "$DELETED_FILES" ]; then
    # Extract directory paths and find missing directories
    cut -d'/' -f1-2 "$DELETED_FILES" | sort -u > "$TEMP_DIR/deleted_dirs_candidate.txt"
    
    while read -r dir_pattern; do
        if [ -n "$dir_pattern" ] && ! grep -q "^${dir_pattern}/" "$TEMP_DIR/current_sorted.txt"; then
            echo "$dir_pattern" >> "$DELETED_FOLDERS"
        fi
    done < "$TEMP_DIR/deleted_dirs_candidate.txt"
fi

# Check for deleted folders
if [ -s "$DELETED_FOLDERS" ]; then
    echo ""
    echo "🗂️  Detected deleted folders since last backup:"
    cat "$DELETED_FOLDERS"
    echo ""
    read -p "Delete these folders from backup? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "✅ Will exclude deleted folders from backup"
        EXCLUDE_DELETED_FOLDERS=true
    else
        echo "ℹ️  Will keep deleted folders in backup"
        EXCLUDE_DELETED_FOLDERS=false
    fi
else
    EXCLUDE_DELETED_FOLDERS=false
fi

# Check for deleted individual files (not in subfolders)
DELETED_ROOT_FILES="$TEMP_DIR/deleted_root_files.txt"
if [ -s "$DELETED_FILES" ]; then
    # Find files that are in root directories (not subfolders)
    grep -E '^[^/]+/[^/]+$' "$DELETED_FILES" > "$DELETED_ROOT_FILES" || true
fi

if [ -s "$DELETED_ROOT_FILES" ]; then
    echo ""
    echo "🗃️  Detected deleted files since last backup:"
    head -10 "$DELETED_ROOT_FILES"
    [ $(wc -l < "$DELETED_ROOT_FILES") -gt 10 ] && echo "... and $(( $(wc -l < "$DELETED_ROOT_FILES") - 10 )) more"
    echo ""
    read -p "Delete these files from backup? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "✅ Will exclude deleted files from backup"
        EXCLUDE_DELETED_FILES=true
    else
        echo "ℹ️  Will keep deleted files in backup"
        EXCLUDE_DELETED_FILES=false
    fi
else
    EXCLUDE_DELETED_FILES=false
fi

# Cleanup temp directory
rm -rf "$TEMP_DIR"

echo ""
echo "🔄 Running backup with your preferences..."

# Set environment variables for the backup script
export EXCLUDE_DELETED_FOLDERS
export EXCLUDE_DELETED_FILES

# Run the backup
cd "$(dirname "$0")"
./upload_state.sh

echo "✅ Smart backup completed!"
