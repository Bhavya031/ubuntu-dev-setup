#!/bin/bash

# Smart Restore Script
# Intelligent restore that asks what components to restore

set -e

# Configuration
BUCKET_NAME="${GCP_STATE_BUCKET:-vm-states-india}"
VM_NAME="${VM_NAME:-$(hostname)}"
RESTORE_DIR="/tmp/vm_smart_restore_$(date +%Y%m%d_%H%M%S)"

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
        --vm-name)
            VM_NAME="$2"
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
            echo "  --vm-name NAME     Specify VM name (default: hostname)"
            echo "  --bucket NAME      Specify bucket name (default: vm-states-backup)"
            echo "  -h, --help         Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "🧠 Smart Restore: Choose what to restore..."
echo "📦 Bucket: gs://${BUCKET_NAME}"
echo "🖥️  VM: ${VM_NAME}"

# Determine which backup to download
if [ "$USE_LATEST" = true ]; then
    BACKUP_FILE="${VM_NAME}_state_latest.tar.gz"
    echo "📥 Using latest backup"
elif [ -n "$SPECIFIC_BACKUP" ]; then
    BACKUP_FILE="$SPECIFIC_BACKUP"
    echo "📥 Using specific backup: $BACKUP_FILE"
else
    echo "📋 Available backups:"
    gsutil ls "gs://${BUCKET_NAME}/${VM_NAME}_state_*.tar.gz" || {
        echo "❌ No backups found for VM: $VM_NAME"
        exit 1
    }
    echo ""
    echo "Please specify --latest or --backup <filename>"
    exit 1
fi

# Create restore directory
mkdir -p "$RESTORE_DIR"
cd "$RESTORE_DIR"

# Download and extract backup
echo "📥 Downloading backup..."
gsutil cp "gs://${BUCKET_NAME}/$BACKUP_FILE" ./
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

# Ask what to restore
echo "🔧 What would you like to restore?"
echo ""

# Check available components
RESTORE_JELLYFIN=false
RESTORE_QBITTORRENT=false
RESTORE_CLOUDFLARED=false
RESTORE_USER_CONFIGS=false
RESTORE_SYSTEM_CONFIGS=false

if [ -d "jellyfin" ]; then
    read -p "🎬 Restore Jellyfin configuration and database? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && RESTORE_JELLYFIN=true
fi

if [ -d "qbittorrent" ]; then
    read -p "🌐 Restore qBittorrent-nox configuration and torrents? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && RESTORE_QBITTORRENT=true
fi

if [ -d ".cloudflared" ]; then
    read -p "☁️  Restore Cloudflared tunnels and certificates? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && RESTORE_CLOUDFLARED=true
fi

if [ -d "user_configs" ]; then
    read -p "⚙️  Restore user configurations (.bashrc, .tmux.conf, nvim)? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && RESTORE_USER_CONFIGS=true
fi

if [ -d "system_configs" ]; then
    read -p "🔧 Restore system configurations (services, performance)? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && RESTORE_SYSTEM_CONFIGS=true
fi

# Confirm before proceeding
echo ""
echo "📋 Restore Summary:"
echo "  Jellyfin: $([ "$RESTORE_JELLYFIN" = true ] && echo "✅ YES" || echo "❌ NO")"
echo "  qBittorrent: $([ "$RESTORE_QBITTORRENT" = true ] && echo "✅ YES" || echo "❌ NO")"
echo "  Cloudflared: $([ "$RESTORE_CLOUDFLARED" = true ] && echo "✅ YES" || echo "❌ NO")"
echo "  User configs: $([ "$RESTORE_USER_CONFIGS" = true ] && echo "✅ YES" || echo "❌ NO")"
echo "  System configs: $([ "$RESTORE_SYSTEM_CONFIGS" = true ] && echo "✅ YES" || echo "❌ NO")"
echo ""
read -p "Proceed with restore? (y/N): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Restore cancelled"
    rm -rf "$RESTORE_DIR"
    exit 0
fi

echo "🔧 Starting selective restore..."

# Stop services that will be restored
if [ "$RESTORE_JELLYFIN" = true ] || [ "$RESTORE_QBITTORRENT" = true ]; then
    echo "⏹️  Stopping services..."
    [ "$RESTORE_JELLYFIN" = true ] && sudo systemctl stop jellyfin 2>/dev/null || true
    [ "$RESTORE_QBITTORRENT" = true ] && sudo systemctl stop qbittorrent-nox 2>/dev/null || true
fi

# Restore Jellyfin
if [ "$RESTORE_JELLYFIN" = true ] && [ -d "jellyfin" ]; then
    echo "  🎬 Restoring Jellyfin..."
    sudo mkdir -p /var/lib/jellyfin
    
    if [ -d "/var/lib/jellyfin/config" ]; then
        sudo mv /var/lib/jellyfin/config "/var/lib/jellyfin/config.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    fi
    
    [ -d "jellyfin/config" ] && sudo cp -r jellyfin/config /var/lib/jellyfin/
    [ -d "jellyfin/data" ] && sudo cp -r jellyfin/data /var/lib/jellyfin/
    [ -d "jellyfin/metadata" ] && sudo cp -r jellyfin/metadata /var/lib/jellyfin/
    
    sudo chown -R jellyfin:jellyfin /var/lib/jellyfin
    sudo chmod -R 755 /var/lib/jellyfin
fi

# Restore qBittorrent-nox
if [ "$RESTORE_QBITTORRENT" = true ] && [ -d "qbittorrent" ]; then
    echo "  🌐 Restoring qBittorrent-nox..."
    sudo mkdir -p /var/lib/qbittorrent-nox
    
    if [ -d "/var/lib/qbittorrent-nox/.config" ]; then
        sudo mv /var/lib/qbittorrent-nox/.config "/var/lib/qbittorrent-nox/.config.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    fi
    
    [ -d "qbittorrent/.config" ] && sudo cp -r qbittorrent/.config /var/lib/qbittorrent-nox/
    [ -d "qbittorrent/.local" ] && sudo cp -r qbittorrent/.local /var/lib/qbittorrent-nox/
    
    sudo chown -R qbittorrent-nox:qbittorrent-nox /var/lib/qbittorrent-nox
fi

# Restore Cloudflared
if [ "$RESTORE_CLOUDFLARED" = true ] && [ -d ".cloudflared" ]; then
    echo "  ☁️  Restoring Cloudflared..."
    if [ -d "$HOME/.cloudflared" ]; then
        mv "$HOME/.cloudflared" "$HOME/.cloudflared.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    fi
    cp -r .cloudflared "$HOME/"
fi

# Restore user configurations
if [ "$RESTORE_USER_CONFIGS" = true ] && [ -d "user_configs" ]; then
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

# Restore system configurations
if [ "$RESTORE_SYSTEM_CONFIGS" = true ] && [ -d "system_configs" ]; then
    echo "  🔧 Restoring system configurations..."
    
    if [ -f "system_configs/qbittorrent-nox.service" ]; then
        sudo cp system_configs/qbittorrent-nox.service /etc/systemd/system/
    fi
    
    if [ -f "system_configs/99-qbittorrent-performance.conf" ]; then
        sudo cp system_configs/99-qbittorrent-performance.conf /etc/sysctl.d/
        sudo sysctl -p /etc/sysctl.d/99-qbittorrent-performance.conf
    fi
    
    sudo systemctl daemon-reload
fi

# Recreate media directories and permissions
echo "  📁 Setting up media directories..."
sudo mkdir -p /home/$USER/Downloads/{Movies,TV\ Shows,Music,Books}
sudo chown -R $USER:$USER /home/$USER/Downloads
sudo chmod -R 755 /home/$USER/Downloads

# Add jellyfin to user group if needed
if id jellyfin &>/dev/null; then
    sudo usermod -a -G $USER jellyfin
fi

# Start restored services
echo "🚀 Starting restored services..."
[ "$RESTORE_JELLYFIN" = true ] && sudo systemctl enable --now jellyfin 2>/dev/null || true
[ "$RESTORE_QBITTORRENT" = true ] && sudo systemctl enable --now qbittorrent-nox 2>/dev/null || true

# Wait for services to start
sleep 3

# Cleanup
echo "🧹 Cleaning up temporary files..."
cd /
rm -rf "$RESTORE_DIR"

echo "✅ Smart restore completed successfully!"
echo ""
echo "🔗 Service URLs:"
echo "  Jellyfin: http://localhost:8096"

PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "localhost")
echo "  qBittorrent: http://$PUBLIC_IP:5879"

echo ""
echo "📋 Service status:"
echo "  Jellyfin: $(systemctl is-active jellyfin 2>/dev/null || echo 'inactive')"
echo "  qBittorrent-nox: $(systemctl is-active qbittorrent-nox 2>/dev/null || echo 'inactive')"

echo ""
echo "⚠️  Note: Restart your terminal session to apply shell configuration changes"
