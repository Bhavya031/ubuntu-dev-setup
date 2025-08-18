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
    download-select     Interactively select specific files to download
    download-folders    Interactively select folders to download
    sync                Two-way sync (upload new, download missing)
    list                List Downloads backups in bucket
    list-files          List all files available for download
    list-folders        List all folders available for download
    help                Show this help message

EXAMPLES:
    $0 upload                          # Upload current Downloads folder
    $0 force-upload                    # Force upload all, overwrite existing
    $0 download                        # Download and merge Downloads folder
    $0 download-select                 # Choose specific files to download
    $0 download-folders                # Choose specific folders to download
    $0 sync                           # Smart two-way sync
    $0 list                           # List available Downloads backups
    $0 list-files                     # Show all files available for download
    $0 list-folders                   # Show all folders available for download

ENVIRONMENT VARIABLES:
    GCP_DOWNLOADS_BUCKET    Bucket for Downloads (default: vm-downloads-backup)
    VM_NAME                 VM identifier (default: hostname)

NOTE: This handles large media files separately from application configs
EOF
}

upload_downloads() {
    local SUBPATH="${2:-}"
    local SOURCE_DIR="$DOWNLOADS_DIR"

    if [ -n "$SUBPATH" ]; then
        if [[ "$SUBPATH" = /* ]]; then
            SOURCE_DIR="$SUBPATH"
        else
            SOURCE_DIR="$DOWNLOADS_DIR/$SUBPATH"
        fi
    fi

    echo "📤 Uploading: $SOURCE_DIR"
    echo "📦 Bucket: gs://${BUCKET_NAME}"

    if [ ! -e "$SOURCE_DIR" ]; then
        echo "❌ Not found: $SOURCE_DIR"
        exit 1
    fi

    sudo gsutil mb -p "$(gcloud config get-value project)" -l asia-south1 "gs://${BUCKET_NAME}" 2>/dev/null || true

    # For full-folder uploads, create and upload a manifest
    if [ -z "$SUBPATH" ]; then
        echo "📋 Creating file manifest..."
        sudo find "$DOWNLOADS_DIR" -type f -exec stat -c "%n|%s|%Y" {} \; > "/tmp/downloads_manifest_${TIMESTAMP}.txt"
        sudo gsutil cp "/tmp/downloads_manifest_${TIMESTAMP}.txt" "gs://${BUCKET_NAME}/${VM_NAME}_downloads_manifest_latest.txt"
    fi

    if [ -f "$SOURCE_DIR" ]; then
        base="$(basename "$SOURCE_DIR")"
        parent_dir="$(dirname "$SOURCE_DIR")"
        if [[ "$SOURCE_DIR" == "$DOWNLOADS_DIR"/* ]]; then
            if [ "$parent_dir" = "$DOWNLOADS_DIR" ]; then
                dest_path="gs://${BUCKET_NAME}/${VM_NAME}_downloads/${base}"
            else
                parent="$(basename "$parent_dir")"
                dest_path="gs://${BUCKET_NAME}/${VM_NAME}_downloads/${parent}/${base}"
            fi
        else
            dest_path="gs://${BUCKET_NAME}/${VM_NAME}_downloads/${base}"
        fi
        sudo gsutil -o "GSUtil:parallel_thread_count=32" -o "GSUtil:parallel_process_count=16" -m cp "$SOURCE_DIR" "$dest_path"
    else
        if [ "$SOURCE_DIR" = "$DOWNLOADS_DIR" ]; then
            sudo gsutil -o "GSUtil:parallel_thread_count=32" -o "GSUtil:parallel_process_count=16" \
                -o "GSUtil:parallel_composite_upload_threshold=10M" \
                -o "GSUtil:parallel_composite_upload_component_size=10M" \
                -m rsync -r -d "$SOURCE_DIR" "gs://${BUCKET_NAME}/${VM_NAME}_downloads/"
        else
            sudo gsutil -o "GSUtil:parallel_thread_count=32" -o "GSUtil:parallel_process_count=16" \
                -o "GSUtil:parallel_composite_upload_threshold=10M" \
                -o "GSUtil:parallel_composite_upload_component_size=10M" \
                -m rsync -r -d "$SOURCE_DIR" "gs://${BUCKET_NAME}/${VM_NAME}_downloads/$(basename "$SOURCE_DIR")/"
        fi
    fi

    if [ -z "$SUBPATH" ]; then
        rm -f "/tmp/downloads_manifest_${TIMESTAMP}.txt"
    fi

    echo "✅ Upload complete"
}

force_upload_downloads() {
    local SUBPATH="${2:-}"
    local SOURCE_DIR="$DOWNLOADS_DIR"

    if [ -n "$SUBPATH" ]; then
        if [[ "$SUBPATH" = /* ]]; then
            SOURCE_DIR="$SUBPATH"
        else
            SOURCE_DIR="$DOWNLOADS_DIR/$SUBPATH"
        fi
    fi

    echo "🚀 Force uploading: $SOURCE_DIR (overwrite existing)"
    echo "📦 Bucket: gs://${BUCKET_NAME}"

    if [ ! -e "$SOURCE_DIR" ]; then
        echo "❌ Not found: $SOURCE_DIR"
        exit 1
    fi

    # Create bucket if it doesn't exist (in India region for better performance)
    sudo gsutil mb -p "$(gcloud config get-value project)" -l asia-south1 "gs://${BUCKET_NAME}" 2>/dev/null || true

    # Upload with overwrite semantics
    if [ -f "$SOURCE_DIR" ]; then
        parent="$(basename "$(dirname "$SOURCE_DIR")")"
        base="$(basename "$SOURCE_DIR")"
        sudo gsutil -o "GSUtil:parallel_thread_count=32" -o "GSUtil:parallel_process_count=16" \
               -o "GSUtil:parallel_composite_upload_threshold=10M" \
               -o "GSUtil:parallel_composite_upload_component_size=10M" \
               -m cp "$SOURCE_DIR" "gs://${BUCKET_NAME}/${VM_NAME}_downloads/${parent}/${base}"
    else
        if [ "$SOURCE_DIR" = "$DOWNLOADS_DIR" ]; then
            sudo gsutil -o "GSUtil:parallel_thread_count=32" -o "GSUtil:parallel_process_count=16" \
                   -o "GSUtil:parallel_composite_upload_threshold=10M" \
                   -o "GSUtil:parallel_composite_upload_component_size=10M" \
                   -m cp -r "$DOWNLOADS_DIR"/* "gs://${BUCKET_NAME}/${VM_NAME}_downloads/"
        else
            sudo gsutil -o "GSUtil:parallel_thread_count=32" -o "GSUtil:parallel_process_count=16" \
                   -o "GSUtil:parallel_composite_upload_threshold=10M" \
                   -o "GSUtil:parallel_composite_upload_component_size=10M" \
                   -m rsync -r -d "$SOURCE_DIR" "gs://${BUCKET_NAME}/${VM_NAME}_downloads/$(basename "$SOURCE_DIR")/"
        fi
    fi

    # Create and upload manifest only for full-force uploads
    if [ -z "$SUBPATH" ]; then
        echo "📋 Creating and uploading file manifest..."
        sudo find "$DOWNLOADS_DIR" -type f -exec stat -c "%n|%s|%Y" {} \; > "/tmp/downloads_manifest_${TIMESTAMP}.txt"
        sudo gsutil cp "/tmp/downloads_manifest_${TIMESTAMP}.txt" "gs://${BUCKET_NAME}/${VM_NAME}_downloads_manifest_latest.txt"
        rm -f "/tmp/downloads_manifest_${TIMESTAMP}.txt"
    fi

    echo "✅ Force upload completed!"
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
    
    # Create Downloads directory if it doesn't exist (with sudo for permissions)
    sudo mkdir -p "$DOWNLOADS_DIR"
    
    # Download Downloads folder with optimized parallel settings
    echo "🔄 Syncing Downloads folder with high-performance settings..."
    sudo gsutil -o "GSUtil:parallel_thread_count=32" -o "GSUtil:parallel_process_count=16" \
           -o "GSUtil:sliced_object_download_threshold=10M" \
           -o "GSUtil:sliced_object_download_max_components=8" \
           -m rsync -r "gs://${BUCKET_NAME}/${VM_NAME}_downloads/" "$DOWNLOADS_DIR"
    
    # Fix permissions
    sudo chown -R $USER:$USER "$DOWNLOADS_DIR"
    sudo chmod -R 755 "$DOWNLOADS_DIR"
    
    echo "✅ Downloads download completed!"
}

smart_sync() {
    echo "🧠 Smart sync: Analyzing differences..."
    
    # Get remote manifest if it exists
    REMOTE_MANIFEST="/tmp/remote_manifest_${TIMESTAMP}.txt"
    LOCAL_MANIFEST="/tmp/local_manifest_${TIMESTAMP}.txt"
    
    if sudo gsutil cp "gs://${BUCKET_NAME}/${VM_NAME}_downloads_manifest_latest.txt" "$REMOTE_MANIFEST" 2>/dev/null; then
        echo "📋 Found remote manifest"
    else
        echo "📋 No remote manifest found, will upload everything"
        upload_downloads
        return
    fi
    
    # Create local manifest
    if [ -d "$DOWNLOADS_DIR" ]; then
        sudo find "$DOWNLOADS_DIR" -type f -exec stat -c "%n|%s|%Y" {} \; > "$LOCAL_MANIFEST"
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
    sudo gsutil ls -l "gs://${BUCKET_NAME}/${VM_NAME}_downloads*" 2>/dev/null || echo "No Downloads backups found"
}

list_files() {
    echo "📦 Bucket: gs://${BUCKET_NAME}"
    echo "🖥️  VM: ${VM_NAME}"
    echo ""
    
    if ! sudo gsutil ls "gs://${BUCKET_NAME}/${VM_NAME}_downloads/" &>/dev/null; then
        echo "❌ No Downloads backup found for VM: $VM_NAME"
        exit 1
    fi
    
    echo "📋 Available files for download:"
    sudo gsutil ls -l -r "gs://${BUCKET_NAME}/${VM_NAME}_downloads/" | grep -v "/$" | while read -r line; do
        # Extract file path and size
        size=$(echo "$line" | awk '{print $1}')
        path=$(echo "$line" | awk '{print $3}')
        filename=$(basename "$path")
        folder=$(dirname "$path" | sed "s|.*${VM_NAME}_downloads/||")
        
        if [ "$folder" != "." ]; then
            printf "  📁 %-15s 📄 %-30s (%s)\n" "$folder/" "$filename" "$size"
        fi
    done
}

download_select() {
    echo "🎯 Selective Downloads Download"
    echo "📦 Bucket: gs://${BUCKET_NAME}"
    echo "📁 Target: $DOWNLOADS_DIR"
    
    if ! gsutil ls "gs://${BUCKET_NAME}/${VM_NAME}_downloads/" &>/dev/null; then
        echo "❌ No Downloads backup found for VM: $VM_NAME"
        exit 1
    fi
    
    # Get list of available files (only actual files, not directories)
    echo "📋 Available files:"
    TEMP_LIST="/tmp/available_files_$(date +%Y%m%d_%H%M%S).txt"
    sudo gsutil ls -r "gs://${BUCKET_NAME}/${VM_NAME}_downloads/" | grep -v "/$" | grep -v "^$" > "$TEMP_LIST"
    
    # Filter out only files with actual content (not empty lines or directory markers)
    FILTERED_LIST="/tmp/filtered_files_$(date +%Y%m%d_%H%M%S).txt"
    while read -r path; do
        if [[ "$path" == */* ]] && [[ "$(basename "$path")" != "" ]] && [[ "$(basename "$path")" != ":" ]]; then
            echo "$path" >> "$FILTERED_LIST"
        fi
    done < "$TEMP_LIST"
    
    # Show files with numbers
    if [ -f "$FILTERED_LIST" ]; then
        cat -n "$FILTERED_LIST" | while read -r num path; do
            filename=$(basename "$path")
            folder=$(dirname "$path" | sed "s|.*${VM_NAME}_downloads/||" | sed 's|/$||')
            if [ "$folder" = "." ]; then folder="Root"; fi
            printf "%2d) 📁 %-15s 📄 %s\n" "$num" "$folder/" "$filename"
        done
        
        # Use filtered list for downloads
        mv "$FILTERED_LIST" "$TEMP_LIST"
    else
        echo "No files found to download"
        rm -f "$TEMP_LIST" "$FILTERED_LIST"
        return 1
    fi
    
    echo ""
    echo "Enter file numbers to download (e.g., 1,3,5 or 1-3 or 'all'):"
    read -r selection
    
    if [ "$selection" = "all" ]; then
        echo "📥 Downloading all files..."
        download_downloads
        rm -f "$TEMP_LIST"
        return
    fi
    
    # Create Downloads directory if it doesn't exist
    sudo mkdir -p "$DOWNLOADS_DIR"
    
    # Parse selection and download files
    echo "📥 Downloading selected files..."
    
    # Handle comma-separated numbers and ranges
    IFS=',' read -ra SELECTIONS <<< "$selection"
    for item in "${SELECTIONS[@]}"; do
        item=$(echo "$item" | xargs) # trim whitespace
        if [[ "$item" =~ ^[0-9]+$ ]]; then
            # Single number
            file_path=$(sed -n "${item}p" "$TEMP_LIST")
            if [ -n "$file_path" ]; then
                echo "  📥 $(basename "$file_path")"
                local_path=$(echo "$file_path" | sed "s|.*${VM_NAME}_downloads|$DOWNLOADS_DIR|")
                sudo mkdir -p "$(dirname "$local_path")"
                sudo gsutil -o "GSUtil:parallel_thread_count=32" -o "GSUtil:parallel_process_count=16" \
                       -o "GSUtil:sliced_object_download_threshold=10M" \
                       -o "GSUtil:sliced_object_download_max_components=8" \
                       cp "$file_path" "$local_path"
            fi
        elif [[ "$item" =~ ^[0-9]+-[0-9]+$ ]]; then
            # Range (e.g., 1-3)
            start=$(echo "$item" | cut -d'-' -f1)
            end=$(echo "$item" | cut -d'-' -f2)
            for ((i=start; i<=end; i++)); do
                file_path=$(sed -n "${i}p" "$TEMP_LIST")
                if [ -n "$file_path" ]; then
                    echo "  📥 $(basename "$file_path")"
                    local_path=$(echo "$file_path" | sed "s|.*${VM_NAME}_downloads|$DOWNLOADS_DIR|")
                    sudo mkdir -p "$(dirname "$local_path")"
                    sudo gsutil -o "GSUtil:parallel_thread_count=32" -o "GSUtil:parallel_process_count=16" \
                           -o "GSUtil:sliced_object_download_threshold=10M" \
                           -o "GSUtil:sliced_object_download_max_components=8" \
                           cp "$file_path" "$local_path"
                fi
            done
        fi
    done
    
    # Fix permissions
    sudo chown -R $USER:$USER "$DOWNLOADS_DIR"
    sudo chmod -R 755 "$DOWNLOADS_DIR"
    
    rm -f "$TEMP_LIST"
    echo "✅ Selected files downloaded successfully!"
}

list_folders() {
    echo "📦 Bucket: gs://${BUCKET_NAME}"
    echo "🖥️  VM: ${VM_NAME}"
    echo ""
    
    if ! sudo gsutil ls "gs://${BUCKET_NAME}/${VM_NAME}_downloads/" &>/dev/null; then
        echo "❌ No Downloads backup found for VM: $VM_NAME"
        exit 1
    fi
    
    echo "📁 Available folders for download:"
    
    # Get unique folders
    sudo gsutil ls "gs://${BUCKET_NAME}/${VM_NAME}_downloads/" | while read -r folder_path; do
        if [[ "$folder_path" == */ ]]; then
            folder_name=$(basename "$folder_path" | sed 's|/$||')
            if [ -n "$folder_name" ]; then
                # Count files in folder
                file_count=$(sudo gsutil ls -r "$folder_path" | grep -v "/$" | wc -l)
                printf "  📁 %-20s (%d files)\n" "$folder_name/" "$file_count"
            fi
        fi
    done
}

download_folders() {
    echo "📁 Selective Folder Download"
    echo "📦 Bucket: gs://${BUCKET_NAME}"
    echo "📁 Target: $DOWNLOADS_DIR"
    
    if ! gsutil ls "gs://${BUCKET_NAME}/${VM_NAME}_downloads/" &>/dev/null; then
        echo "❌ No Downloads backup found for VM: $VM_NAME"
        exit 1
    fi
    
    # Get list of available folders
    echo "📋 Available folders:"
    TEMP_FOLDERS="/tmp/available_folders_$(date +%Y%m%d_%H%M%S).txt"
    sudo gsutil ls "gs://${BUCKET_NAME}/${VM_NAME}_downloads/" | grep "/$" > "$TEMP_FOLDERS"
    
    # Show folders with numbers and file counts
    cat -n "$TEMP_FOLDERS" | while read -r num folder_path; do
        folder_name=$(basename "$folder_path" | sed 's|/$||')
        if [ -n "$folder_name" ]; then
            # Count files in folder
            file_count=$(gsutil ls -r "$folder_path" | grep -v "/$" | wc -l)
            printf "%2d) 📁 %-20s (%d files)\n" "$num" "$folder_name/" "$file_count"
        fi
    done
    
    echo ""
    echo "Enter folder numbers to download (e.g., 1,3 or 1-2 or 'all'):"
    read -r selection
    
    if [ "$selection" = "all" ]; then
        echo "📥 Downloading all folders..."
        download_downloads
        rm -f "$TEMP_FOLDERS"
        return
    fi
    
    # Create Downloads directory if it doesn't exist
    sudo mkdir -p "$DOWNLOADS_DIR"
    
    # Parse selection and download folders
    echo "📥 Downloading selected folders..."
    
    # Handle comma-separated numbers and ranges
    IFS=',' read -ra SELECTIONS <<< "$selection"
    for item in "${SELECTIONS[@]}"; do
        item=$(echo "$item" | xargs) # trim whitespace
        if [[ "$item" =~ ^[0-9]+$ ]]; then
            # Single number
            folder_path=$(sed -n "${item}p" "$TEMP_FOLDERS")
            if [ -n "$folder_path" ]; then
                folder_name=$(basename "$folder_path" | sed 's|/$||')
                echo "  📁 Downloading folder: $folder_name/"
                
                # Download entire folder with high performance settings
                sudo mkdir -p "$DOWNLOADS_DIR/$folder_name"
                sudo gsutil -o "GSUtil:parallel_thread_count=32" -o "GSUtil:parallel_process_count=16" \
                       -o "GSUtil:sliced_object_download_threshold=10M" \
                       -o "GSUtil:sliced_object_download_max_components=8" \
                       -m rsync -r "$folder_path" "$DOWNLOADS_DIR/$folder_name/"
            fi
        elif [[ "$item" =~ ^[0-9]+-[0-9]+$ ]]; then
            # Range (e.g., 1-2)
            start=$(echo "$item" | cut -d'-' -f1)
            end=$(echo "$item" | cut -d'-' -f2)
            for ((i=start; i<=end; i++)); do
                folder_path=$(sed -n "${i}p" "$TEMP_FOLDERS")
                if [ -n "$folder_path" ]; then
                    folder_name=$(basename "$folder_path" | sed 's|/$||')
                    echo "  📁 Downloading folder: $folder_name/"
                    
                    # Download entire folder with high performance settings
                    sudo mkdir -p "$DOWNLOADS_DIR/$folder_name"
                    sudo gsutil -o "GSUtil:parallel_thread_count=32" -o "GSUtil:parallel_process_count=16" \
                           -o "GSUtil:sliced_object_download_threshold=10M" \
                           -o "GSUtil:sliced_object_download_max_components=8" \
                           -m rsync -r "$folder_path" "$DOWNLOADS_DIR/$folder_name/"
                fi
            done
        fi
    done
    
    # Fix permissions
    sudo chown -R $USER:$USER "$DOWNLOADS_DIR"
    sudo chmod -R 755 "$DOWNLOADS_DIR"
    
    rm -f "$TEMP_FOLDERS"
    echo "✅ Selected folders downloaded successfully with preserved structure!"
}

case "${1:-help}" in
    upload)
        upload_downloads "$@"
        ;;
    force-upload)
        force_upload_downloads "$@"
        ;;
    download)
        download_downloads
        ;;
    download-select)
        download_select
        ;;
    download-folders)
        download_folders
        ;;
    upload-folder)
        select d in "$DOWNLOADS_DIR"/*/; do
            [ -n "$d" ] && upload_downloads upload "$d" && break
        done
        ;;
    sync)
        smart_sync
        ;;
    list)
        list_downloads
        ;;
    list-files)
        list_files
        ;;
    list-folders)
        list_folders
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
