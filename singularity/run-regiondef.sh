#!/bin/bash

# Singularity run script for petfit region definition app
# Usage: ./run-regiondef.sh [options]

set -e

# Default values
CONTAINER="petfit_latest.sif"
PORT=3838
HOST_PORT=3838
BIDS_DIR=""
DERIVATIVES_DIR=""
PETFIT_FOLDER="petfit"

# Help function
show_help() {
    cat << EOF
Run petfit region definition app in Singularity container

Usage: $0 [options]

Options:
    -c, --container PATH    Path to Singularity container (default: $CONTAINER)
    -p, --port PORT         Internal port for Shiny app (default: $PORT)
    --host-port PORT        Host port to map to (default: $HOST_PORT)
    --bids-dir PATH         Path to BIDS directory to mount [required]
    --derivatives-dir PATH  Path to derivatives directory to mount (optional)
    --petfit-folder NAME   Name for petfit output folder (default: $PETFIT_FOLDER)
    -h, --help              Show this help message

Examples:
    # Basic usage with BIDS directory
    $0 --bids-dir /path/to/bids

    # With separate derivatives directory
    $0 --bids-dir /data/bids --derivatives-dir /data/derivatives

    # Custom port mapping for server usage
    $0 --host-port 8080 --bids-dir /path/to/bids

    # Custom container and output folder
    $0 --container ./petfit_dev.sif --bids-dir /path/to/bids --petfit-folder custom_petfit

Requirements:
    - BIDS directory is required for region definition
    - BIDS directory should contain:
      * Standard BIDS structure with subjects/sessions
      * PET data with associated JSON metadata files
      * Segmentation or atlas files for region definition

The region definition app creates:
    - petfit_regions.tsv file in code/petfit/ folder
    - Combined TACs files in derivatives/petfit/ folder
    - Region morphometry and volume calculations
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--container)
            CONTAINER="$2"
            shift 2
            ;;
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        --host-port)
            HOST_PORT="$2"
            shift 2
            ;;
        --bids-dir)
            BIDS_DIR="$2"
            shift 2
            ;;
        --derivatives-dir)
            DERIVATIVES_DIR="$2"
            shift 2
            ;;
        --petfit-folder)
            PETFIT_FOLDER="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$BIDS_DIR" ]; then
    echo "Error: --bids-dir is required for region definition"
    echo "Use --help for more information"
    exit 1
fi

# Check if container exists
if [ ! -f "$CONTAINER" ] && [ ! -d "$CONTAINER" ]; then
    echo "Error: Container not found: $CONTAINER"
    echo "Build the container first using: ./build.sh"
    exit 1
fi

# Validate directories exist
if [ ! -d "$BIDS_DIR" ]; then
    echo "Error: BIDS directory does not exist: $BIDS_DIR"
    exit 1
fi

if [ -n "$DERIVATIVES_DIR" ] && [ ! -d "$DERIVATIVES_DIR" ]; then
    echo "Error: Derivatives directory does not exist: $DERIVATIVES_DIR"
    exit 1
fi

# Build bind mounts
BIND_MOUNTS="--bind $BIDS_DIR:/data/bids_dir"

if [ -n "$DERIVATIVES_DIR" ]; then
    BIND_MOUNTS="$BIND_MOUNTS --bind $DERIVATIVES_DIR:/data/derivatives_dir"
fi

# Build command arguments
CMD_ARGS="--func regiondef --mode interactive"
if [ -n "$PETFIT_FOLDER" ]; then
    CMD_ARGS="$CMD_ARGS --petfit_output_foldername $PETFIT_FOLDER"
fi

echo "=== petfit Region Definition App ==="
echo "Container: $CONTAINER"
echo "Port mapping: $HOST_PORT -> $PORT"
echo "BIDS directory: $BIDS_DIR"
if [ -n "$DERIVATIVES_DIR" ]; then
    echo "Derivatives directory: $DERIVATIVES_DIR"
fi
echo "petfit folder: $PETFIT_FOLDER"
echo

echo "Starting region definition app..."
echo "App will be available at: http://localhost:$HOST_PORT"
echo "Press Ctrl+C to stop the container"
echo

# Check for expected BIDS structure
echo "Checking BIDS directory structure..."
if [ ! -d "$BIDS_DIR" ]; then
    echo "Warning: BIDS directory structure not found"
fi

# Check for subjects
SUBJECT_COUNT=$(find "$BIDS_DIR" -maxdepth 1 -name "sub-*" -type d | wc -l)
if [ $SUBJECT_COUNT -eq 0 ]; then
    echo "Warning: No subjects (sub-*) found in BIDS directory"
else
    echo "Found $SUBJECT_COUNT subject(s) in BIDS directory"
fi

# Check for PET data
PET_COUNT=$(find "$BIDS_DIR" -name "*_pet.nii*" -o -name "*_pet.json" | wc -l)
if [ $PET_COUNT -eq 0 ]; then
    echo "Warning: No PET files found in BIDS directory"
else
    echo "Found PET-related files in BIDS directory"
fi

echo

# Check if Singularity is installed
if ! command -v singularity &> /dev/null; then
    echo "Error: Singularity is not installed or not in PATH"
    exit 1
fi

# Run the container
echo "Command: singularity run $BIND_MOUNTS $CONTAINER $CMD_ARGS"
echo

exec singularity run $BIND_MOUNTS "$CONTAINER" $CMD_ARGS