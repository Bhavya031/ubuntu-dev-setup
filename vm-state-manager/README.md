# VM State Manager

Complete state management system for Ubuntu development VMs with intelligent backup/restore and Downloads synchronization.

## 📁 Files Overview

### Core Scripts
- **`state_manager.sh`** - Main interface for all state management operations
- **`upload_state.sh`** - Creates and uploads application state backups
- **`download_state.sh`** - Downloads and restores application states
- **`smart_backup.sh`** - Intelligent backup with change detection
- **`smart_restore.sh`** - Interactive restore with component selection
- **`sync_downloads.sh`** - High-performance Downloads folder synchronization

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
```bash
# Force upload all Downloads (no questions, overwrite existing)
./state_manager.sh force-downloads

# Smart sync Downloads folder
./state_manager.sh sync-downloads sync

# Upload Downloads folder
./state_manager.sh sync-downloads upload

# Download Downloads folder
./state_manager.sh sync-downloads download
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
# State management buckets
export GCP_STATE_BUCKET=vm-states-india          # Default: vm-states-india
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
4. Upload Downloads: `./state_manager.sh force-downloads`

### Regular Backup
```bash
# Quick backup
./state_manager.sh backup

# Smart backup (recommended)
./state_manager.sh smart-backup

# Backup Downloads
./state_manager.sh force-downloads
```

### New VM Setup
1. Run setup script: `../setup_tools.sh` (auto-restores states)
2. Restore Downloads: `./state_manager.sh sync-downloads download`

### Selective Operations
```bash
# Only restore specific components
./state_manager.sh smart-restore --latest

# Only sync specific Downloads changes
./state_manager.sh sync-downloads sync
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
