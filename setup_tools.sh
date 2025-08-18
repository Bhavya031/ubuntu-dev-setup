#!/bin/bash

# Ubuntu 24.04 Development Tools Setup Script
# This script installs Starship, tmux, Neovim, Jellyfin, btop, and cloudflared

set -e

echo "🚀 Starting Ubuntu 24.04 Development Tools Setup..."

# Update package lists
echo "📦 Updating package lists..."
sudo apt update

# Install dependencies
echo "📋 Installing required dependencies..."
sudo apt install -y curl git apt-transport-https ca-certificates gnupg2

# Install Starship
echo "⭐ Installing Starship..."
curl -sS https://starship.rs/install.sh | sh -s -- -y

# Safe Starship initialization with error handling
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)" 2>/dev/null || true
fi

# Safe PATH export with error handling
if [ -d "$HOME/bin" ]; then
    export PATH="$HOME/bin:$PATH"
fi

# Install tmux
echo "🖥️  Installing tmux..."
sudo apt install -y tmux

# Download and apply tmux configuration
echo "⚙️  Applying tmux configuration..."
curl -o ~/.tmux.conf https://gist.githubusercontent.com/Bhavya031/9a1cc9d391564fc62aca089504e297dd/raw

# Install Neovim
echo "📝 Installing Neovim..."
sudo apt install -y neovim

# Clone Neovim configuration
echo "⚙️  Setting up Neovim configuration..."
if [ -d ~/.config/nvim ]; then
    echo "   Backing up existing nvim config..."
    mv ~/.config/nvim ~/.config/nvim.backup.$(date +%Y%m%d_%H%M%S)
fi
mkdir -p ~/.config
git clone https://github.com/Bhavya031/nvim ~/.config/nvim

# Add Jellyfin repository
echo "🎬 Setting up Jellyfin repository..."
curl -fsSL https://repo.jellyfin.org/jellyfin_team.gpg.key | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/jellyfin.gpg
echo "deb [signed-by=/etc/apt/trusted.gpg.d/jellyfin.gpg] https://repo.jellyfin.org/ubuntu $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/jellyfin.list

# Update package lists with Jellyfin repo
sudo apt update

# Install Jellyfin
echo "🎬 Installing Jellyfin..."
sudo apt install -y jellyfin

# Enable and start  service
sudo systemctl enable --now jellyfin

echo "📁 Setting up media directories..."
sudo usermod -a -G $USER jellyfin
sudo systemctl restart jellyfin

# Install btop
echo "📊 Installing btop..."
sudo apt install -y btop

echo "🌐 Installing qBittorrent-nox static..."
bash <(curl -sL https://raw.githubusercontent.com/userdocs/qbittorrent-nox-static/refs/heads/master/qi.bash)

if ! grep -q 'export PATH="$HOME/bin:$PATH"' ~/.bashrc; then
    echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
fi
source ~/.bashrc

echo "⚡ Setting up qBittorrent-nox..."

# Create system user if it doesn't exist
if ! id "qbittorrent-nox" &>/dev/null; then
    sudo useradd --system --shell /usr/sbin/nologin --home-dir /var/lib/qbittorrent-nox --create-home qbittorrent-nox
fi

# Create required directories with proper structure
sudo mkdir -p /var/lib/qbittorrent-nox/.config/qBittorrent
sudo mkdir -p /var/lib/qbittorrent-nox/.local/share/qBittorrent/logs
sudo mkdir -p /var/lib/qbittorrent-nox/Downloads/{Movies,TV\ Shows,Music,Books}

# Copy binary to system location where service expects it
sudo cp ~/bin/qbittorrent-nox /usr/local/bin/
sudo chmod +x /usr/local/bin/qbittorrent-nox

# Set proper ownership and permissions
sudo chown -R qbittorrent-nox:qbittorrent-nox /var/lib/qbittorrent-nox
sudo chmod 775 /var/lib/qbittorrent-nox/Downloads

# Add current user to qbittorrent-nox group for shared access
sudo usermod -a -G qbittorrent-nox $USER

# Create symlink from user Downloads to shared directory
if [ ! -L ~/Downloads ]; then
    if [ -d ~/Downloads ]; then
        mv ~/Downloads ~/Downloads.old.$(date +%Y%m%d_%H%M%S)
    fi
    ln -s /var/lib/qbittorrent-nox/Downloads ~/Downloads
fi

echo "🔧 Setting up systemd service..."
sudo curl -fsSL https://gist.githubusercontent.com/Bhavya031/958301e7315284f035e67d5e8472c84b/raw -o /etc/systemd/system/qbittorrent-nox.service

echo "🌐 Applying system-level performance optimizations..."
sudo curl -fsSL https://gist.githubusercontent.com/Bhavya031/f5c1ef36decd60509532dd8c4b1929b5/raw -o /etc/sysctl.d/99-qbittorrent-performance.conf

sudo sysctl -p /etc/sysctl.d/99-qbittorrent-performance.conf
sudo systemctl daemon-reload
sudo systemctl enable qbittorrent-nox

# Start the service to verify it works
echo "🚀 Starting qBittorrent-nox service..."
sudo systemctl start qbittorrent-nox

# Wait a moment and check service status
sleep 3
if sudo systemctl is-active --quiet qbittorrent-nox; then
    echo "✅ qBittorrent-nox service started successfully!"
else
    echo "⚠️  Service may have issues. Check with: sudo systemctl status qbittorrent-nox"
fi

echo "ℹ️  qBittorrent-nox installed and configured. WebUI available at http://localhost:5879"
echo "📁 Shared media directories created in /var/lib/qbittorrent-nox/Downloads/"
echo "🔗 Your ~/Downloads now links to the shared directory"

echo "☁️  Installing cloudflared..."
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt-get update && sudo apt-get install -y cloudflared

PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "localhost")

echo "✅ Setup complete!"
echo "Jellyfin: http://localhost:8096"
echo "qBittorrent: http://$PUBLIC_IP:5879"
echo "Restart terminal for Starship prompt"
echo ""
echo "🔄 State Management Commands:"
echo "📱 Application configs (quick):"
echo "  cd $(dirname "$0") && ./vm-state-manager/state_manager.sh backup"
echo "  cd $(dirname "$0") && ./vm-state-manager/state_manager.sh restore --latest"
echo ""
echo "🧠 Smart config backup/restore (detects changes, asks what to do):"
echo "  cd $(dirname "$0") && ./vm-state-manager/state_manager.sh smart-backup"
echo "  cd $(dirname "$0") && ./vm-state-manager/state_manager.sh smart-restore --latest"
echo ""
echo "📁 Downloads folder management (large media files):"
echo "  cd $(dirname "$0") && ./vm-state-manager/state_manager.sh force-downloads"
echo "  cd $(dirname "$0") && ./vm-state-manager/downloads_manager.sh download-folders"
echo "  cd $(dirname "$0") && ./vm-state-manager/downloads_manager.sh download-select"
echo ""
echo "📋 List backups:"
echo "  cd $(dirname "$0") && ./vm-state-manager/state_manager.sh list"
echo ""
echo "🔄 Auto-restoring your saved state..."
cd "$(dirname "$0")"
./vm-state-manager/state_manager.sh restore --latest