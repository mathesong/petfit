#!/bin/bash

# Singularity run script for petfit automatic mode
# Usage: ./run-automatic.sh [options]

set -e

# Default values
CONTAINER="petfit_latest.sif"
FUNC=""
DERIVATIVES_DIR=""
BLOOD_DIR=""
STEP=""
PETFIT_FOLDER="petfit"
ANALYSIS_FOLDER="Primary_Analysis"

# Help function
show_help() {
    cat << EOF
Run petfit Singularity container in automatic mode

Usage: $0 [options]

Options:
    -c, --container PATH     Path to Singularity container (default: $CONTAINER)
    -f, --func FUNC          App function: 'modelling_plasma' or 'modelling_ref' [required]
    --derivatives-dir PATH   Path to derivatives directory to mount [required]
    --blood-dir PATH         Path to blood data directory to mount
    --step STEP              Specific step to run (optional)
    --petfit-folder NAME    Name for petfit output folder (default: $PETFIT_FOLDER)
    --analysis-folder NAME   Name for analysis subfolder (default: $ANALYSIS_FOLDER)
    -h, --help               Show this help message

Step Options:
    datadef     - Data definition step
    weights     - Weights calculation step  
    delay       - Delay fitting step
    model1      - Model 1 fitting step
    model2      - Model 2 fitting step
    model3      - Model 3 fitting step
    
    If no step specified, runs full pipeline based on configuration

Examples:
    # Full pipeline execution with plasma input models
    $0 --func modelling_plasma --derivatives-dir /path/to/derivatives --blood-dir /path/to/blood

    # Full pipeline execution with reference tissue models
    $0 --func modelling_ref --derivatives-dir /path/to/derivatives

    # Run specific step only
    $0 --func modelling_plasma --derivatives-dir /path/to/derivatives --step weights

    # Custom analysis folder
    $0 --func modelling_ref --derivatives-dir /path/to/derivatives --analysis-folder "Study_A"

    # Custom container
    $0 --container ./petfit_dev.sif --func modelling_plasma --derivatives-dir /path/to/derivatives

Requirements:
    - derivatives-dir must contain petfit folder with analysis subfolder
    - Analysis subfolder must contain desc-petfitoptions_config.json file
    - blood-dir only needed for delay fitting and invasive model steps

Directory Structure Expected:
    derivatives_dir/
    └── petfit/
        └── analysis_folder/
            ├── desc-petfitoptions_config.json
            └── [other analysis files]
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--container)
            CONTAINER="$2"
            shift 2
            ;;
        -f|--func)
            FUNC="$2"
            shift 2
            ;;
        --derivatives-dir)
            DERIVATIVES_DIR="$2"
            shift 2
            ;;
        --blood-dir)
            BLOOD_DIR="$2"
            shift 2
            ;;
        --step)
            STEP="$2"
            shift 2
            ;;
        --petfit-folder)
            PETFIT_FOLDER="$2"
            shift 2
            ;;
        --analysis-folder)
            ANALYSIS_FOLDER="$2"
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
if [ -z "$FUNC" ]; then
    echo "Error: --func is required"
    echo "Use --help for more information"
    exit 1
fi

if [ "$FUNC" != "modelling_plasma" ] && [ "$FUNC" != "modelling_ref" ]; then
    echo "Error: --func must be 'modelling_plasma' or 'modelling_ref'"
    exit 1
fi

if [ -z "$DERIVATIVES_DIR" ]; then
    echo "Error: --derivatives-dir is required for automatic mode"
    echo "Use --help for more information"
    exit 1
fi

# Validate step argument if provided
if [ -n "$STEP" ]; then
    valid_steps="datadef weights delay model1 model2 model3"
    if [[ ! " $valid_steps " =~ " $STEP " ]]; then
        echo "Error: Invalid step '$STEP'"
        echo "Valid steps: $valid_steps"
        exit 1
    fi
fi

# Check if container exists
if [ ! -f "$CONTAINER" ] && [ ! -d "$CONTAINER" ]; then
    echo "Error: Container not found: $CONTAINER"
    echo "Build the container first using: ./build.sh"
    exit 1
fi

# Validate directories exist
if [ ! -d "$DERIVATIVES_DIR" ]; then
    echo "Error: Derivatives directory does not exist: $DERIVATIVES_DIR"
    exit 1
fi

if [ -n "$BLOOD_DIR" ] && [ ! -d "$BLOOD_DIR" ]; then
    echo "Error: Blood directory does not exist: $BLOOD_DIR"
    exit 1
fi

# Check for analysis folder and config file
ANALYSIS_PATH="$DERIVATIVES_DIR/$PETFIT_FOLDER/$ANALYSIS_FOLDER"
CONFIG_FILE="$ANALYSIS_PATH/desc-petfitoptions_config.json"

if [ ! -d "$ANALYSIS_PATH" ]; then
    echo "Error: Analysis folder does not exist: $ANALYSIS_PATH"
    echo "Expected path: derivatives_dir/petfit_folder/analysis_folder"
    exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found: $CONFIG_FILE"
    echo "Run the appropriate modelling app in interactive mode first to create the configuration"
    exit 1
fi

# Build bind mounts
BIND_MOUNTS="--bind $DERIVATIVES_DIR:/data/derivatives_dir"

if [ -n "$BLOOD_DIR" ]; then
    BIND_MOUNTS="$BIND_MOUNTS --bind $BLOOD_DIR:/data/blood_dir"
fi

# Build command arguments
CMD_ARGS="--func $FUNC --mode automatic"
if [ -n "$STEP" ]; then
    CMD_ARGS="$CMD_ARGS --step $STEP"
fi
if [ -n "$PETFIT_FOLDER" ]; then
    CMD_ARGS="$CMD_ARGS --petfit_output_foldername $PETFIT_FOLDER"
fi
if [ -n "$ANALYSIS_FOLDER" ]; then
    CMD_ARGS="$CMD_ARGS --analysis_foldername $ANALYSIS_FOLDER"
fi

echo "=== petfit Singularity Automatic Mode ==="
echo "Container: $CONTAINER"
echo "Function: $FUNC"
echo "Derivatives directory: $DERIVATIVES_DIR"
if [ -n "$BLOOD_DIR" ]; then
    echo "Blood directory: $BLOOD_DIR"
fi
echo "petfit folder: $PETFIT_FOLDER"
echo "Analysis folder: $ANALYSIS_FOLDER"
echo "Analysis path: $ANALYSIS_PATH"
if [ -n "$STEP" ]; then
    echo "Step: $STEP"
else
    echo "Mode: Full pipeline"
fi
echo

echo "Starting automatic processing..."
echo

# Check if Singularity is installed
if ! command -v singularity &> /dev/null; then
    echo "Error: Singularity is not installed or not in PATH"
    exit 1
fi

# Run the container
echo "Command: singularity run $BIND_MOUNTS $CONTAINER $CMD_ARGS"
echo

singularity run $BIND_MOUNTS "$CONTAINER" $CMD_ARGS

# Capture exit code
EXIT_CODE=$?

echo
if [ $EXIT_CODE -eq 0 ]; then
    echo "=== Processing Completed Successfully ==="
    echo "Check the analysis folder for generated reports:"
    echo "  $ANALYSIS_PATH/reports/"
else
    echo "=== Processing Failed ==="
    echo "Exit code: $EXIT_CODE"
fi

exit $EXIT_CODE