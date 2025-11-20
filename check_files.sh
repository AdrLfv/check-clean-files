#!/bin/bash

# Default values
expired_only=false
min_size_gb=0
timeout_seconds=1200

# Parse command-line options
while [ $# -gt 0 ]; do
    case $1 in
        -e) expired_only=true ;;
        -m) min_size_gb="$2" ; shift ;;
        -t) timeout_seconds="$2" ; shift ;;
        *) echo "Usage: $0 [-e] [-m min_size_gb] [-t timeout_seconds]" >&2; exit 1 ;;
    esac
    shift
done

echo "Options parsed: expired_only=$expired_only, min_size_gb=$min_size_gb, timeout_seconds=$timeout_seconds"
BASE_DIRS=(
    "/work/vita"
)
LOG_FILES=(
    "./expired_files.csv"
)
EXPIRATION_DAYS=365
MAX_DEPTH=2

# Function to log expired directories with size
log_expired_dirs_with_size() {
    local base_dir="$1"
    local log_file="$2"
    local min_size_bytes=$((min_size_gb * 1024 * 1024 * 1024))

    echo "Entering function: base_dir=$base_dir, log_file=$log_file"
    echo '"Directory","Size"' > "$log_file"
    echo "Scanning $base_dir (expired_only=$expired_only, min_size_gb=$min_size_gb) ..."
    
    # Get list of directories to check
    local dirs_to_check=()
    if [ "$expired_only" = true ]; then
        echo "Finding expired directories..."
        mapfile -t dirs_to_check < <(find "$base_dir" -mindepth 1 -maxdepth "$MAX_DEPTH" -type d -mtime +"$EXPIRATION_DAYS" 2>/dev/null)
    else
        echo "Finding all directories..."
        mapfile -t dirs_to_check < <(find "$base_dir" -mindepth 1 -maxdepth "$MAX_DEPTH" -type d 2>/dev/null)
    fi
    
    echo "Found ${#dirs_to_check[@]} directories to check"
    
    local count=0
    for dir in "${dirs_to_check[@]}"; do
        count=$((count+1))
        
        # Log every directory being checked
        echo "[$count/${#dirs_to_check[@]}] Checking: $dir" >&2
        
        # Quick size check with du -s (timeout after $timeout_seconds seconds)
        local size_bytes=$(timeout "$timeout_seconds" du -s -B1 "$dir" 2>/dev/null | awk '{print $1}')
        
        if [ -n "$size_bytes" ]; then
            local size_gb=$((size_bytes / 1024 / 1024 / 1024))
            echo "  -> Size: ${size_gb}GB" >&2
            
            if [ "$size_bytes" -ge "$min_size_bytes" ]; then
                local size_human=$(numfmt --to=iec --suffix=B "$size_bytes" 2>/dev/null || echo "${size_bytes}B")
                printf '"%s","%s"\n' "$dir" "$size_human" >> "$log_file"
                echo "  ✓ MATCH! Added to CSV" >&2
            fi
        else
            echo "  -> Skipped (timeout or error)" >&2
        fi
    done
    
    echo "Scan finished (checked $count directories)"
    echo "Results logged to: $log_file"
}

# Iterate over each base directory and log file pair
echo "Before for loop"
echo "BASE_DIRS count=${#BASE_DIRS[@]} values=${BASE_DIRS[*]}"
echo "LOG_FILES count=${#LOG_FILES[@]} values=${LOG_FILES[*]}"
for i in "${!BASE_DIRS[@]}"; do
    log_expired_dirs_with_size "${BASE_DIRS[$i]}" "${LOG_FILES[$i]}"
done