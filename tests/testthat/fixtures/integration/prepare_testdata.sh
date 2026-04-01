#!/usr/bin/env bash
#
# prepare_testdata.sh
#
# One-time script to prepare the ds004869 test dataset for petfit integration tests.
# Requires: datalad, tar
#
# This script:
#   1. Downloads ds004869 from OpenNeuro via datalad
#   2. Replaces all broken symlinks (git-annex files) with empty files
#   3. Strips all version control metadata (.git, .datalad, .gitattributes)
#   4. Creates a tarball: ds004869_testdata.tar.gz
#
# The resulting tarball contains only real TSV/JSON files (with content) and
# empty placeholder files where NIfTI/binary files would be. This allows
# integration tests to run without datalad or git-annex.
#
# Usage:
#   ./prepare_testdata.sh [--output-dir /path/to/output]
#
# The tarball should be uploaded as a GitHub Release asset for CI use.

set -euo pipefail

# Parse arguments
OUTPUT_DIR="."
while [[ $# -gt 0 ]]; do
  case $1 in
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--output-dir /path/to/output]"
      echo ""
      echo "Downloads ds004869, prepares it for testing, and creates a tarball."
      echo "Requires: datalad, tar"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# Check dependencies
if ! command -v datalad &> /dev/null; then
  echo "ERROR: datalad is not installed or not in PATH"
  echo "Install with: pip install datalad"
  exit 1
fi

if ! command -v tar &> /dev/null; then
  echo "ERROR: tar is not found"
  exit 1
fi

# Create a temporary working directory
WORK_DIR=$(mktemp -d)
echo "Working directory: ${WORK_DIR}"

# Ensure cleanup on exit
cleanup() {
  echo "Cleaning up working directory..."
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

# Step 1: Download dataset via datalad
echo ""
echo "=== Step 1: Downloading ds004869 via datalad ==="
echo "This will download ~104MB of metadata and small files..."
datalad install -s https://github.com/OpenNeuroDatasets/ds004869.git "${WORK_DIR}/ds004869"

# Step 2: Replace broken symlinks with empty files
echo ""
echo "=== Step 2: Replacing broken symlinks with empty files ==="
BROKEN_COUNT=0
while IFS= read -r -d '' symlink; do
  # Remove the broken symlink and create an empty file in its place
  rm "$symlink"
  touch "$symlink"
  BROKEN_COUNT=$((BROKEN_COUNT + 1))
done < <(find "${WORK_DIR}/ds004869" -xtype l -print0)
echo "Replaced ${BROKEN_COUNT} broken symlinks with empty files"

# Step 3: Strip version control metadata
echo ""
echo "=== Step 3: Stripping version control metadata ==="
rm -rf "${WORK_DIR}/ds004869/.git"
rm -rf "${WORK_DIR}/ds004869/.datalad"
rm -f "${WORK_DIR}/ds004869/.gitattributes"

# Also remove any nested .git/.datalad (shouldn't exist but be safe)
find "${WORK_DIR}/ds004869" -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
find "${WORK_DIR}/ds004869" -name ".datalad" -type d -exec rm -rf {} + 2>/dev/null || true
find "${WORK_DIR}/ds004869" -name ".gitattributes" -type f -delete 2>/dev/null || true

# Step 4: Verify no broken symlinks remain
echo ""
echo "=== Step 4: Verification ==="
REMAINING_BROKEN=$(find "${WORK_DIR}/ds004869" -xtype l 2>/dev/null | wc -l)
if [ "$REMAINING_BROKEN" -gt 0 ]; then
  echo "WARNING: ${REMAINING_BROKEN} broken symlinks still remain!"
  find "${WORK_DIR}/ds004869" -xtype l | head -10
else
  echo "No broken symlinks remain"
fi

# Count real files
TACS_COUNT=$(find "${WORK_DIR}/ds004869/derivatives" -name "*_tacs.tsv" | wc -l)
BLOOD_COUNT=$(find "${WORK_DIR}/ds004869" -name "*_blood.tsv" | wc -l)
MORPH_COUNT=$(find "${WORK_DIR}/ds004869/derivatives" -name "*_morph.tsv" | wc -l)
JSON_COUNT=$(find "${WORK_DIR}/ds004869" -name "*.json" | wc -l)

echo "TACs files: ${TACS_COUNT}"
echo "Blood files: ${BLOOD_COUNT}"
echo "Morph files: ${MORPH_COUNT}"
echo "JSON files: ${JSON_COUNT}"

# Step 5: Create tarball
echo ""
echo "=== Step 5: Creating tarball ==="
TARBALL="${OUTPUT_DIR}/ds004869_testdata.tar.gz"
mkdir -p "${OUTPUT_DIR}"
tar -czf "${TARBALL}" -C "${WORK_DIR}" ds004869

TARBALL_SIZE=$(du -h "${TARBALL}" | cut -f1)
echo "Created: ${TARBALL} (${TARBALL_SIZE})"

# Print next steps
echo ""
echo "=== Done ==="
echo ""
echo "The tarball has been created at: ${TARBALL}"
echo ""
echo "Next steps:"
echo "  1. For local testing, copy the tarball to:"
echo "     tests/testthat/fixtures/integration/ds004869_testdata.tar.gz"
echo "     (Add this path to .gitignore -- do NOT commit the tarball)"
echo ""
echo "  2. For GitHub Actions, upload as a release asset:"
echo "     gh release create testdata-v1.0 \\"
echo "       --title 'Test Data v1.0' \\"
echo "       --notes 'ds004869 test dataset for integration tests' \\"
echo "       ${TARBALL}"
echo ""
echo "  3. To update the test data later, re-run this script and"
echo "     create a new release (e.g., testdata-v1.1)."
