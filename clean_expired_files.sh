#!/bin/bash
#SBATCH --time=48:00:00
#SBATCH --job-name=check_files
#SBATCH --nodes=1
#SBATCH --cpus-per-task=8
#SBATCH --partition=standard
#SBATCH --output=/work/vita/alefevre/programs/check-clean-files/logs/cleaning/%j.out
#SBATCH --error=/work/vita/alefevre/programs/check-clean-files/logs/cleaning/%j.err

FILES_LIST="files_to_clean"

if [[ ! -f "$FILES_LIST" ]]; then
    echo "Error: File '$FILES_LIST' not found!"
    exit 1
fi

# Ensure SLURM_CPUS_PER_TASK is set, default to 1 if not running via sbatch
CPUS=${SLURM_CPUS_PER_TASK:-1}

echo "Starting cleanup with $CPUS CPUs..."

# Extract paths, check existence, and delete in parallel using xargs
awk '{print $1}' "$FILES_LIST" | while read -r FILE_PATH; do
    if [[ -e "$FILE_PATH" ]]; then
        echo "$FILE_PATH"
    fi
done | xargs -I {} -P "$CPUS" bash -c 'rm -rf "$1" && echo "Deleted: $1"' _ {}

echo "Cleanup completed."