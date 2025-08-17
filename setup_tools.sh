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

# Add Starship to bashrc if not already present
if ! grep -q "starship init bash" ~/.bashrc; then
    echo 'eval "$(starship init bash)"' >> ~/.bashrc
    echo "✅ Added Starship to bashrc"
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
sudo mkdir -p /home/$USER/Downloads/{Movies,TV\ Shows,Music,Books}
sudo chown -R $USER:$USER /home/$USER/Downloads
sudo chmod -R 755 /home/$USER/Downloads
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

sudo useradd --system --shell /usr/sbin/nologin --home-dir /var/lib/qbittorrent-nox --create-home qbittorrent-nox
sudo mkdir -p /var/lib/qbittorrent-nox/.config/qBittorrent
sudo mkdir -p /var/lib/qbittorrent-nox/.local/share/qBittorrent/logs

echo "🔧 Setting up systemd service..."
sudo curl -fsSL https://gist.githubusercontent.com/Bhavya031/958301e7315284f035e67d5e8472c84b/raw -o /etc/systemd/system/qbittorrent-nox.service

echo "🌐 Applying system-level performance optimizations..."
sudo curl -fsSL https://gist.githubusercontent.com/Bhavya031/f5c1ef36decd60509532dd8c4b1929b5/raw -o /etc/sysctl.d/99-qbittorrent-performance.conf

sudo sysctl -p /etc/sysctl.d/99-qbittorrent-performance.conf
sudo chown -R qbittorrent-nox:qbittorrent-nox /var/lib/qbittorrent-nox
sudo systemctl daemon-reload
sudo systemctl enable qbittorrent-nox

echo "ℹ️  qBittorrent-nox installed. Use state management scripts to restore configuration."

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
echo "Application configs (quick):"
echo "  cd $(dirname "$0") && ./vm-state-manager/state_manager.sh backup"
echo "  cd $(dirname "$0") && ./vm-state-manager/state_manager.sh restore --latest"
echo ""
echo "Smart backup/restore (detects changes, asks what to do):"
echo "  cd $(dirname "$0") && ./vm-state-manager/state_manager.sh smart-backup"
echo "  cd $(dirname "$0") && ./vm-state-manager/state_manager.sh smart-restore --latest"
echo ""
echo "Downloads folder sync (for large media files):"
echo "  cd $(dirname "$0") && ./vm-state-manager/state_manager.sh sync-downloads upload"
echo "  cd $(dirname "$0") && ./vm-state-manager/state_manager.sh sync-downloads sync"
echo ""
echo "List backups:"
echo "  cd $(dirname "$0") && ./vm-state-manager/state_manager.sh list"
echo ""
echo "🔄 Auto-restoring your saved state..."
cd "$(dirname "$0")"
./vm-state-manager/state_manager.sh restore --latest