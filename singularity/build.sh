#!/bin/bash

# Singularity build script for petfit app
# Usage: ./build.sh [options]

set -e

# Default values
IMAGE_NAME="petfit"
TAG="latest"
BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$BUILD_DIR")"
SANDBOX=false
REMOTE=false
USER_ID=$(id -u)
GROUP_ID=$(id -g)
USER_NAME="petfit"

# Help function
show_help() {
    cat << EOF
Build script for petfit Singularity container

Usage: $0 [options]

Options:
    -n, --name NAME         Container image name (default: $IMAGE_NAME)
    -t, --tag TAG           Container tag (default: $TAG)
    -s, --sandbox           Build as sandbox (writable) instead of SIF
    -r, --remote            Build remotely using Singularity Cloud
    --user-id ID            User ID for container user (default: current user)
    --group-id ID           Group ID for container user (default: current group)
    --user-name NAME        Username for container user (default: $USER_NAME)
    -h, --help              Show this help message

Examples:
    # Basic build
    $0

    # Build with custom name and tag
    $0 --name mypetfit --tag v1.0

    # Build as sandbox for development
    $0 --sandbox

    # Build with specific user permissions
    $0 --user-id 1001 --group-id 1001
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            IMAGE_NAME="$2"
            shift 2
            ;;
        -t|--tag)
            TAG="$2"
            shift 2
            ;;
        -s|--sandbox)
            SANDBOX=true
            shift
            ;;
        -r|--remote)
            REMOTE=true
            shift
            ;;
        --user-id)
            USER_ID="$2"
            shift 2
            ;;
        --group-id)
            GROUP_ID="$2"
            shift 2
            ;;
        --user-name)
            USER_NAME="$2"
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

# Set output filename
if [ "$SANDBOX" = true ]; then
    OUTPUT="${IMAGE_NAME}_${TAG}_sandbox"
    BUILD_TYPE="sandbox"
else
    OUTPUT="${IMAGE_NAME}_${TAG}.sif"
    BUILD_TYPE="sif"
fi

# Build command setup
BUILD_CMD="singularity build"

if [ "$REMOTE" = true ]; then
    BUILD_CMD="$BUILD_CMD --remote"
fi

if [ "$SANDBOX" = true ]; then
    BUILD_CMD="$BUILD_CMD --sandbox"
fi

# Add build arguments for user configuration
BUILD_ARGS="--build-arg USER_ID=$USER_ID --build-arg GROUP_ID=$GROUP_ID --build-arg USER_NAME=$USER_NAME"

echo "=== petfit Singularity Build ==="
echo "Project root: $PROJECT_ROOT"
echo "Definition file: $BUILD_DIR/petfit.def"
echo "Output: $OUTPUT"
echo "Build type: $BUILD_TYPE"
echo "User ID: $USER_ID"
echo "Group ID: $GROUP_ID"
echo "User name: $USER_NAME"
if [ "$REMOTE" = true ]; then
    echo "Build mode: Remote"
else
    echo "Build mode: Local"
fi
echo

# Check if Singularity is installed
if ! command -v singularity &> /dev/null; then
    echo "Error: Singularity is not installed or not in PATH"
    echo "Please install Singularity from https://sylabs.io/guides/latest/user-guide/"
    exit 1
fi

# Check Singularity version
SINGULARITY_VERSION=$(singularity version 2>/dev/null || echo "unknown")
echo "Singularity version: $SINGULARITY_VERSION"

# Change to project root for build context
cd "$PROJECT_ROOT"

# Remove existing output if it exists
if [ -f "$OUTPUT" ] || [ -d "$OUTPUT" ]; then
    echo "Removing existing output: $OUTPUT"
    rm -rf "$OUTPUT"
fi

# Build the container
echo "Building container..."
echo "Command: $BUILD_CMD $BUILD_ARGS $OUTPUT $BUILD_DIR/petfit.def"
echo

$BUILD_CMD $BUILD_ARGS "$OUTPUT" "$BUILD_DIR/petfit.def"

# Check build result
if [ $? -eq 0 ]; then
    echo
    echo "=== Build Successful ==="
    echo "Container built: $OUTPUT"
    
    if [ "$SANDBOX" = false ]; then
        # Show container info for SIF files
        echo
        echo "Container information:"
        singularity inspect "$OUTPUT"
    fi
    
    echo
    echo "Test the container with:"
    echo "  singularity run $OUTPUT --help"
    echo
    echo "For interactive modelling app:"
    echo "  singularity run --bind /path/to/data:/data/bids_dir $OUTPUT --func modelling"
    echo
else
    echo
    echo "=== Build Failed ==="
    echo "Check the error messages above for details."
    exit 1
fi