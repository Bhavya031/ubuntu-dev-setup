#!/bin/bash

# VM State Manager - Helper script for backup and restore operations

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPLOAD_SCRIPT="$SCRIPT_DIR/upload_state.sh"
DOWNLOAD_SCRIPT="$SCRIPT_DIR/download_state.sh"
SMART_BACKUP_SCRIPT="$SCRIPT_DIR/smart_backup.sh"
SMART_RESTORE_SCRIPT="$SCRIPT_DIR/smart_restore.sh"
SYNC_DOWNLOADS_SCRIPT="$SCRIPT_DIR/sync_downloads.sh"

show_help() {
    cat << EOF
VM State Manager

USAGE:
    $0 <command> [options]

COMMANDS:
    backup              Create a backup of current VM state
    smart-backup        Intelligent backup (detects deleted files/folders)
    restore             Restore VM state from backup
    smart-restore       Interactive restore (choose what to restore)
    sync-downloads      Sync Downloads folder with bucket
    force-downloads     Force upload all Downloads (no questions, overwrite)
    list                List available backups
    help                Show this help message

BACKUP EXAMPLES:
    $0 backup                           # Create backup with default settings
    
RESTORE EXAMPLES:
    $0 restore --latest                 # Restore from latest backup
    $0 restore --backup filename.tar.gz # Restore from specific backup
    
LIST EXAMPLES:
    $0 list                            # List all backups for current VM
    $0 list --all                      # List all backups in bucket

ENVIRONMENT VARIABLES:
    GCP_STATE_BUCKET    GCP bucket name (default: vm-states-india)
    VM_NAME             VM identifier (default: hostname)

SETUP:
    Before first use, ensure:
    1. gcloud CLI is configured: gcloud auth login
    2. Set default project: gcloud config set project YOUR_PROJECT_ID
    3. (Optional) Set bucket name: export GCP_STATE_BUCKET=your-bucket-name
EOF
}

list_backups() {
    local BUCKET_NAME="${GCP_STATE_BUCKET:-vm-states-backup}"
    local VM_NAME="${VM_NAME:-$(hostname)}"
    local SHOW_ALL=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all)
                SHOW_ALL=true
                shift
                ;;
            *)
                echo "Unknown option for list: $1"
                exit 1
                ;;
        esac
    done
    
    echo "📦 Bucket: gs://${BUCKET_NAME}"
    echo "🖥️  VM: ${VM_NAME}"
    echo ""
    
    if [ "$SHOW_ALL" = true ]; then
        echo "📋 All backups in bucket:"
        gsutil ls -l "gs://${BUCKET_NAME}/" | grep "\.tar\.gz$" || echo "No backups found"
    else
        echo "📋 Backups for VM '$VM_NAME':"
        gsutil ls -l "gs://${BUCKET_NAME}/${VM_NAME}_state_*.tar.gz" || echo "No backups found for this VM"
    fi
}

case "${1:-help}" in
    backup)
        shift
        echo "🔄 Starting backup process..."
        "$UPLOAD_SCRIPT" "$@"
        ;;
    smart-backup)
        shift
        echo "🧠 Starting smart backup process..."
        "$SMART_BACKUP_SCRIPT" "$@"
        ;;
    restore)
        shift
        echo "🔄 Starting restore process..."
        "$DOWNLOAD_SCRIPT" "$@"
        ;;
    smart-restore)
        shift
        echo "🧠 Starting smart restore process..."
        "$SMART_RESTORE_SCRIPT" "$@"
        ;;
    sync-downloads)
        shift
        echo "📁 Starting Downloads sync..."
        "$SYNC_DOWNLOADS_SCRIPT" "$@"
        ;;
    force-downloads)
        shift
        echo "🚀 Starting force Downloads upload..."
        "$SYNC_DOWNLOADS_SCRIPT" force-upload "$@"
        ;;
    list)
        shift
        list_backups "$@"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
