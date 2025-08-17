#!/bin/bash

# Downloads Folder Sync Script
# Syncs Downloads folder with GCP bucket for large media files

set -e

# Configuration
BUCKET_NAME="${GCP_DOWNLOADS_BUCKET:-vm-downloads-india}"
VM_NAME="${VM_NAME:-$(hostname)}"
DOWNLOADS_DIR="/home/$USER/Downloads"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

show_help() {
    cat << EOF
Downloads Sync Manager

USAGE:
    $0 <command> [options]

COMMANDS:
    upload              Upload Downloads folder to bucket
    force-upload        Force upload everything, overwrite existing files
    download            Download Downloads folder from bucket
    sync                Two-way sync (upload new, download missing)
    list                List Downloads backups in bucket
    help                Show this help message

EXAMPLES:
    $0 upload                          # Upload current Downloads folder
    $0 force-upload                    # Force upload all, overwrite existing
    $0 download                        # Download and merge Downloads folder
    $0 sync                           # Smart two-way sync
    $0 list                           # List available Downloads backups

ENVIRONMENT VARIABLES:
    GCP_DOWNLOADS_BUCKET    Bucket for Downloads (default: vm-downloads-backup)
    VM_NAME                 VM identifier (default: hostname)

NOTE: This handles large media files separately from application configs
EOF
}

upload_downloads() {
    echo "📤 Uploading Downloads folder..."
    echo "📦 Bucket: gs://${BUCKET_NAME}"
    echo "📁 Source: $DOWNLOADS_DIR"
    
    if [ ! -d "$DOWNLOADS_DIR" ]; then
        echo "❌ Downloads directory not found: $DOWNLOADS_DIR"
        exit 1
    fi
    
    # Create bucket if it doesn't exist (in India region for better performance)
    gsutil mb -p $(gcloud config get-value project) -l asia-south1 "gs://${BUCKET_NAME}" 2>/dev/null || true
    
    # Create manifest of current files
    echo "📋 Creating file manifest..."
    find "$DOWNLOADS_DIR" -type f -exec stat -c "%n|%s|%Y" {} \; > "/tmp/downloads_manifest_${TIMESTAMP}.txt"
    
    # Upload manifest
    gsutil cp "/tmp/downloads_manifest_${TIMESTAMP}.txt" "gs://${BUCKET_NAME}/${VM_NAME}_downloads_manifest_latest.txt"
    
    # Sync Downloads folder with optimized parallel settings
    echo "🔄 Syncing Downloads folder with high-performance settings..."
    gsutil -o "GSUtil:parallel_thread_count=32" -o "GSUtil:parallel_process_count=16" \
           -o "GSUtil:parallel_composite_upload_threshold=10M" \
           -o "GSUtil:parallel_composite_upload_component_size=10M" \
           -m rsync -r -d "$DOWNLOADS_DIR" "gs://${BUCKET_NAME}/${VM_NAME}_downloads/"
    
    # Cleanup
    rm -f "/tmp/downloads_manifest_${TIMESTAMP}.txt"
    
    echo "✅ Downloads upload completed!"
}

force_upload_downloads() {
    echo "🚀 Force uploading Downloads folder (no questions, overwrite existing)..."
    echo "📦 Bucket: gs://${BUCKET_NAME}"
    echo "📁 Source: $DOWNLOADS_DIR"
    
    if [ ! -d "$DOWNLOADS_DIR" ]; then
        echo "❌ Downloads directory not found: $DOWNLOADS_DIR"
        exit 1
    fi
    
    # Create bucket if it doesn't exist (in India region for better performance)
    gsutil mb -p $(gcloud config get-value project) -l asia-south1 "gs://${BUCKET_NAME}" 2>/dev/null || true
    
    # Force upload everything with overwrite, no questions asked
    echo "🔄 Force uploading all Downloads with high-performance settings..."
    gsutil -o "GSUtil:parallel_thread_count=32" -o "GSUtil:parallel_process_count=16" \
           -o "GSUtil:parallel_composite_upload_threshold=10M" \
           -o "GSUtil:parallel_composite_upload_component_size=10M" \
           -m cp -r "$DOWNLOADS_DIR"/* "gs://${BUCKET_NAME}/${VM_NAME}_downloads/"
    
    # Create and upload manifest
    echo "📋 Creating and uploading file manifest..."
    find "$DOWNLOADS_DIR" -type f -exec stat -c "%n|%s|%Y" {} \; > "/tmp/downloads_manifest_${TIMESTAMP}.txt"
    gsutil cp "/tmp/downloads_manifest_${TIMESTAMP}.txt" "gs://${BUCKET_NAME}/${VM_NAME}_downloads_manifest_latest.txt"
    rm -f "/tmp/downloads_manifest_${TIMESTAMP}.txt"
    
    echo "✅ Force upload completed! All files uploaded and existing files overwritten."
}

download_downloads() {
    echo "📥 Downloading Downloads folder..."
    echo "📦 Bucket: gs://${BUCKET_NAME}"
    echo "📁 Target: $DOWNLOADS_DIR"
    
    # Check if bucket exists
    if ! gsutil ls "gs://${BUCKET_NAME}/${VM_NAME}_downloads/" &>/dev/null; then
        echo "❌ No Downloads backup found for VM: $VM_NAME"
        exit 1
    fi
    
    # Create Downloads directory if it doesn't exist
    mkdir -p "$DOWNLOADS_DIR"
    
    # Download Downloads folder with optimized parallel settings
    echo "🔄 Syncing Downloads folder with high-performance settings..."
    gsutil -o "GSUtil:parallel_thread_count=32" -o "GSUtil:parallel_process_count=16" \
           -o "GSUtil:sliced_object_download_threshold=10M" \
           -o "GSUtil:sliced_object_download_max_components=8" \
           -m rsync -r "gs://${BUCKET_NAME}/${VM_NAME}_downloads/" "$DOWNLOADS_DIR"
    
    # Fix permissions
    chown -R $USER:$USER "$DOWNLOADS_DIR"
    chmod -R 755 "$DOWNLOADS_DIR"
    
    echo "✅ Downloads download completed!"
}

smart_sync() {
    echo "🧠 Smart sync: Analyzing differences..."
    
    # Get remote manifest if it exists
    REMOTE_MANIFEST="/tmp/remote_manifest_${TIMESTAMP}.txt"
    LOCAL_MANIFEST="/tmp/local_manifest_${TIMESTAMP}.txt"
    
    if gsutil cp "gs://${BUCKET_NAME}/${VM_NAME}_downloads_manifest_latest.txt" "$REMOTE_MANIFEST" 2>/dev/null; then
        echo "📋 Found remote manifest"
    else
        echo "📋 No remote manifest found, will upload everything"
        upload_downloads
        return
    fi
    
    # Create local manifest
    if [ -d "$DOWNLOADS_DIR" ]; then
        find "$DOWNLOADS_DIR" -type f -exec stat -c "%n|%s|%Y" {} \; > "$LOCAL_MANIFEST"
    else
        touch "$LOCAL_MANIFEST"
    fi
    
    # Find files that exist remotely but not locally
    echo "🔍 Checking for files to download..."
    MISSING_LOCAL=$(comm -23 <(cut -d'|' -f1 "$REMOTE_MANIFEST" | sort) <(cut -d'|' -f1 "$LOCAL_MANIFEST" | sort) | head -10)
    
    if [ -n "$MISSING_LOCAL" ]; then
        echo "📥 Files available for download:"
        echo "$MISSING_LOCAL"
        echo ""
        read -p "Download missing files? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            download_downloads
        fi
    fi
    
    # Find files that exist locally but not remotely
    echo "🔍 Checking for files to upload..."
    MISSING_REMOTE=$(comm -13 <(cut -d'|' -f1 "$REMOTE_MANIFEST" | sort) <(cut -d'|' -f1 "$LOCAL_MANIFEST" | sort) | head -10)
    
    if [ -n "$MISSING_REMOTE" ]; then
        echo "📤 New local files to upload:"
        echo "$MISSING_REMOTE"
        echo ""
        read -p "Upload new files? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            upload_downloads
        fi
    fi
    
    # Cleanup
    rm -f "$REMOTE_MANIFEST" "$LOCAL_MANIFEST"
    
    echo "✅ Smart sync completed!"
}

list_downloads() {
    local BUCKET_NAME="${GCP_DOWNLOADS_BUCKET:-vm-downloads-india}"
    local VM_NAME="${VM_NAME:-$(hostname)}"
    
    echo "📦 Bucket: gs://${BUCKET_NAME}"
    echo "🖥️  VM: ${VM_NAME}"
    echo ""
    echo "📋 Downloads backups:"
    gsutil ls -l "gs://${BUCKET_NAME}/${VM_NAME}_downloads*" 2>/dev/null || echo "No Downloads backups found"
}

case "${1:-help}" in
    upload)
        upload_downloads
        ;;
    force-upload)
        force_upload_downloads
        ;;
    download)
        download_downloads
        ;;
    sync)
        smart_sync
        ;;
    list)
        list_downloads
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
