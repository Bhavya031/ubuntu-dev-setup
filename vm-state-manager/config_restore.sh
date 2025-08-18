#!/bin/bash

# VM State Download Script
# Restores application configurations and states from GCP bucket

set -e

# Configuration
BUCKET_NAME="${GCP_STATE_BUCKET:-vm-states-india}"
RESTORE_DIR="/tmp/vm_state_restore_$(date +%Y%m%d_%H%M%S)"

# Parse command line arguments
USE_LATEST=false
SPECIFIC_BACKUP=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --latest)
            USE_LATEST=true
            shift
            ;;
        --backup)
            SPECIFIC_BACKUP="$2"
            shift 2
            ;;

        --bucket)
            BUCKET_NAME="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --latest           Restore from latest backup"
            echo "  --backup NAME      Restore from specific backup file"
echo "  --bucket NAME      Specify bucket name (default: vm-states-india)"
            echo "  -h, --help         Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "🔄 Starting VM state restore..."
echo "📦 Bucket: gs://${BUCKET_NAME}"
echo "🕐 Restoring from backup"

# Determine which backup to download
if [ "$USE_LATEST" = true ]; then
    BACKUP_FILE="state_latest.tar.gz"
    echo "📥 Using latest backup"
elif [ -n "$SPECIFIC_BACKUP" ]; then
    BACKUP_FILE="$SPECIFIC_BACKUP"
    echo "📥 Using specific backup: $BACKUP_FILE"
else
    echo "📋 Available backups:"
    gsutil ls "gs://${BUCKET_NAME}/state_*.tar.gz" || {
        echo "❌ No backups found"
        exit 1
    }
    echo ""
    echo "Please specify --latest or --backup <filename>"
    exit 1
fi

# Create restore directory
mkdir -p "$RESTORE_DIR"
cd "$RESTORE_DIR"

# Download backup
echo "📥 Downloading backup..."
gsutil cp "gs://${BUCKET_NAME}/$BACKUP_FILE" ./

# Extract archive
echo "📦 Extracting archive..."
tar -xzf "$BACKUP_FILE"

# Find extracted directory
EXTRACTED_DIR=$(find . -maxdepth 1 -type d -name "vm_state_backup_*" | head -1)
if [ -z "$EXTRACTED_DIR" ]; then
    echo "❌ Could not find extracted backup directory"
    exit 1
fi

cd "$EXTRACTED_DIR"

# Show backup metadata
if [ -f "state_metadata.json" ]; then
    echo "📋 Backup information:"
    cat state_metadata.json | python3 -m json.tool
    echo ""
fi

echo "🔧 Restoring application states..."

# Stop services before restoring
echo "⏹️  Stopping services..."
sudo systemctl stop jellyfin 2>/dev/null || true
sudo systemctl stop qbittorrent-nox 2>/dev/null || true

# 1. Restore Jellyfin
if [ -d "jellyfin" ]; then
    echo "  🎬 Restoring Jellyfin..."
    sudo mkdir -p /var/lib/jellyfin
    
    # Backup existing config if it exists
    if [ -d "/var/lib/jellyfin/config" ]; then
        sudo mv /var/lib/jellyfin/config "/var/lib/jellyfin/config.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    fi
    
    # Restore configurations
    [ -d "jellyfin/config" ] && sudo cp -r jellyfin/config /var/lib/jellyfin/
    [ -d "jellyfin/data" ] && sudo cp -r jellyfin/data /var/lib/jellyfin/
    [ -d "jellyfin/metadata" ] && sudo cp -r jellyfin/metadata /var/lib/jellyfin/
    
    sudo chown -R jellyfin:jellyfin /var/lib/jellyfin
    sudo chmod -R 755 /var/lib/jellyfin
fi

# 2. Restore qBittorrent-nox
if [ -d "qbittorrent" ]; then
    echo "  🌐 Restoring qBittorrent-nox..."
    sudo mkdir -p /var/lib/qbittorrent-nox
    
    # Backup existing config if it exists
    if [ -d "/var/lib/qbittorrent-nox/.config" ]; then
        sudo mv /var/lib/qbittorrent-nox/.config "/var/lib/qbittorrent-nox/.config.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    fi
    
    # Restore configurations
    [ -d "qbittorrent/.config" ] && sudo cp -r qbittorrent/.config /var/lib/qbittorrent-nox/
    [ -d "qbittorrent/.local" ] && sudo cp -r qbittorrent/.local /var/lib/qbittorrent-nox/
    
    sudo chown -R qbittorrent-nox:qbittorrent-nox /var/lib/qbittorrent-nox
fi

# 3. Restore Cloudflared
if [ -d ".cloudflared" ]; then
    echo "  ☁️  Restoring Cloudflared..."
    # Backup existing config if it exists
    if [ -d "$HOME/.cloudflared" ]; then
        mv "$HOME/.cloudflared" "$HOME/.cloudflared.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    fi
    cp -r .cloudflared "$HOME/"
fi

# 4. Restore user configurations
if [ -d "user_configs" ]; then
    echo "  ⚙️  Restoring user configurations..."
    
    # Backup existing configs
    [ -f "$HOME/.bashrc" ] && cp "$HOME/.bashrc" "$HOME/.bashrc.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    [ -f "$HOME/.tmux.conf" ] && cp "$HOME/.tmux.conf" "$HOME/.tmux.conf.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    
    # Restore configurations
    [ -f "user_configs/.bashrc" ] && cp user_configs/.bashrc "$HOME/"
    [ -f "user_configs/.bash_profile" ] && cp user_configs/.bash_profile "$HOME/"
    [ -f "user_configs/.tmux.conf" ] && cp user_configs/.tmux.conf "$HOME/"
    
    # Neovim config
    if [ -d "user_configs/nvim" ]; then
        if [ -d "$HOME/.config/nvim" ]; then
            mv "$HOME/.config/nvim" "$HOME/.config/nvim.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        fi
        mkdir -p "$HOME/.config"
        cp -r user_configs/nvim "$HOME/.config/"
    fi
    
    # Starship config
    if [ -f "user_configs/.config/starship.toml" ]; then
        mkdir -p "$HOME/.config"
        cp user_configs/.config/starship.toml "$HOME/.config/"
    fi
fi

# 5. Restore system configurations
if [ -d "system_configs" ]; then
    echo "  🔧 Restoring system configurations..."
    
    # qBittorrent systemd service
    if [ -f "system_configs/qbittorrent-nox.service" ]; then
        sudo cp system_configs/qbittorrent-nox.service /etc/systemd/system/
    fi
    
    # Performance optimizations
    if [ -f "system_configs/99-qbittorrent-performance.conf" ]; then
        sudo cp system_configs/99-qbittorrent-performance.conf /etc/sysctl.d/
        sudo sysctl -p /etc/sysctl.d/99-qbittorrent-performance.conf
    fi
    
    sudo systemctl daemon-reload
fi

# 6. Recreate media directories and permissions
echo "  📁 Setting up media directories..."
sudo mkdir -p /home/$USER/Downloads/{Movies,TV\ Shows,Music,Books}
sudo chown -R $USER:$USER /home/$USER/Downloads
sudo chmod -R 755 /home/$USER/Downloads

# Add jellyfin to user group if needed
if id jellyfin &>/dev/null; then
    sudo usermod -a -G $USER jellyfin
fi

# 7. Start services
echo "🚀 Starting services..."
sudo systemctl enable --now jellyfin 2>/dev/null || true
sudo systemctl enable --now qbittorrent-nox 2>/dev/null || true

# Wait a moment for services to start
sleep 3

# 8. Cleanup
echo "🧹 Cleaning up temporary files..."
cd /
rm -rf "$RESTORE_DIR"

echo "✅ State restore completed successfully!"
echo ""
echo "🔗 Service URLs:"
echo "  Jellyfin: http://localhost:8096"

# Get public IP for qBittorrent
PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "localhost")
echo "  qBittorrent: http://$PUBLIC_IP:5879"

echo ""
echo "📋 Service status:"
echo "  Jellyfin: $(systemctl is-active jellyfin 2>/dev/null || echo 'inactive')"
echo "  qBittorrent-nox: $(systemctl is-active qbittorrent-nox 2>/dev/null || echo 'inactive')"

echo ""
echo "⚠️  Note: Restart your terminal session to apply shell configuration changes"
