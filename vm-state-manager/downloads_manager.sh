#!/bin/bash

# Downloads External Drive Manager
# Manages Downloads folder like external drive with GSuite tags and ignore support

set -e

# Configuration
BUCKET_NAME="${GCP_DOWNLOADS_BUCKET:-vm-downloads-india}"
VM_NAME="${VM_NAME:-$(hostname)}"

# Get the real user who invoked the script (not the sudo user)
REAL_USER="${SUDO_USER:-$USER}"
DOWNLOADS_DIR="${DOWNLOADS_DIR:-/home/$REAL_USER/Downloads}"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
IGNORE_FILE=".ignore_uploads"

show_help() {
    cat << EOF
Downloads External Drive Manager

USAGE:
    $0 <command> [options]

COMMANDS:
    lazy-upload         Upload non-ignored files (overwrite existing)
    selective-upload    Choose specific files/folders to upload
    selective-download  Choose specific files/folders to download
    upload-all          Upload everything (ignore tags respected)
    download-all        Download everything from bucket
    list-remote         List files available in bucket
    list-local          List local files with status
    add-ignore          Add file/folder to ignore list
    remove-ignore       Remove file/folder from ignore list
    show-ignore         Show current ignore list
    show-dir            Show current working directory
    set-dir             Set working directory for operations
    help                Show this help message

EXAMPLES:
    $0 lazy-upload                    # Upload non-ignored files (overwrite existing)
    $0 selective-upload               # Choose what to upload
    $0 selective-download             # Choose what to download
    $0 upload-all                     # Upload everything (respects ignore)
    $0 download-all                   # Download everything from bucket
    $0 add-ignore "*.tmp"            # Ignore all .tmp files
    $0 add-ignore "temp_folder"      # Ignore temp_folder

FOLDER EXAMPLES:
    DOWNLOADS_DIR=/home/$REAL_USER/Documents $0 lazy-upload    # Use Documents folder
    DOWNLOADS_DIR=/home/$REAL_USER/Pictures $0 selective-upload # Use Pictures folder
    DOWNLOADS_DIR=/home/$REAL_USER/Videos $0 download-all      # Use Videos folder

ENVIRONMENT VARIABLES:
    GCP_DOWNLOADS_BUCKET    Bucket for Downloads (default: vm-downloads-india)
    VM_NAME                 VM identifier (default: hostname)
    DOWNLOADS_DIR           Source directory (default: /home/$REAL_USER/Downloads)

NOTE: This works like an external drive, not a backup system
EOF
}

# Check if file/folder should be ignored
is_ignored() {
    local path="$1"
    local relative_path="${path#$DOWNLOADS_DIR/}"
    
    if [ ! -f "$DOWNLOADS_DIR/$IGNORE_FILE" ]; then
        return 1
    fi
    
    while IFS= read -r pattern; do
        # Skip empty lines and comments
        [[ -z "$pattern" || "$pattern" =~ ^[[:space:]]*# ]] && continue
        
        # Remove leading/trailing whitespace
        pattern=$(echo "$pattern" | xargs)
        
        # Check if pattern matches
        if [[ "$relative_path" == $pattern ]] || [[ "$(basename "$path")" == $pattern ]]; then
            return 0
        fi
    done < "$DOWNLOADS_DIR/$IGNORE_FILE"
    
    return 1
}

# Create ignore file if it doesn't exist
ensure_ignore_file() {
    if [ ! -f "$DOWNLOADS_DIR/$IGNORE_FILE" ]; then
        cat > "$DOWNLOADS_DIR/$IGNORE_FILE" << EOF
# Files and folders to ignore during upload
# Use patterns like: *.tmp, temp_folder, etc.
# Lines starting with # are comments

*.tmp
*.log
.temp
temp
cache
EOF
        echo "📝 Created ignore file: $DOWNLOADS_DIR/$IGNORE_FILE"
    fi
}

# Lazy upload - upload non-ignored files (overwrite existing)
lazy_upload() {
    echo "🦥 Lazy upload: Upload non-ignored files (overwrite existing)"
    echo "📦 Bucket: gs://${BUCKET_NAME}"
    
    ensure_ignore_file
    
    # Create bucket if it doesn't exist
    sudo gsutil mb -p "$(gcloud config get-value project)" -l asia-south1 "gs://${BUCKET_NAME}" 2>/dev/null || true
    
    local upload_count=0
    local ignore_count=0
    local overwrite_count=0
    local subfolder_count=0
    
    echo "🔍 Scanning base directory for files..."
    
    # Count subfolders first
    subfolder_count=$(find "$DOWNLOADS_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)
    echo "📁 Found $subfolder_count subfolders (will be processed as whole)"
    
    # Collect files to upload (only base directory, not subfolders)
    local files_to_upload=()
    local bucket_paths=()
    
    while IFS= read -r -d '' file; do
        local relative_path="${file#$DOWNLOADS_DIR/}"
        
        # Check if file should be ignored
        if is_ignored "$file"; then
            echo "🚫 Ignored: $relative_path"
            ((ignore_count++))
            continue
        fi
        
        # Check if file exists in bucket
        local bucket_path="gs://${BUCKET_NAME}/downloads/${relative_path}"
        if sudo gsutil ls "$bucket_path" &>/dev/null; then
            echo "🔄 Will overwrite: $relative_path"
            ((overwrite_count++))
        else
            echo "📤 Will upload new: $relative_path"
        fi
        
        # Add to upload lists
        files_to_upload+=("$file")
        bucket_paths+=("$bucket_path")
        
    done < <(find "$DOWNLOADS_DIR" -maxdepth 1 -type f -print0)
    
    # Upload all files at once using parallel processing
    if [ ${#files_to_upload[@]} -gt 0 ]; then
        echo ""
        echo "📤 Uploading ${#files_to_upload[@]} files in parallel..."
        
        
        # Upload files individually but with parallel processing
        # Upload files individually but with parallel processing
        for i in "${!files_to_upload[@]}"; do
            local file="${files_to_upload[$i]}"
            local bucket_path="${bucket_paths[$i]}"
            echo "📤 Uploading: $(basename "$file")"
            sudo gsutil -o "GSUtil:parallel_thread_count=32" -o "GSUtil:parallel_process_count=16" \
                   -o "GSUtil:parallel_composite_upload_threshold=10M" \
                   -o "GSUtil:parallel_composite_upload_component_size=10M" \
                   cp "$file" "$bucket_path"
        done
        # Upload files individually but with parallel processing
        # Upload files individually but with parallel processing
        # Upload files individually but with parallel processing
        # Upload files individually but with parallel processing
    fi
    
    echo ""
    echo "✅ Lazy upload completed!"
    echo "📤 Total uploaded: $upload_count files"
    echo "🔄 Overwritten: $overwrite_count files"
    echo "🚫 Ignored: $ignore_count files"
}

# Selective upload - choose what to upload
selective_upload() {
    echo "🎯 Selective Upload"
    echo "📦 Bucket: gs://${BUCKET_NAME}"
    
    ensure_ignore_file
    
    # Create bucket if it doesn't exist
    sudo gsutil mb -p "$(gcloud config get-value project)" -l asia-south1 "gs://${BUCKET_NAME}" 2>/dev/null || true
    
    # Count subfolders first
    local subfolder_count=$(find "$DOWNLOADS_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)
    echo "📁 Found $subfolder_count subfolders (will be processed as whole)"
    
    # Get list of local files (only base directory)
    echo "📋 Available files for upload (base directory only):"
    local files=()
    local index=1
    
    while IFS= read -r -d '' file; do
        local relative_path="${file#$DOWNLOADS_DIR/}"
        
        # Check if file should be ignored
        if is_ignored "$file"; then
            printf "%2d) 🚫 %s (IGNORED)\n" "$index" "$relative_path"
        else
            # Check if file exists in bucket
            local bucket_path="gs://${BUCKET_NAME}/downloads/${relative_path}"
            if sudo gsutil ls "$bucket_path" &>/dev/null; then
                printf "%2d) ⏭️  %s (EXISTS)\n" "$index" "$relative_path"
            else
                printf "%2d) 📤 %s (NEW)\n" "$index" "$relative_path"
            fi
        fi
        
        files+=("$file")
        ((index++))
    done < <(find "$DOWNLOADS_DIR" -maxdepth 1 -type f -print0)
    
    echo ""
    echo "Enter file numbers to upload (e.g., 1,3,5 or 1-3 or 'all' or 'new'):"
    read -r selection
    
    if [ "$selection" = "all" ]; then
        echo "📤 Uploading all files (respecting ignore list)..."
        upload_all
        return
    elif [ "$selection" = "new" ]; then
        echo "📤 Uploading only new files..."
        local upload_count=0
        
        # Collect new files to upload
        local files_to_upload=()
        local bucket_paths=()
        
        for file in "${files[@]}"; do
            local relative_path="${file#$DOWNLOADS_DIR/}"
            local bucket_path="gs://${BUCKET_NAME}/downloads/${relative_path}"
            if ! sudo gsutil ls "$bucket_path" &>/dev/null; then
                files_to_upload+=("$file")
                bucket_paths+=("$bucket_path")
            fi
        done
        
        # Upload all new files at once using parallel processing
        if [ ${#files_to_upload[@]} -gt 0 ]; then
            echo "📤 Uploading ${#files_to_upload[@]} new files in parallel..."
            
            
            # Upload all files at once with parallel processing
            sudo gsutil -o "GSUtil:parallel_thread_count=32" -o "GSUtil:parallel_process_count=16" \
                   -o "GSUtil:parallel_composite_upload_threshold=10M" \
                   -o "GSUtil:parallel_composite_upload_component_size=10M" \
                   -m cp "${files_to_upload[@]}" "${bucket_paths[@]}"
            upload_count=${#files_to_upload[@]}
        fi
        
        echo "✅ Uploaded $upload_count new files!"
        return
    fi
    
    # Parse selection and upload files
    echo "📤 Uploading selected files..."
    local upload_count=0
    
    # Collect selected files to upload
    local files_to_upload=()
    local bucket_paths=()
    
    IFS=',' read -ra SELECTIONS <<< "$selection"
    for item in "${SELECTIONS[@]}"; do
        item=$(echo "$item" | xargs)
        if [[ "$item" =~ ^[0-9]+$ ]]; then
            # Single number
            if [ "$item" -ge 1 ] && [ "$item" -le "${#files[@]}" ]; then
                local file="${files[$((item-1))]}"
                local relative_path="${file#$DOWNLOADS_DIR/}"
                
                files_to_upload+=("$file")
                bucket_paths+=("gs://${BUCKET_NAME}/downloads/${relative_path}")
            fi
        elif [[ "$item" =~ ^[0-9]+-[0-9]+$ ]]; then
            # Range
            local start=$(echo "$item" | cut -d'-' -f1)
            local end=$(echo "$item" | cut -d'-' -f2)
            for ((i=start; i<=end; i++)); do
                if [ "$i" -ge 1 ] && [ "$i" -le "${#files[@]}" ]; then
                    local file="${files[$((i-1))]}"
                    local relative_path="${file#$DOWNLOADS_DIR/}"
                    
                    files_to_upload+=("$file")
                    bucket_paths+=("gs://${BUCKET_NAME}/downloads/${relative_path}")
                fi
            done
        fi
    done
    
    # Upload all selected files at once using parallel processing
    if [ ${#files_to_upload[@]} -gt 0 ]; then
        echo "📤 Uploading ${#files_to_upload[@]} selected files in parallel..."
        
        
        # Upload all files at once with parallel processing
        sudo gsutil -o "GSUtil:parallel_thread_count=32" -o "GSUtil:parallel_process_count=16" \
               -o "GSUtil:parallel_composite_upload_threshold=10M" \
               -o "GSUtil:parallel_composite_upload_component_size=10M" \
               -m cp "${files_to_upload[@]}" "${bucket_paths[@]}"
        upload_count=${#files_to_upload[@]}
    fi
    
    echo "✅ Uploaded $upload_count files!"
}

# Upload all files (respecting ignore list)
upload_all() {
    echo "📤 Uploading all files (respects ignore list)..."
    echo "📦 Bucket: gs://${BUCKET_NAME}"
    
    ensure_ignore_file
    
    # Create bucket if it doesn't exist
    sudo gsutil mb -p "$(gcloud config get-value project)" -l asia-south1 "gs://${BUCKET_NAME}" 2>/dev/null || true
    
    local upload_count=0
    local ignore_count=0
    local subfolder_count=0
    
    echo "🔍 Scanning base directory for files..."
    
    # Count subfolders first
    subfolder_count=$(find "$DOWNLOADS_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)
    echo "📁 Found $subfolder_count subfolders (will be processed as whole)"
    
    # Collect files to upload (only base directory, not subfolders)
    local files_to_upload=()
    local bucket_paths=()
    
    while IFS= read -r -d '' file; do
        local relative_path="${file#$DOWNLOADS_DIR/}"
        
        # Check if file should be ignored
        if is_ignored "$file"; then
            echo "🚫 Ignored: $relative_path"
            ((ignore_count++))
            continue
        fi
        
        # Add to upload lists
        files_to_upload+=("$file")
        bucket_paths+=("gs://${BUCKET_NAME}/downloads/${relative_path}")
        
    done < <(find "$DOWNLOADS_DIR" -maxdepth 1 -type f -print0)
    
    # Upload all files at once using parallel processing
    if [ ${#files_to_upload[@]} -gt 0 ]; then
        echo ""
        echo "📤 Uploading ${#files_to_upload[@]} files in parallel..."
        
        
        # Upload all files at once with parallel processing
        sudo gsutil -o "GSUtil:parallel_thread_count=32" -o "GSUtil:parallel_process_count=16" \
               -o "GSUtil:parallel_composite_upload_threshold=10M" \
               -o "GSUtil:parallel_composite_upload_component_size=10M" \
               -m cp "${files_to_upload[@]}" "${bucket_paths[@]}"
        upload_count=${#files_to_upload[@]}
    fi
    
    echo ""
    echo "✅ Upload completed!"
    echo "📤 Uploaded: $upload_count files"
    echo "🚫 Ignored: $ignore_count files"
}

# Selective download - choose what to download
selective_download() {
    echo "🎯 Selective Download"
    echo "📦 Bucket: gs://${BUCKET_NAME}"
    echo "📁 Target: $DOWNLOADS_DIR"
    
    # Check if bucket exists
    if ! sudo gsutil ls "gs://${BUCKET_NAME}/downloads/" &>/dev/null; then
        echo "❌ No files found in bucket downloads folder"
        exit 1
    fi
    
    # Get list of available files
    echo "📋 Available files for download:"
    local files=()
    local index=1
    
    sudo gsutil ls -r "gs://${BUCKET_NAME}/downloads/" | grep -v "/$" | while read -r bucket_path; do
        local relative_path="${bucket_path#gs://${BUCKET_NAME}/downloads/}"
        printf "%2d) 📄 %s\n" "$index" "$relative_path"
        files+=("$bucket_path")
        ((index++))
    done
    
    echo ""
    echo "Enter file numbers to download (e.g., 1,3,5 or 1-3 or 'all'):"
    read -r selection
    
    if [ "$selection" = "all" ]; then
        echo "📥 Downloading all files..."
        download_all
        return
    fi
    
    # Create Downloads directory if it doesn't exist
    sudo mkdir -p "$DOWNLOADS_DIR"
    
    # Parse selection and download files
    echo "📥 Downloading selected files..."
    local download_count=0
    
    IFS=',' read -ra SELECTIONS <<< "$selection"
    for item in "${SELECTIONS[@]}"; do
        item=$(echo "$item" | xargs)
        if [[ "$item" =~ ^[0-9]+$ ]]; then
            # Single number
            if [ "$item" -ge 1 ] && [ "$item" -le "${#files[@]}" ]; then
                local bucket_path="${files[$((item-1))]}"
                local relative_path="${bucket_path#gs://${BUCKET_NAME}/}"
                local local_path="$DOWNLOADS_DIR/$relative_path"
                
                echo "📥 Downloading: $relative_path"
                sudo mkdir -p "$(dirname "$local_path")"
                sudo gsutil -o "GSUtil:parallel_thread_count=32" -o "GSUtil:parallel_process_count=16" \
                       -o "GSUtil:sliced_object_download_threshold=10M" \
                       -o "GSUtil:sliced_object_download_max_components=8" \
                       cp "$bucket_path" "$local_path"
                ((download_count++))
            fi
        elif [[ "$item" =~ ^[0-9]+-[0-9]+$ ]]; then
            # Range
            local start=$(echo "$item" | cut -d'-' -f1)
            local end=$(echo "$item" | cut -d'-' -f2)
            for ((i=start; i<=end; i++)); do
                if [ "$i" -ge 1 ] && [ "$i" -le "${#files[@]}" ]; then
                    local bucket_path="${files[$((i-1))]}"
                    local relative_path="${bucket_path#gs://${BUCKET_NAME}/}"
                    local local_path="$DOWNLOADS_DIR/$relative_path"
                    
                    echo "📥 Downloading: $relative_path"
                    sudo mkdir -p "$(dirname "$local_path")"
                    sudo gsutil -o "GSUtil:parallel_thread_count=32" -o "GSUtil:parallel_process_count=16" \
                           -o "GSUtil:sliced_object_download_threshold=10M" \
                           -o "GSUtil:sliced_object_download_max_components=8" \
                           cp "$bucket_path" "$local_path"
                    ((download_count++))
                fi
            done
        fi
    done
    
    # Fix permissions
    sudo chown -R $USER:$USER "$DOWNLOADS_DIR"
    sudo chmod -R 755 "$DOWNLOADS_DIR"
    
    echo "✅ Downloaded $download_count files!"
}

# Download all files
download_all() {
    echo "📥 Downloading all files..."
    echo "📦 Bucket: gs://${BUCKET_NAME}"
    echo "📁 Target: $DOWNLOADS_DIR"
    
    # Check if bucket exists
    if ! sudo gsutil ls "gs://${BUCKET_NAME}/downloads/" &>/dev/null; then
        echo "❌ No files found in bucket downloads folder"
        exit 1
    fi
    
    # Create Downloads directory if it doesn't exist
    sudo mkdir -p "$DOWNLOADS_DIR"
    
    # Download all files
    echo "🔄 Downloading files..."
    sudo gsutil -o "GSUtil:parallel_thread_count=32" -o "GSUtil:parallel_process_count=16" \
           -o "GSUtil:sliced_object_download_threshold=10M" \
           -o "GSUtil:sliced_object_download_max_components=8" \
           -m rsync -r "gs://${BUCKET_NAME}/downloads/" "$DOWNLOADS_DIR"
    
    # Fix permissions
    sudo chown -R $USER:$USER "$DOWNLOADS_DIR"
    sudo chmod -R 755 "$DOWNLOADS_DIR"
    
    echo "✅ Download completed!"
}

# List remote files
list_remote() {
    echo "📦 Bucket: gs://${BUCKET_NAME}"
    echo "🖥️  VM: ${VM_NAME}"
    echo ""
    
    if ! sudo gsutil ls "gs://${BUCKET_NAME}/downloads/" &>/dev/null; then
        echo "❌ No files found in bucket downloads folder"
        exit 1
    fi
    
    echo "📋 Files available in bucket downloads folder:"
    sudo gsutil ls -l -r "gs://${BUCKET_NAME}/downloads/" | grep -v "/$" | while read -r line; do
        local size=$(echo "$line" | awk '{print $1}')
        local path=$(echo "$line" | awk '{print $3}')
        local filename=$(basename "$path")
        local folder=$(dirname "$path" | sed "s|.*${BUCKET_NAME}/downloads/||")
        
        if [ "$folder" != "." ]; then
            printf "  📁 %-15s 📄 %-30s (%s)\n" "$folder/" "$filename" "$size"
        else
            printf "  📄 %-30s (%s)\n" "$filename" "$size"
        fi
    done
}

# List local files with status
list_local() {
    echo "📁 Local Downloads directory: $DOWNLOADS_DIR"
    echo ""
    
    if [ ! -d "$DOWNLOADS_DIR" ]; then
        echo "❌ Downloads directory not found"
        exit 1
    fi
    
    # Count subfolders first
    local subfolder_count=$(find "$DOWNLOADS_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)
    echo "📁 Found $subfolder_count subfolders (will be processed as whole)"
    
    echo "📋 Local files with status (base directory only):"
    local index=1
    
    while IFS= read -r -d '' file; do
        local relative_path="${file#$DOWNLOADS_DIR/}"
        
        # Check if file should be ignored
        if is_ignored "$file"; then
            printf "%2d) 🚫 %s (IGNORED)\n" "$index" "$relative_path"
        else
            # Check if file exists in bucket
            local bucket_path="gs://${BUCKET_NAME}/downloads/${relative_path}"
            if sudo gsutil ls "$bucket_path" &>/dev/null; then
                printf "%2d) ✅ %s (SYNCED)\n" "$index" "$relative_path"
            else
                printf "%2d) 📤 %s (NEW)\n" "$index" "$relative_path"
            fi
        fi
        
        ((index++))
    done < <(find "$DOWNLOADS_DIR" -maxdepth 1 -type f -print0)
}

# Add to ignore list
add_ignore() {
    local pattern="$1"
    
    if [ -z "$pattern" ]; then
        echo "❌ Please provide a pattern to ignore"
        echo "Usage: $0 add-ignore <pattern>"
        exit 1
    fi
    
    ensure_ignore_file
    
    # Check if pattern already exists
    if grep -q "^[[:space:]]*$pattern[[:space:]]*$" "$DOWNLOADS_DIR/$IGNORE_FILE"; then
        echo "⚠️  Pattern '$pattern' already in ignore list"
        return
    fi
    
    # Add pattern to ignore file
    echo "$pattern" >> "$DOWNLOADS_DIR/$IGNORE_FILE"
    echo "✅ Added '$pattern' to ignore list"
}

# Remove from ignore list
remove_ignore() {
    local pattern="$1"
    
    if [ -z "$pattern" ]; then
        echo "❌ Please provide a pattern to remove"
        echo "Usage: $0 remove-ignore <pattern>"
        exit 1
    fi
    
    if [ ! -f "$DOWNLOADS_DIR/$IGNORE_FILE" ]; then
        echo "❌ No ignore file found"
        return
    fi
    
    # Remove pattern from ignore file
    if sed -i "/^[[:space:]]*$pattern[[:space:]]*$/d" "$DOWNLOADS_DIR/$IGNORE_FILE"; then
        echo "✅ Removed '$pattern' from ignore list"
    else
        echo "❌ Pattern '$pattern' not found in ignore list"
    fi
}

# Show ignore list
show_ignore() {
    if [ ! -f "$DOWNLOADS_DIR/$IGNORE_FILE" ]; then
        echo "📝 No ignore file found"
        return
    fi
    
    echo "📝 Current ignore list ($DOWNLOADS_DIR/$IGNORE_FILE):"
    echo ""
    cat "$DOWNLOADS_DIR/$IGNORE_FILE"
}

# Show current working directory
show_dir() {
    echo "📁 Current working directory: $DOWNLOADS_DIR"
    
    if [ ! -d "$DOWNLOADS_DIR" ]; then
        echo "❌ Directory does not exist!"
        return 1
    fi
    
    local file_count=$(find "$DOWNLOADS_DIR" -maxdepth 1 -type f | wc -l)
    local dir_count=$(find "$DOWNLOADS_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)
    echo "📊 Directory contains: $file_count files in base directory, $dir_count subfolders"
}

# Set working directory
set_dir() {
    local new_dir="$1"
    
    if [ -z "$new_dir" ]; then
        echo "❌ Please provide a directory path"
        echo "Usage: $0 set-dir <directory_path>"
        echo "Example: $0 set-dir /home/bhavya/Documents"
        exit 1
    fi
    
    # Expand user path if it starts with ~
    if [[ "$new_dir" == ~* ]]; then
        new_dir=$(eval echo "$new_dir")
    fi
    
    # Check if directory exists
    if [ ! -d "$new_dir" ]; then
        echo "❌ Directory does not exist: $new_dir"
        exit 1
    fi
    
    # Check if directory is readable
    if [ ! -r "$new_dir" ]; then
        echo "❌ Directory is not readable: $new_dir"
        exit 1
    fi
    
    echo "📁 Setting working directory to: $new_dir"
    echo "💡 To make this permanent, set: export DOWNLOADS_DIR='$new_dir'"
    echo ""
    echo "🔍 Testing operations with new directory..."
    
    # Test if we can access the directory
    local test_file_count=$(find "$new_dir" -type f | wc -l)
    echo "✅ Directory accessible: $test_file_count files found"
    
    # Show current directory info
    DOWNLOADS_DIR="$new_dir"
    show_dir
}

# Main command handler
case "${1:-help}" in
    lazy-upload)
        lazy_upload
        ;;
    selective-upload)
        selective_upload
        ;;
    selective-download)
        selective_download
        ;;
    upload-all)
        upload_all
        ;;
    download-all)
        download_all
        ;;
    list-remote)
        list_remote
        ;;
    list-local)
        list_local
        ;;
    add-ignore)
        add_ignore "$2"
        ;;
    remove-ignore)
        remove_ignore "$2"
        ;;
    show-ignore)
        show_ignore
        ;;
    show-dir)
        show_dir
        ;;
    set-dir)
        set_dir "$2"
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
