# Singularity / Apptainer

Singularity (now [Apptainer](https://apptainer.org/)) is the standard container runtime on HPC clusters. PETFit provides build scripts and run wrappers in the `singularity/` directory.

## Building the container

### Prerequisites

- Singularity or Apptainer installed
- `sudo` access for building (not for running)
- Internet access during the build

### Basic build

```bash
cd singularity/
./build.sh
```

This creates a `petfit_latest.sif` file.

### Build options

```bash
./build.sh [options]

Options:
  -n, --name NAME         Image name (default: petfit)
  -t, --tag TAG           Tag (default: latest)
  -s, --sandbox           Build as writable sandbox
  -r, --remote            Build remotely via Singularity Cloud
  --user-id ID            User ID for container (default: current user)
  --group-id ID           Group ID for container (default: current group)
```

```bash
# Development build
./build.sh --sandbox --name petfit-dev

# Build for specific permissions
./build.sh --user-id 1001 --group-id 1001

# Remote build
./build.sh --remote
```

## Interactive mode

Interactive mode launches a Shiny web app accessible in your browser.

```bash
# Region definition
./run-interactive.sh --func regiondef --bids-dir /path/to/bids

# Plasma input modelling
./run-interactive.sh --func modelling_plasma \
  --bids-dir /path/to/bids \
  --blood-dir /path/to/blood

# Reference tissue modelling
./run-interactive.sh --func modelling_ref --bids-dir /path/to/bids

# Custom port
./run-interactive.sh --func modelling_plasma \
  --host-port 8080 \
  --bids-dir /path/to/bids \
  --blood-dir /path/to/blood
```

Then open `http://localhost:3838` (or your custom port) in your browser.

## Automatic mode

```bash
# Full pipeline
./run-automatic.sh --func modelling_plasma \
  --derivatives-dir /path/to/derivatives \
  --blood-dir /path/to/blood

# Single step
./run-automatic.sh --func modelling_plasma \
  --derivatives-dir /path/to/derivatives \
  --step weights

# Custom analysis folder
./run-automatic.sh --func modelling_plasma \
  --derivatives-dir /path/to/derivatives \
  --blood-dir /path/to/blood \
  --analysis-folder "Baseline_only"
```

## Direct Singularity commands

If you prefer not to use the wrapper scripts:

```bash
# Interactive
singularity run \
  --bind /data/bids:/data/bids_dir \
  --bind /analysis/derivatives:/data/derivatives_dir \
  --bind /data/blood:/data/blood_dir \
  petfit_latest.sif \
  --func modelling_plasma

# Automatic
singularity run \
  --bind /analysis/derivatives:/data/derivatives_dir \
  --bind /data/blood:/data/blood_dir \
  petfit_latest.sif \
  --func modelling_plasma --mode automatic --step weights
```

## HPC integration

### SLURM

**Interactive job (for GUI usage):**

```bash
#!/bin/bash
#SBATCH --job-name=petfit-interactive
#SBATCH --time=04:00:00
#SBATCH --mem=8G
#SBATCH --cpus-per-task=2

module load singularity

./run-interactive.sh \
  --func modelling_plasma \
  --bids-dir /scratch/project/bids_data \
  --derivatives-dir /scratch/project/derivatives \
  --blood-dir /scratch/project/blood \
  --host-port 8080
```

**Batch processing with job arrays:**

```bash
#!/bin/bash
#SBATCH --job-name=petfit-batch
#SBATCH --time=02:00:00
#SBATCH --mem=4G
#SBATCH --cpus-per-task=1
#SBATCH --array=1-10

module load singularity

ANALYSES=(Analysis1 Analysis2 Analysis3 Study_A Study_B
          Custom_Run Test_1 Test_2 Validation_1 Validation_2)
CURRENT=${ANALYSES[$SLURM_ARRAY_TASK_ID-1]}

./run-automatic.sh \
  --func modelling_plasma \
  --derivatives-dir /scratch/project/derivatives \
  --blood-dir /scratch/project/blood \
  --analysis-folder "$CURRENT"
```

**Step-wise processing:**

```bash
#!/bin/bash
#SBATCH --job-name=petfit-step
#SBATCH --time=01:00:00
#SBATCH --mem=2G

module load singularity

./run-automatic.sh \
  --func modelling_plasma \
  --derivatives-dir /scratch/project/derivatives \
  --step weights \
  --analysis-folder "$1"
```

### PBS/Torque

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

### LSF

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

## Volume mounting

Singularity uses `--bind` instead of Docker's `-v`:

```bash
--bind /host/path:/container/path

# Multiple mounts
--bind /data/bids:/data/bids_dir \
--bind /analysis:/data/derivatives_dir \
--bind /blood:/data/blood_dir
```

## Troubleshooting

### Permission denied errors

```bash
# Ensure proper user/group mapping
./build.sh --user-id $(id -u) --group-id $(id -g)
```

### Directory not found

```bash
# Verify bind mount paths exist
ls -la /host/path/to/data

# Check inside the container
singularity exec petfit_latest.sif ls -la /data/bids_dir
```

### Port already in use

```bash
./run-interactive.sh --host-port 8080 --bids-dir /path/to/data
```

### No internet on compute nodes

Build the container on a login node, then copy the `.sif` file to your project space.

### Home directory size limits

Build in a scratch directory and set `SINGULARITY_CACHEDIR`:

```bash
export SINGULARITY_CACHEDIR=/scratch/$USER/singularity_cache
./build.sh
```

### Module loading

Common module names across HPC systems:

```bash
module load singularity
module load apptainer
module load singularity-ce
```

### Debug mode

```bash
export SINGULARITY_VERBOSE=true
singularity run --debug petfit_latest.sif --func modelling_plasma --help
```

## Performance considerations

| Resource | Interactive mode | Automatic mode |
|----------|-----------------|----------------|
| **RAM** | 4–8 GB recommended | 2–4 GB typically sufficient |
| **CPU** | Mostly single-threaded | I/O intensive, model fitting benefits from multiple cores |
| **Container size** | ~2–3 GB for `.sif` file | Same |
| **Working space** | 2–5x input data size | Same |
| **Report storage** | ~50–100 MB per analysis | Same |

## Docker to Singularity migration

| Docker | Singularity |
|--------|-------------|
| `docker run -it --rm -v /data:/data/bids_dir -p 3838:3838 petfit --func modelling_plasma` | `singularity run --bind /data:/data/bids_dir petfit.sif --func modelling_plasma` |
| `docker-compose up petfit-modelling-plasma` | `./run-interactive.sh --func modelling_plasma --bids-dir /data` |
| `docker build -t petfit .` | `./build.sh --name petfit` |

The command-line arguments and functionality are identical between Docker and Singularity.
