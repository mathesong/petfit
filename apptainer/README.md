# Apptainer Implementation for PETFit Apps

This directory contains the [Apptainer](https://apptainer.org/) (formerly Singularity) definition file for running the PETFit region definition and modelling apps in containerised environments, particularly suited for HPC clusters and shared computing resources.

## Quick Start

The fastest way to get started is to pull a pre-built image directly from Docker Hub.

```bash
apptainer build petfit_latest.sif docker://mathesong/petfit:latest
```

For HPC, SSH port forwarding is needed for interactive (Shiny) mode, since Apptainer typically uses the host network and does not provide Docker-style `-p host:container` port publishing.

```bash
ssh -L 3838:localhost:3838 username@servername
```

Then run apptainer directly — see the [main README](../README.md#apptainer-usage) for ready-to-copy interactive and automatic invocations.

## Building from source

If you need to build the SIF locally (e.g. to customise the definition or work offline):

```bash
apptainer build petfit_latest.sif apptainer/petfit.def
```

This requires `sudo`/root access. The build pulls `rocker/shiny-verse:latest` as the base image and installs `kinfitr` and the package's R dependencies.

## Files

- `petfit.def` — Apptainer definition file (equivalent to a Dockerfile)
- `README.md` — this file

## HPC integration examples

### SLURM

**Interactive job (for GUI usage):**

```bash
#!/bin/bash
#SBATCH --job-name=petfit-interactive
#SBATCH --time=04:00:00
#SBATCH --mem=8G
#SBATCH --cpus-per-task=2

module load apptainer

apptainer run --cleanenv \
  -B /scratch/project/bids_data:/data/bids_dir:ro \
  -B /scratch/project/derivatives:/data/derivatives_dir:rw \
  -B /scratch/project/blood:/data/blood_dir:ro \
  -B /tmp:/tmp \
  petfit_latest.sif \
  --func modelling_plasma
```

**Batch processing with job arrays:**

```bash
#!/bin/bash
#SBATCH --job-name=petfit-batch
#SBATCH --time=02:00:00
#SBATCH --mem=4G
#SBATCH --cpus-per-task=1
#SBATCH --array=1-10

module load apptainer

ANALYSES=(Analysis1 Analysis2 Analysis3 Study_A Study_B
          Custom_Run Test_1 Test_2 Validation_1 Validation_2)
CURRENT=${ANALYSES[$SLURM_ARRAY_TASK_ID-1]}

apptainer run --cleanenv \
  -B /scratch/project/bids_data:/data/bids_dir:ro \
  -B /scratch/project/derivatives:/data/derivatives_dir:rw \
  -B /scratch/project/blood:/data/blood_dir:ro \
  -B /tmp:/tmp \
  petfit_latest.sif \
  --func modelling_plasma --mode automatic \
  --analysis_foldername "$CURRENT"
```

### PBS/Torque

```bash
#!/bin/bash
#PBS -N petfit-processing
#PBS -l walltime=02:00:00
#PBS -l mem=4gb
#PBS -l ncpus=1

cd $PBS_O_WORKDIR
module load apptainer

apptainer run --cleanenv \
  -B /data/bids:/data/bids_dir:ro \
  -B /data/derivatives:/data/derivatives_dir:rw \
  -B /data/blood:/data/blood_dir:ro \
  -B /tmp:/tmp \
  petfit_latest.sif \
  --func modelling_plasma --mode automatic \
  --analysis_foldername "Primary_Analysis"
```

### LSF

```bash
#!/bin/bash
#BSUB -J petfit-batch
#BSUB -W 02:00
#BSUB -M 4000
#BSUB -n 1

module load apptainer

apptainer run --cleanenv \
  -B /data/bids:/data/bids_dir:ro \
  -B /data/derivatives:/data/derivatives_dir:rw \
  -B /tmp:/tmp \
  petfit_latest.sif \
  --func modelling_plasma --mode automatic \
  --analysis_foldername "Analysis_$(printf %03d $LSB_JOBINDEX)"
```

## Troubleshooting

### No internet on compute nodes

Build the SIF on a login node, then copy it to your project space.

### Home directory size limits

Build in a scratch directory and set the cache location:

```bash
export APPTAINER_CACHEDIR=/scratch/$USER/apptainer_cache
```

### Module loading

Common module names across HPC systems:

```bash
module load apptainer
module load singularity
module load singularity-ce
```

### Debug mode

```bash
apptainer run --debug petfit_latest.sif --func modelling_plasma --help
```

## Container comparison: Docker vs Apptainer

| Feature | Docker | Apptainer |
|---------|---------|-----------|
| **Security model** | Root daemon | User-space, no daemon |
| **HPC suitability** | Limited | Excellent |
| **Networking** | Port mapping required | Direct host network access |
| **File permissions** | Can be complex | Preserves user permissions |
| **Build requirements** | Root access | Sudo for build only |
| **Runtime requirements** | Root daemon | User-space execution |
| **Container format** | Layers | Single SIF file |
