#!/bin/bash

# VM State Upload Script
# Backs up application configurations and states to GCP bucket

set -e

# Configuration
BUCKET_NAME="${GCP_STATE_BUCKET:-vm-states-india}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/vm_state_backup_${TIMESTAMP}"
ARCHIVE_NAME="state_${TIMESTAMP}.tar.gz"

echo "🔄 Starting VM state backup..."
echo "📦 Bucket: gs://${BUCKET_NAME}"
echo "🕐 Timestamp: ${TIMESTAMP}"

# Create temporary backup directory
mkdir -p "$BACKUP_DIR"

echo "📋 Collecting application states..."

# 1. Jellyfin configuration and database
echo "  🎬 Backing up Jellyfin..."
if [ -d "/var/lib/jellyfin" ]; then
    sudo mkdir -p "$BACKUP_DIR/jellyfin"
    sudo cp -r /var/lib/jellyfin/config "$BACKUP_DIR/jellyfin/" 2>/dev/null || true
    sudo cp -r /var/lib/jellyfin/data "$BACKUP_DIR/jellyfin/" 2>/dev/null || true
    sudo cp -r /var/lib/jellyfin/metadata "$BACKUP_DIR/jellyfin/" 2>/dev/null || true
    sudo chown -R $USER:$USER "$BACKUP_DIR/jellyfin"
fi

# 2. qBittorrent-nox configuration and state
echo "  🌐 Backing up qBittorrent-nox..."
if [ -d "/var/lib/qbittorrent-nox" ]; then
    sudo mkdir -p "$BACKUP_DIR/qbittorrent"
    sudo cp -r /var/lib/qbittorrent-nox/.config "$BACKUP_DIR/qbittorrent/" 2>/dev/null || true
    sudo cp -r /var/lib/qbittorrent-nox/.local "$BACKUP_DIR/qbittorrent/" 2>/dev/null || true
    sudo chown -R $USER:$USER "$BACKUP_DIR/qbittorrent"
fi

# 3. Cloudflared configuration
echo "  ☁️  Backing up Cloudflared..."
if [ -d "$HOME/.cloudflared" ]; then
    cp -r "$HOME/.cloudflared" "$BACKUP_DIR/"
fi

# 4. User configurations
echo "  ⚙️  Backing up user configurations..."
mkdir -p "$BACKUP_DIR/user_configs"

# Bash configuration
[ -f "$HOME/.bashrc" ] && cp "$HOME/.bashrc" "$BACKUP_DIR/user_configs/"
[ -f "$HOME/.bash_profile" ] && cp "$HOME/.bash_profile" "$BACKUP_DIR/user_configs/"

# Tmux configuration
[ -f "$HOME/.tmux.conf" ] && cp "$HOME/.tmux.conf" "$BACKUP_DIR/user_configs/"

# Neovim configuration
if [ -d "$HOME/.config/nvim" ]; then
    cp -r "$HOME/.config/nvim" "$BACKUP_DIR/user_configs/"
fi

# Starship configuration
if [ -f "$HOME/.config/starship.toml" ]; then
    mkdir -p "$BACKUP_DIR/user_configs/.config"
    cp "$HOME/.config/starship.toml" "$BACKUP_DIR/user_configs/.config/"
fi

# 5. System configurations
echo "  🔧 Backing up system configurations..."
sudo mkdir -p "$BACKUP_DIR/system_configs"

# qBittorrent systemd service
if [ -f "/etc/systemd/system/qbittorrent-nox.service" ]; then
    sudo cp "/etc/systemd/system/qbittorrent-nox.service" "$BACKUP_DIR/system_configs/"
fi

# Performance optimizations
if [ -f "/etc/sysctl.d/99-qbittorrent-performance.conf" ]; then
    sudo cp "/etc/sysctl.d/99-qbittorrent-performance.conf" "$BACKUP_DIR/system_configs/"
fi

sudo chown -R $USER:$USER "$BACKUP_DIR/system_configs"

# 6. Create state metadata
echo "  📝 Creating state metadata..."
cat > "$BACKUP_DIR/state_metadata.json" << EOF
{
  "backup_timestamp": "$TIMESTAMP",
  "backup_date": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "user": "$USER",
  "applications": {
    "jellyfin": $([ -d "/var/lib/jellyfin" ] && echo "true" || echo "false"),
    "qbittorrent": $([ -d "/var/lib/qbittorrent-nox" ] && echo "true" || echo "false"),
    "cloudflared": $([ -d "$HOME/.cloudflared" ] && echo "true" || echo "false")
  },
  "services_status": {
    "jellyfin": "$(systemctl is-active jellyfin 2>/dev/null || echo 'inactive')",
    "qbittorrent-nox": "$(systemctl is-active qbittorrent-nox 2>/dev/null || echo 'inactive')"
  }
}
EOF

# 7. Create archive
echo "📦 Creating archive..."
cd "$(dirname "$BACKUP_DIR")"
tar -czf "$ARCHIVE_NAME" "$(basename "$BACKUP_DIR")"

# 8. Upload to GCP bucket
echo "☁️  Uploading to GCP bucket..."
gsutil mb -p $(gcloud config get-value project) -l asia-south1 "gs://${BUCKET_NAME}" 2>/dev/null || true
gsutil cp "$ARCHIVE_NAME" "gs://${BUCKET_NAME}/"

# Also upload as "latest" for easy access
gsutil cp "$ARCHIVE_NAME" "gs://${BUCKET_NAME}/state_latest.tar.gz"

# 9. Cleanup
echo "🧹 Cleaning up temporary files..."
rm -rf "$BACKUP_DIR"
rm -f "$ARCHIVE_NAME"

echo "✅ State backup completed successfully!"
echo "📍 Backup location: gs://${BUCKET_NAME}/$ARCHIVE_NAME"
echo "📍 Latest backup: gs://${BUCKET_NAME}/state_latest.tar.gz"

# Optional: List recent backups
echo ""
echo "📋 Recent backups:"
gsutil ls -l "gs://${BUCKET_NAME}/state_*.tar.gz" | tail -5
