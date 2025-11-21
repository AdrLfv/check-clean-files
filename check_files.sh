#!/bin/bash

# Default values
expired_only=false
min_size_gb=0
timeout_seconds=1200
resume=false
BASE_DIRS=(
    "/work/vita/"
)
OUTPUT_DIR="./output"
LOG_BASENAME="expired_files_scitas.csv"

# Parse command-line options
declare -a user_base_dirs=()

while [ $# -gt 0 ]; do
    case $1 in
        -e) expired_only=true ;;
        -m)
            if [ -z "$2" ]; then
                echo "Missing value for -m" >&2
                exit 1
            fi
            min_size_gb="$2"
            shift
            ;;
        -t)
            if [ -z "$2" ]; then
                echo "Missing value for -t" >&2
                exit 1
            fi
            timeout_seconds="$2"
            shift
            ;;
        -b)
            if [ -z "$2" ]; then
                echo "Missing value for -b" >&2
                exit 1
            fi
            IFS=',' read -ra new_dirs <<< "$2"
            user_base_dirs+=("${new_dirs[@]}")
            shift
            ;;
        -o)
            if [ -z "$2" ]; then
                echo "Missing value for -o" >&2
                exit 1
            fi
            LOG_BASENAME="$2"
            shift
            ;;
        --resume)
            resume=true
            ;;
        *) echo "Usage: $0 [--resume] [-e] [-m min_size_gb] [-t timeout_seconds] [-b base_dir[,base_dir...]] [-o output_csv_basename]" >&2; exit 1 ;;
    esac
    shift
done

if [ ${#user_base_dirs[@]} -gt 0 ]; then
    BASE_DIRS=("${user_base_dirs[@]}")
fi

mkdir -p "$OUTPUT_DIR"

log_stem="$LOG_BASENAME"
log_ext=""
if [[ "$LOG_BASENAME" == *.* ]]; then
    log_stem="${LOG_BASENAME%.*}"
    log_ext=".${LOG_BASENAME##*.}"
fi

LOG_FILES=()
if [ ${#BASE_DIRS[@]} -gt 1 ]; then
    for i in "${!BASE_DIRS[@]}"; do
        LOG_FILES+=("$OUTPUT_DIR/${log_stem}_$((i+1))${log_ext}")
    done
else
    LOG_FILES+=("$OUTPUT_DIR/${log_stem}${log_ext}")
fi

RESUME_DIRS=()
if [ "$resume" = true ]; then
    for log_file in "${LOG_FILES[@]}"; do
        if [ -f "$log_file" ]; then
            last_dir=$(awk -F',' 'NR>1 && NF {last=$1} END {gsub(/^"|"$/, "", last); print last}' "$log_file")
            RESUME_DIRS+=("$last_dir")
        else
            RESUME_DIRS+=("")
        fi
    done
fi

echo "Options parsed: expired_only=$expired_only, min_size_gb=$min_size_gb, timeout_seconds=$timeout_seconds, base_dirs=${BASE_DIRS[*]}, output_dir=$OUTPUT_DIR, log_basename=$LOG_BASENAME"
EXPIRATION_DAYS=365
MAX_DEPTH=2
# Directories to skip measuring (their subfolders will still be measured)
EXCLUDED_DIRS=(
    "/work/vita/datasets"
    "/work/vita/rjiang"
)

is_excluded_dir() {
    local dir="$1"
    for excluded in "${EXCLUDED_DIRS[@]}"; do
        if [[ "$dir" == "$excluded" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to log expired directories with size
log_expired_dirs_with_size() {
    local base_dir="$1"
    local log_file="$2"
    local resume_after="${3:-}"
    local min_size_bytes=$((min_size_gb * 1024 * 1024 * 1024))

    echo "Entering function: base_dir=$base_dir, log_file=$log_file"
    if [ "$resume" = true ] && [ -s "$log_file" ]; then
        echo "Resume mode: appending to existing log $log_file" >&2
    else
        echo '"Directory","Size"' > "$log_file"
    fi
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
    
    local total_dirs=${#dirs_to_check[@]}
    echo "Found ${total_dirs} directories to check"

    local resume_enabled=false
    local resume_index=-1
    local skipped_due_resume=0
    if [ -n "$resume_after" ]; then
        for idx in "${!dirs_to_check[@]}"; do
            candidate="${dirs_to_check[$idx]}"
            if [[ "$candidate" == "$resume_after" ]]; then
                resume_enabled=true
                resume_index=$idx
                break
            fi
        done

        if [ "$resume_enabled" = true ]; then
            skipped_due_resume=$((resume_index + 1))
            local remaining_after_resume=$((total_dirs - skipped_due_resume))
            echo "Resume enabled for $log_file: skipping up to '$resume_after' (skipping $skipped_due_resume dirs, $remaining_after_resume remaining)" >&2
        else
            echo "Resume requested but '$resume_after' not found under $base_dir; processing from start" >&2
        fi
    fi

    local skip_until_resume=false
    if [ "$resume_enabled" = true ]; then
        skip_until_resume=true
    fi

    local count=0
    for dir in "${dirs_to_check[@]}"; do
        if [ "$skip_until_resume" = true ]; then
            if [[ "$dir" == "$resume_after" ]]; then
                skip_until_resume=false
                echo "Resume marker reached for $log_file: $dir" >&2
            fi
            continue
        fi
        count=$((count+1))
        
        # Log every directory being checked
        echo "[$count/${#dirs_to_check[@]}] Checking: $dir" >&2
        
        if is_excluded_dir "$dir"; then
            echo "  -> Skipped (excluded directory; its subfolders are still processed)" >&2
            continue
        fi
        
        # Quick size check with du -s (timeout after $timeout_seconds seconds)
        local size_bytes=$(timeout "$timeout_seconds" du -s -B1 "$dir" 2>/dev/null | awk '{print $1}')
        
        if [ -n "$size_bytes" ]; then
            local size_gb=$((size_bytes / 1024 / 1024 / 1024))
            echo "  -> Size: ${size_gb}GB" >&2
            
            if [ "$size_bytes" -ge "$min_size_bytes" ]; then
                local size_human=$(numfmt --to=iec --suffix=B "$size_bytes" 2>/dev/null || echo "${size_bytes}B")
                printf '"%s","%s"\n' "$dir" "$size_human" >> "$log_file"
                echo "  MATCH! Added to CSV" >&2
            fi
        else
            echo "  -> Skipped (timeout or error)" >&2
        fi
    done
    
    local processed_dirs=$count
    local remaining_after_resume=$((total_dirs - skipped_due_resume))
    if [ "$resume_enabled" = true ]; then
        echo "Resume summary: skipped $skipped_due_resume, processed $processed_dirs of $remaining_after_resume remaining directories" >&2
    fi

    echo "Scan finished (checked $processed_dirs directories; total candidates $total_dirs)"
    echo "Results logged to: $log_file"
}

# Iterate over each base directory and log file pair
echo "Before for loop"
echo "BASE_DIRS count=${#BASE_DIRS[@]} values=${BASE_DIRS[*]}"
echo "LOG_FILES count=${#LOG_FILES[@]} values=${LOG_FILES[*]}"
for i in "${!BASE_DIRS[@]}"; do
    resume_arg=""
    if [ "$resume" = true ]; then
        resume_arg="${RESUME_DIRS[$i]}"
    fi
    log_expired_dirs_with_size "${BASE_DIRS[$i]}" "${LOG_FILES[$i]}" "$resume_arg"
done