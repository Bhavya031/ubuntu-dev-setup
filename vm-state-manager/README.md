# VM State Manager

Complete state management system for Ubuntu development VMs with intelligent backup/restore and Downloads synchronization.

## 📁 Files Overview

### Main Interface
- **`state_manager.sh`** - Unified interface for all operations

### 📱 Config/State Management Scripts
- **`config_backup.sh`** - Quick backup of application configurations
- **`config_restore.sh`** - Quick restore of application configurations
- **`config_smart_backup.sh`** - Intelligent backup with change detection
- **`config_smart_restore.sh`** - Interactive restore with component selection

### 📁 Downloads Management Scripts
- **`downloads_manager.sh`** - Complete Downloads folder management (files, folders, sync)

## 📋 File Naming Convention

### **`config_*` files** = Application configurations (small, frequent)
- Jellyfin settings, qBittorrent configs, Cloudflared certificates
- Quick backup/restore (~4MB, ~11 seconds)
- Handles: databases, settings, user configs, system configs

### **`downloads_*` files** = Large media files (big, occasional)  
- Movies, TV shows, music, books from Downloads folder
- High-performance sync (~26+ MiB/s)
- Handles: selective downloads, folder management, bulk operations

## 🎯 What Gets Managed

### Application States (Small, frequent backups)
- **Jellyfin**: Configuration, database, metadata, user settings
- **qBittorrent-nox**: Configuration, torrent states, download history, advanced settings
- **Cloudflared**: Tunnel configurations, certificates, authentication
- **User configs**: .bashrc, .tmux.conf, Neovim configuration, Starship settings
- **System configs**: Systemd services, performance optimizations

### Downloads Folder (Large media files)
- **Movies, TV Shows, Music, Books** - Handled separately for performance
- **Smart sync** with change detection
- **Force upload** option for bulk operations

## 🚀 Quick Start

### Basic Operations
```bash
# Create backup of application states
./state_manager.sh backup

# Restore from latest backup
./state_manager.sh restore --latest

# List available backups
./state_manager.sh list
```

### Smart Operations
```bash
# Smart backup (detects deleted files/folders, asks what to do)
./state_manager.sh smart-backup

# Smart restore (choose what components to restore)
./state_manager.sh smart-restore --latest
```

### Downloads Management
**Note: Downloads operations require sudo permissions for file system access.**

```bash
# Force upload all Downloads (no questions, overwrite existing)
sudo ./state_manager.sh force-downloads

# OR use downloads manager directly:
sudo ./downloads_manager.sh force-upload          # Force upload all (no questions)
sudo ./downloads_manager.sh download-folders      # Select specific folders
sudo ./downloads_manager.sh download-select       # Select specific files
sudo ./downloads_manager.sh sync                  # Smart two-way sync
sudo ./downloads_manager.sh list-files           # List available files
sudo ./downloads_manager.sh list-folders         # List available folders
```

## 📊 Performance Optimizations

### High-Speed Transfers
- **32 parallel threads** for maximum throughput
- **16 parallel processes** for CPU optimization
- **Composite uploads** for files >10MB (automatic chunking)
- **Sliced downloads** for large file downloads
- **India region buckets** (asia-south1) for optimal performance from India

### Typical Performance
- **Application states**: ~4MB backup in ~11 seconds
- **Downloads sync**: ~26 MiB/s for large media files
- **Regional optimization**: 2-3x faster than US region buckets

## 🔧 Configuration

### Environment Variables
```bash
# Config/State management bucket (small files)
export GCP_STATE_BUCKET=vm-states-india          # Default: vm-states-india

# Downloads management bucket (large media files)  
export GCP_DOWNLOADS_BUCKET=vm-downloads-india   # Default: vm-downloads-india

# VM identification
export VM_NAME=my-custom-vm-name                 # Default: hostname
```

### Prerequisites
```bash
# Authenticate with GCP
gcloud auth login

# Set your project
gcloud config set project YOUR_PROJECT_ID
```

## 📋 Detailed Command Reference

### State Management Commands

#### `state_manager.sh backup`
- Quick backup of all application states
- Creates timestamped and "latest" copies
- ~4MB archive with all configurations

#### `state_manager.sh smart-backup`
- Analyzes changes since last backup
- Detects deleted folders and asks if you want to remove them
- Detects deleted files and asks if you want to remove them
- Creates clean, up-to-date backups

#### `state_manager.sh restore --latest`
- Restores all application states from latest backup
- Automatically stops/starts services
- Backs up existing configs before overwriting

#### `state_manager.sh smart-restore --latest`
- Interactive restore process
- Choose which components to restore:
  - 🎬 Jellyfin (database, configuration)
  - 🌐 qBittorrent-nox (settings, torrents)
  - ☁️ Cloudflared (tunnels, certificates)
  - ⚙️ User configs (shell, tools)
  - 🔧 System configs (services, performance)

### Downloads Manager Commands

#### `downloads_manager.sh force-upload`
- **No questions asked** - uploads everything
- **Overwrites existing files** in bucket
- **High-performance** parallel upload (26+ MiB/s)
- Perfect for bulk operations

#### `downloads_manager.sh download-folders`
- **Interactive folder selection**
- Choose specific folders: Movies, Music, TV Shows, Books
- **Preserves folder structure** exactly
- Example: Select "1,3" to download Movies and Music folders

#### `downloads_manager.sh download-select`
- **Interactive file selection**
- Choose specific files from any folder
- **Individual file control**
- Example: Select "2,5,7" to download specific movies

#### `downloads_manager.sh list-folders`
- Shows all available folders with file counts
- Example: "📁 Movies/ (15 files)"

#### `downloads_manager.sh list-files`
- Shows all available files with folder organization
- Example: "📁 Movies/ 📄 movie_name.mkv (2.1GB)"

### Downloads Sync Commands

#### `state_manager.sh force-downloads`
- **No questions asked** - uploads everything
- **Overwrites existing files** in bucket
- **High-performance** parallel upload
- Perfect for bulk operations

#### `state_manager.sh sync-downloads sync`
- Smart two-way synchronization
- Detects missing files locally and remotely
- Asks what you want to download/upload
- Preserves bandwidth by only transferring differences

#### `state_manager.sh sync-downloads upload`
- Standard upload with sync logic
- Only uploads new/changed files
- Preserves existing files in bucket

#### `state_manager.sh sync-downloads download`
- Downloads all files from bucket
- Merges with existing local files
- High-performance parallel download

## 🏗️ Architecture

### Bucket Structure
```
gs://vm-states-india/
├── {VM_NAME}_state_latest.tar.gz           # Latest backup
├── {VM_NAME}_state_YYYYMMDD_HHMMSS.tar.gz  # Timestamped backups
└── {VM_NAME}_state_latest_metadata.json    # Backup metadata

gs://vm-downloads-india/
├── {VM_NAME}_downloads/                    # Downloads folder mirror
│   ├── Movies/
│   ├── TV Shows/
│   ├── Music/
│   └── Books/
└── {VM_NAME}_downloads_manifest_latest.txt # File manifest
```

### Backup Contents
Each state backup includes:
- Application data and configurations
- User shell and tool configurations  
- System service configurations
- Metadata with backup info and service status
- Permission and ownership information

## 🔒 Security & Privacy

- **Private buckets** - Only you can access your backups
- **Regional storage** - Data stays in India region
- **Encrypted in transit** - All transfers use HTTPS
- **No sensitive data** in public scripts
- **Automatic cleanup** of temporary files

## 🛠️ Troubleshooting

### Common Issues

**Slow uploads/downloads:**
- Ensure you're using India region buckets
- Check network connectivity
- Consider adjusting parallel thread counts

**Permission errors:**
- Downloads operations require sudo: `sudo ./state_manager.sh force-downloads`
- Run `gcloud auth login` to re-authenticate
- Check project permissions: `gcloud config get-value project`

**Service restore failures:**
- Services are automatically stopped/started during restore
- Check service status: `systemctl status jellyfin qbittorrent-nox`

**Missing backups:**
- Use `./state_manager.sh list` to see available backups
- Check bucket name and VM name settings

### Performance Tuning

For different network speeds, you can adjust parallel settings:
```bash
# For slower connections (reduce load)
gsutil -o "GSUtil:parallel_thread_count=8" -o "GSUtil:parallel_process_count=4" ...

# For faster connections (increase throughput)  
gsutil -o "GSUtil:parallel_thread_count=64" -o "GSUtil:parallel_process_count=32" ...
```

## 🎯 Usage Workflows

### First-Time Setup
1. Run main setup script: `../setup_tools.sh`
2. Configure applications manually (Jellyfin libraries, qBittorrent settings)
3. Create initial backup: `./state_manager.sh backup`
4. Upload Downloads: `sudo ./state_manager.sh force-downloads`

### Regular Backup
```bash
# Quick config backup
./state_manager.sh backup

# Smart config backup (recommended - detects changes)
./state_manager.sh smart-backup

# Force upload all Downloads (no questions)
sudo ./state_manager.sh force-downloads

# OR selective Downloads management:
sudo ./downloads_manager.sh download-folders    # Choose specific folders to download
sudo ./downloads_manager.sh download-select     # Choose specific files to download
```

### New VM Setup
1. Run setup script: `../setup_tools.sh` (auto-restores configs)
2. Restore Downloads: 
   ```bash
   # Download everything
   sudo ./downloads_manager.sh download
   
   # OR be selective:
   sudo ./downloads_manager.sh download-folders    # Choose folders
   sudo ./downloads_manager.sh download-select     # Choose files
   ```

### Selective Operations
```bash
# Only restore specific config components
./state_manager.sh smart-restore --latest

# Selective Downloads management
sudo ./downloads_manager.sh list-folders         # See available folders
sudo ./downloads_manager.sh download-folders     # Download specific folders
sudo ./downloads_manager.sh list-files          # See available files  
sudo ./downloads_manager.sh download-select     # Download specific files
```

## 📈 Performance Metrics

### Tested Performance (India region)
- **State backup**: 4MB in 11 seconds
- **Downloads upload**: 1.8GB in 25 seconds (26 MiB/s)
- **Downloads download**: 1.6GB in 34 seconds (51 MiB/s)
- **Bucket creation**: Automatic in asia-south1 region

### Optimization Features
- Multi-threaded uploads (32 threads)
- Multi-process operations (16 processes)
- Composite uploads for large files (>10MB)
- Sliced downloads for large files (>10MB)
- Regional optimization for Indian users
