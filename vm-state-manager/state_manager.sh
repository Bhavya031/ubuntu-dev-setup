#!/bin/bash

# VM State Manager - Helper script for backup and restore operations

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_BACKUP_SCRIPT="$SCRIPT_DIR/config_backup.sh"
CONFIG_RESTORE_SCRIPT="$SCRIPT_DIR/config_restore.sh"
CONFIG_SMART_BACKUP_SCRIPT="$SCRIPT_DIR/config_smart_backup.sh"
CONFIG_SMART_RESTORE_SCRIPT="$SCRIPT_DIR/config_smart_restore.sh"
DOWNLOADS_MANAGER_SCRIPT="$SCRIPT_DIR/downloads_manager.sh"

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
    $0 list                            # List all backups for current system
    $0 list --all                      # List all backups in bucket

ENVIRONMENT VARIABLES:
    GCP_STATE_BUCKET    GCP bucket name (default: vm-states-india)

SETUP:
    Before first use, ensure:
    1. gcloud CLI is configured: gcloud auth login
    2. Set default project: gcloud config set project YOUR_PROJECT_ID
    3. (Optional) Set bucket name: export GCP_STATE_BUCKET=your-bucket-name
EOF
}

list_backups() {
    local BUCKET_NAME="${GCP_STATE_BUCKET:-vm-states-india}"
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
    echo ""
    
    if [ "$SHOW_ALL" = true ]; then
        echo "📋 All backups in bucket:"
        gsutil ls -l "gs://${BUCKET_NAME}/" | grep "\.tar\.gz$" || echo "No backups found"
    else
        echo "📋 Backups for current system:"
        gsutil ls -l "gs://${BUCKET_NAME}/state_*.tar.gz" || echo "No backups found"
    fi
}

case "${1:-help}" in
    backup)
        shift
        echo "🔄 Starting config backup process..."
        "$CONFIG_BACKUP_SCRIPT" "$@"
        ;;
    smart-backup)
        shift
        echo "🧠 Starting smart config backup process..."
        "$CONFIG_SMART_BACKUP_SCRIPT" "$@"
        ;;
    restore)
        shift
        echo "🔄 Starting config restore process..."
        "$CONFIG_RESTORE_SCRIPT" "$@"
        ;;
    smart-restore)
        shift
        echo "🧠 Starting smart config restore process..."
        "$CONFIG_SMART_RESTORE_SCRIPT" "$@"
        ;;
    sync-downloads)
        shift
        echo "📁 Starting Downloads sync..."
        "$DOWNLOADS_MANAGER_SCRIPT" "$@"
        ;;
    force-downloads)
        shift
        echo "🚀 Starting force Downloads upload..."
        "$DOWNLOADS_MANAGER_SCRIPT" force-upload "$@"
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
