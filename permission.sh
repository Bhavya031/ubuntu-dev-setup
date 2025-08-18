# Ensure groups exist and membership is correct
sudo usermod -a -G qbittorrent-nox "$USER"
sudo usermod -a -G qbittorrent-nox jellyfin
sudo usermod -a -G jellyfin "$USER"

# Fix ownership, group, and setgid on base dirs
sudo chown -R qbittorrent-nox:qbittorrent-nox /var/lib/qbittorrent-nox
sudo chmod 2775 /var/lib/qbittorrent-nox
sudo chmod 2775 /var/lib/qbittorrent-nox/Downloads
sudo find /var/lib/qbittorrent-nox/Downloads -type d -exec chmod 2775 {} \;

# Ensure ACLs so group access sticks
sudo apt-get install -y acl
sudo setfacl -m g:qbittorrent-nox:rx /var/lib/qbittorrent-nox
sudo setfacl -R -m g:qbittorrent-nox:rwx -m d:g:qbittorrent-nox:rwx /var/lib/qbittorrent-nox/Downloads

# If your shell is still using old groups, re-login or:
newgrp qbittorrent-nox <<'EOF'
echo "Switched into qbittorrent-nox group for this shell"
EOF