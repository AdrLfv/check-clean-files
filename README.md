# Check Clean Files

Shell utilities for scanning storage on the Vita cluster and logging directories that exceed a size or age threshold. The primary entry point is `check_files.sh`, which walks the configured base directories, computes directory sizes, and writes the results to CSV for later review.

## Requirements

- Bash (tested on GNU bash)
- Standard GNU userland tools (`find`, `du`, `timeout`, `awk`, `numfmt`)
- Access to the Vita filesystem paths you plan to scan

## Usage

```bash
bash check_files.sh [OPTIONS]
```

### Common options

| Option | Description |
| --- | --- |
| `-e` | Only consider directories that have not been modified for more than 365 days. |
| `-m <min_size_gb>` | Minimum directory size (in gigabytes) required to record an entry. Default is `0`. |
| `-t <timeout_seconds>` | Timeout (seconds) for each `du` size computation. Default is `1200`. |
| `-b <dir[,dir,...]>` | Comma-separated list of base directories to scan. Overrides the defaults in the script. |
| `-o <output_csv_basename>` | Basename for the CSV outputs written under `./output`. |
| `--resume` | Resume from the last directory previously recorded in the output CSV(s). The script skips all directories up to that marker and reports how many were skipped/remaining. |

### Output

- Results are written to `./output/<basename>.csv`. When multiple base directories are specified, numbered suffixes are appended.
- CSV columns: `Directory`, `Size` (human-readable IEC units).
- Progress information, matches, and resume statistics are printed to `stderr` so you can monitor the run without polluting the CSV.

### Example

```bash
bash check_files.sh -m 100 -t 1200 -b /work/vita/ -o scitas_storage.csv --resume
```

This scans `/work/vita/` for directories larger than 100 GB, resumes from the last recorded directory in `./output/scitas_storage.csv`, and times out individual `du` commands after 1200 seconds.

## Notes

- The script currently ignores top-level directories listed in `EXCLUDED_DIRS`, but still processes their subdirectories.
- When `--resume` is used, the script appends to existing CSV files. Delete the old output files if you want to start over.
- Some directories can take a while to scan; consider reducing `MAX_DEPTH` or the base directory list if you only need summaries of specific paths.
