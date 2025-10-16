# Singularity Implementation for petfit Apps

This directory contains Singularity implementation files for running the petfit region definition and modelling apps in containerized environments, particularly suited for HPC clusters and shared computing resources.

## Quick Start

### Building the Container

```bash
# Basic build
cd singularity/
./build.sh

# Build with custom name/tag
./build.sh --name petfit --tag v1.0

# Build as sandbox for development
./build.sh --sandbox
```

### Interactive Mode

```bash
# Modelling app with plasma input
./run-interactive.sh --func modelling_plasma --bids-dir /path/to/your/bids --blood-dir /path/to/blood

# Modelling app with reference tissue
./run-interactive.sh --func modelling_ref --bids-dir /path/to/your/bids

# Region definition app
./run-interactive.sh --func regiondef --bids-dir /path/to/your/bids

# With custom port for server usage
./run-interactive.sh --func modelling_plasma --host-port 8080 --bids-dir /path/to/your/bids --blood-dir /path/to/blood
```

Then open http://localhost:3838 (or your custom port) in your browser.

### Automatic Mode

```bash
# Full pipeline execution with plasma input
./run-automatic.sh --func modelling_plasma --derivatives-dir /path/to/derivatives --blood-dir /path/to/blood

# Full pipeline execution with reference tissue
./run-automatic.sh --func modelling_ref --derivatives-dir /path/to/derivatives

# Single step execution
./run-automatic.sh --func modelling_plasma --derivatives-dir /path/to/derivatives --step weights
```

## Files Overview

### Core Files
- `petfit.def` - Singularity definition file (equivalent to Dockerfile)
- `build.sh` - Container build script with options
- `README.md` - This documentation file

### Run Scripts
- `run-interactive.sh` - Interactive mode for region definition, plasma input, and reference tissue modelling apps
- `run-automatic.sh` - Automatic/batch processing mode

## Building the Container

### Prerequisites

- Singularity/Apptainer installed on your system
- Internet connection for downloading base images and packages
- Sudo/root access (for building, not running)

### Build Options

```bash
./build.sh [options]

Options:
  -n, --name NAME         Container image name (default: petfit)
  -t, --tag TAG           Container tag (default: latest)  
  -s, --sandbox           Build as sandbox (writable) instead of SIF
  -r, --remote            Build remotely using Singularity Cloud
  --user-id ID            User ID for container user (default: current user)
  --group-id ID           Group ID for container user (default: current group)
  --user-name NAME        Username for container user (default: petfit)
```

### Examples

```bash
# Standard build
./build.sh

# Development build (writable sandbox)
./build.sh --sandbox --name petfit-dev

# Build for specific user permissions
./build.sh --user-id 1001 --group-id 1001

# Remote build (requires Singularity Cloud account)
./build.sh --remote
```

## Running the Container

### Interactive Mode

Interactive mode launches a Shiny web application accessible via browser.


#### Region Definition App
```bash
# Basic region definition
./run-interactive.sh --func regiondef --bids-dir /data/study_bids

# With custom derivatives location
./run-interactive.sh \
  --func regiondef \
  --bids-dir /data/study_bids \
  --derivatives-dir /analysis/derivatives
```

#### Modelling App with Plasma Input
```bash
# Basic usage
./run-interactive.sh --func modelling_plasma --bids-dir /data/study_bids --blood-dir /data/blood

# With all directories specified
./run-interactive.sh \
  --func modelling_plasma \
  --bids-dir /data/study_bids \
  --derivatives-dir /analysis/derivatives \
  --blood-dir /data/blood

# Custom port and analysis settings
./run-interactive.sh \
  --func modelling_plasma \
  --bids-dir /data/study_bids \
  --blood-dir /data/blood \
  --host-port 8080 \
  --analysis-folder "Custom_Analysis"
```

#### Modelling App with Reference Tissue
```bash
# Basic usage
./run-interactive.sh --func modelling_ref --bids-dir /data/study_bids

# With all directories specified
./run-interactive.sh \
  --func modelling_ref \
  --bids-dir /data/study_bids \
  --derivatives-dir /analysis/derivatives

# Custom port and analysis settings
./run-interactive.sh \
  --func modelling_ref \
  --bids-dir /data/study_bids \
  --host-port 8080 \
  --analysis-folder "Custom_Analysis"
```



### Automatic Mode

Automatic mode runs processing pipelines without user interaction, ideal for batch processing and HPC environments.

#### Full Pipeline
```bash
# Complete analysis pipeline with plasma input
./run-automatic.sh \
  --func modelling_plasma \
  --derivatives-dir /analysis/derivatives \
  --blood-dir /data/blood

# Complete analysis pipeline with reference tissue
./run-automatic.sh \
  --func modelling_ref \
  --derivatives-dir /analysis/derivatives
```

#### Step-by-Step Processing
```bash
# Data definition step
./run-automatic.sh --func modelling_plasma --derivatives-dir /analysis/derivatives --step datadef

# Weights calculation
./run-automatic.sh --func modelling_plasma --derivatives-dir /analysis/derivatives --step weights

# Delay fitting (requires blood data)
./run-automatic.sh \
  --func modelling_plasma \
  --derivatives-dir /analysis/derivatives \
  --blood-dir /data/blood \
  --step delay

# Model fitting steps
./run-automatic.sh \
  --func modelling_plasma \
  --derivatives-dir /analysis/derivatives \
  --blood-dir /data/blood \
  --step model1
```

### Direct Singularity Commands

If you prefer to use Singularity directly:

```bash
# Interactive modelling app with plasma input
singularity run \
  --bind /data/bids:/data/bids_dir \
  --bind /analysis/derivatives:/data/derivatives_dir \
  --bind /data/blood:/data/blood_dir \
  petfit_latest.sif \
  --func modelling_plasma

# Interactive modelling app with reference tissue
singularity run \
  --bind /data/bids:/data/bids_dir \
  --bind /analysis/derivatives:/data/derivatives_dir \
  petfit_latest.sif \
  --func modelling_ref

# Automatic processing
singularity run \
  --bind /analysis/derivatives:/data/derivatives_dir \
  --bind /data/blood:/data/blood_dir \
  petfit_latest.sif \
  --func modelling_plasma --mode automatic --step weights
```

## HPC Integration

### SLURM Examples

#### Interactive Job for GUI Usage
```bash
#!/bin/bash
#SBATCH --job-name=petfit-interactive
#SBATCH --time=04:00:00
#SBATCH --mem=8G
#SBATCH --cpus-per-task=2

# Load Singularity module (adjust for your cluster)
module load singularity

# Run interactive app (use salloc for interactive session)
./run-interactive.sh \
  --func modelling_plasma \
  --bids-dir /scratch/project/bids_data \
  --derivatives-dir /scratch/project/derivatives \
  --blood-dir /scratch/project/blood \
  --host-port 8080
```

#### Batch Processing Job
```bash
#!/bin/bash
#SBATCH --job-name=petfit-batch
#SBATCH --time=02:00:00
#SBATCH --mem=4G
#SBATCH --cpus-per-task=1
#SBATCH --array=1-10

# Load Singularity module
module load singularity

# Process different analysis folders
ANALYSIS_FOLDERS=(Analysis1 Analysis2 Analysis3 Study_A Study_B Custom_Run Test_1 Test_2 Validation_1 Validation_2)
CURRENT_ANALYSIS=${ANALYSIS_FOLDERS[$SLURM_ARRAY_TASK_ID-1]}

echo "Processing analysis: $CURRENT_ANALYSIS"

./run-automatic.sh \
  --func modelling_plasma \
  --derivatives-dir /scratch/project/derivatives \
  --blood-dir /scratch/project/blood \
  --analysis-folder "$CURRENT_ANALYSIS"
```

#### Step-wise Processing
```bash
#!/bin/bash
#SBATCH --job-name=petfit-step
#SBATCH --time=01:00:00
#SBATCH --mem=2G

module load singularity

# Run specific processing step
./run-automatic.sh \
  --func modelling_plasma \
  --derivatives-dir /scratch/project/derivatives \
  --step weights \
  --analysis-folder "$1"  # Pass analysis folder as argument
```

### PBS/Torque Examples

```bash
#!/bin/bash
#PBS -N petfit-processing
#PBS -l walltime=02:00:00
#PBS -l mem=4gb
#PBS -l ncpus=1

cd $PBS_O_WORKDIR
module load singularity

./run-automatic.sh \
  --func modelling_plasma \
  --derivatives-dir /data/derivatives \
  --blood-dir /data/blood \
  --analysis-folder "Primary_Analysis"
```

### LSF Examples

```bash
#!/bin/bash
#BSUB -J petfit-batch
#BSUB -W 02:00
#BSUB -M 4000
#BSUB -n 1

module load singularity

./run-automatic.sh \
  --func modelling_plasma \
  --derivatives-dir /data/derivatives \
  --analysis-folder "Analysis_$(printf %03d $LSB_JOBINDEX)"
```

## Directory Requirements and Mounting

### Volume Mounting
Singularity uses `--bind` for mounting host directories:

```bash
# Basic format
--bind /host/path:/container/path

# Multiple mounts
--bind /data/bids:/data/bids_dir \
--bind /analysis:/data/derivatives_dir \
--bind /blood:/data/blood_dir
```

### Required Directory Structure

#### For Region Definition
```
bids_dir/
├── sub-01/
│   ├── ses-1/
│   │   └── pet/
│   │       ├── sub-01_ses-1_task-rest_pet.nii.gz
│   │       └── sub-01_ses-1_task-rest_pet.json
├── participants.tsv
└── dataset_description.json
```

#### For Modelling (Automatic Mode)
```
derivatives_dir/
└── petfit/
    └── analysis_folder/
        ├── desc-petfitoptions_config.json
        ├── desc-combinedregions_tacs.tsv
        └── reports/
            └── [generated reports]
```

### Blood Data Structure
```
blood_dir/
├── sub-01_ses-1_task-rest_blood.tsv
├── sub-02_ses-1_task-rest_inputfunction.tsv
└── [other blood/input function files]
```

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**
   ```bash
   # Ensure proper user/group mapping during build
   ./build.sh --user-id $(id -u) --group-id $(id -g)
   ```

2. **Directory Not Found**
   ```bash
   # Check bind mount paths exist
   ls -la /host/path/to/data
   
   # Verify container paths
   singularity exec container.sif ls -la /data/bids_dir
   ```

3. **Port Already in Use**
   ```bash
   # Use different host port
   ./run-interactive.sh --host-port 8080 --bids-dir /path/to/data
   ```

4. **Container Build Fails**
   ```bash
   # Try sandbox build for debugging
   ./build.sh --sandbox
   
   # Or build remotely
   ./build.sh --remote
   ```

### HPC-Specific Issues

1. **No Internet Access on Compute Nodes**
   - Build container on login node
   - Transfer SIF file to scratch/project space

2. **Home Directory Size Limits**
   - Build in scratch or project directory
   - Set `SINGULARITY_CACHEDIR` environment variable

3. **Module Loading**
   ```bash
   # Common module names
   module load singularity
   module load apptainer
   module load singularity-ce
   ```

### Debug Mode

```bash
# Enable verbose output
export SINGULARITY_VERBOSE=true

# Debug container execution
singularity run --debug container.sif --func modelling_plasma --help
```

## Performance Considerations

### Memory Requirements
- **Interactive mode**: 4-8 GB RAM recommended
- **Automatic mode**: 2-4 GB RAM typically sufficient
- **Large datasets**: Scale memory with data size

### CPU Usage
- Most operations are single-threaded
- I/O intensive during file processing
- Model fitting may benefit from multiple cores

### Storage
- **Container size**: ~2-3 GB for SIF file
- **Working space**: Plan for 2-5x input data size
- **Reports**: Minimal additional space (~50-100 MB per analysis)

## Container Comparison: Docker vs Singularity

| Feature | Docker | Singularity |
|---------|---------|-------------|
| **Security Model** | Root daemon | User-space, no daemon |
| **HPC Suitability** | Limited | Excellent |
| **Networking** | Port mapping required | Direct host network access |
| **File Permissions** | Can be complex | Preserves user permissions |
| **Build Requirements** | Root access | Sudo for build only |
| **Runtime Requirements** | Root daemon | User-space execution |
| **Container Format** | Layers | Single SIF file |

## Migration from Docker

If you're familiar with the Docker implementation:

| Docker Command | Singularity Equivalent |
|----------------|------------------------|
| `docker run -it --rm -v /data:/data/bids_dir -p 3838:3838 petfit --func modelling_plasma` | `singularity run --bind /data:/data/bids_dir petfit.sif --func modelling_plasma` |
| `docker-compose up petfit-modelling-plasma` | `./run-interactive.sh --func modelling_plasma --bids-dir /data` |
| `docker build -t petfit .` | `./build.sh --name petfit` |

The command-line arguments and functionality remain identical between Docker and Singularity versions.

## Support and Resources

- **Singularity Documentation**: https://docs.sylabs.io/
- **HPC Best Practices**: https://docs.sylabs.io/guides/latest/user-guide/
- **Container Registry**: Build and push to container registries for sharing
- **petfit Package**: https://github.com/mathesong/petfit