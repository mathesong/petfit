#!/bin/bash

# Basic test script for Singularity integration
# Tests script functionality without requiring actual container build

set -e

echo "=== petfit Singularity Integration Test ==="
echo

# Test 1: Check all scripts are executable
echo "Test 1: Script permissions"
scripts=("build.sh" "run-interactive.sh" "run-automatic.sh" "run-regiondef.sh")
for script in "${scripts[@]}"; do
    if [ -x "$script" ]; then
        echo "✓ $script is executable"
    else
        echo "✗ $script is not executable"
        exit 1
    fi
done
echo

# Test 2: Check help functionality
echo "Test 2: Help functionality"
for script in "${scripts[@]}"; do
    if ./"$script" --help > /dev/null 2>&1; then
        echo "✓ $script --help works"
    else
        echo "✗ $script --help failed"
        exit 1
    fi
done
echo

# Test 3: Check argument parsing (should fail gracefully)
echo "Test 3: Argument validation"

# Test invalid function
if ./run-interactive.sh --func invalid --bids-dir /tmp 2>/dev/null; then
    echo "✗ Invalid function validation failed"
    exit 1
else
    echo "✓ Invalid function properly rejected"
fi

# Test missing required directory
if ./run-interactive.sh --func modelling 2>/dev/null; then
    echo "✗ Missing directory validation failed"
    exit 1  
else
    echo "✓ Missing directory properly detected"
fi

# Test invalid step
if ./run-automatic.sh --derivatives-dir /tmp --step invalid 2>/dev/null; then
    echo "✗ Invalid step validation failed"
    exit 1
else
    echo "✓ Invalid step properly rejected"
fi

echo

# Test 4: Check definition file syntax
echo "Test 4: Definition file validation"
if [ -f "petfit.def" ]; then
    # Basic syntax checks
    if grep -q "^Bootstrap: docker" petfit.def; then
        echo "✓ Bootstrap declaration found"
    else
        echo "✗ Bootstrap declaration missing"
        exit 1
    fi
    
    if grep -q "^From: rocker/shiny-verse" petfit.def; then
        echo "✓ Base image declaration found"
    else
        echo "✗ Base image declaration missing"
        exit 1
    fi
    
    if grep -q "%runscript" petfit.def; then
        echo "✓ Runscript section found"
    else
        echo "✗ Runscript section missing"
        exit 1
    fi
else
    echo "✗ petfit.def not found"
    exit 1
fi
echo

# Test 5: Documentation completeness
echo "Test 5: Documentation validation"
if [ -f "README.md" ]; then
    required_sections=("Quick Start" "Building the Container" "HPC Integration" "Troubleshooting")
    for section in "${required_sections[@]}"; do
        if grep -q "$section" README.md; then
            echo "✓ README.md contains '$section' section"
        else
            echo "✗ README.md missing '$section' section"
            exit 1
        fi
    done
else
    echo "✗ README.md not found"
    exit 1
fi
echo

echo "=== All Tests Passed ==="
echo "Singularity integration appears to be correctly implemented."
echo
echo "Next steps for full validation:"
echo "1. Install Singularity/Apptainer on your system"
echo "2. Run: ./build.sh --sandbox (for testing)"
echo "3. Test with actual data directories"
echo "4. Validate on HPC environment if available"