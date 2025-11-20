#!/bin/bash

FILES_LIST="files_to_clean"

if [[ ! -f "$FILES_LIST" ]]; then
    echo "Error: File '$FILES_LIST' not found!"
    exit 1
fi

TOTAL_SPACE_CLEANED=0

echo "Starting cleanup..."

while IFS= read -r line; do
    FILE_PATH=$(echo "$line" | awk '{print $1}')
    FILE_SIZE=$(echo "$line" | grep -oP '(?<=\(Size: ).*(?=\))')
    
    if [[ "$FILE_SIZE" =~ G ]]; then
        SIZE_BYTES=$(echo "$FILE_SIZE" | grep -oP '\d+' | awk '{print $1 * 1024 * 1024 * 1024}')
    elif [[ "$FILE_SIZE" =~ M ]]; then
        SIZE_BYTES=$(echo "$FILE_SIZE" | grep -oP '\d+' | awk '{print $1 * 1024 * 1024}')
    elif [[ "$FILE_SIZE" =~ K ]]; then
        SIZE_BYTES=$(echo "$FILE_SIZE" | grep -oP '\d+' | awk '{print $1 * 1024}')
    else
        SIZE_BYTES=0
    fi
    
    if [[ -e "$FILE_PATH" ]]; then
        rm -rf "$FILE_PATH"
        echo "Deleted: $FILE_PATH (Freed $FILE_SIZE)"
        TOTAL_SPACE_CLEANED=$(echo "$TOTAL_SPACE_CLEANED + $SIZE_BYTES" | bc)
    else
        echo "Warning: $FILE_PATH not found, skipping..."
    fi

done < "$FILES_LIST"

TOTAL_CLEANED_HUMAN=$(numfmt --to=iec --suffix=B $TOTAL_SPACE_CLEANED)

echo "Total space cleaned: $TOTAL_CLEANED_HUMAN"