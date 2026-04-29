# Apptainer

[Apptainer](https://apptainer.org/) (formerly Singularity) is the standard container runtime on HPC clusters. PETFit's Apptainer definition file lives in the `apptainer/` directory of the repository.

## Building the container

### Prerequisites

- Apptainer installed (or Singularity, which uses the same commands)
- `sudo` access for building (not for running)
- Internet access during the build

### Quickest path: pull from Docker Hub

```bash
apptainer build petfit_latest.sif docker://mathesong/petfit:latest
```

This converts the published Docker image into a SIF file. No local definition file is needed.

### Build from the definition file

If you need to customise the build (e.g. specific user/group IDs, work offline, modify dependencies):

```bash
apptainer build petfit_latest.sif apptainer/petfit.def
```

To pass build arguments such as a non-default user ID:

```bash
apptainer build \
  --build-arg USER_ID=1001 \
  --build-arg GROUP_ID=1001 \
  petfit_latest.sif apptainer/petfit.def
```

## Interactive mode

Interactive mode launches a Shiny web app accessible in your browser.

```bash
# Region definition
apptainer run --cleanenv \
  -B /path/to/bids:/data/bids_dir:ro \
  -B /path/to/derivatives:/data/derivatives_dir:rw \
  -B /tmp:/tmp \
  petfit_latest.sif \
  --func regiondef

# Plasma input modelling
apptainer run --cleanenv \
  -B /path/to/bids:/data/bids_dir:ro \
  -B /path/to/derivatives:/data/derivatives_dir:rw \
  -B /path/to/blood:/data/blood_dir:ro \
  -B /tmp:/tmp \
  petfit_latest.sif \
  --func modelling_plasma

# Reference tissue modelling
apptainer run --cleanenv \
  -B /path/to/bids:/data/bids_dir:ro \
  -B /path/to/derivatives:/data/derivatives_dir:rw \
  -B /tmp:/tmp \
  petfit_latest.sif \
  --func modelling_ref
```

Then open `http://localhost:3838` in your browser. On a remote HPC, use SSH port forwarding first:

```bash
ssh -L 3838:localhost:3838 username@servername
```

## Automatic mode

```bash
# Region definition
apptainer run --cleanenv \
  -B /path/to/derivatives:/data/derivatives_dir:rw \
  -B /tmp:/tmp \
  petfit_latest.sif \
  --func regiondef --mode automatic

# Modelling pipeline (plasma input)
apptainer run --cleanenv \
  -B /path/to/bids:/data/bids_dir:ro \
  -B /path/to/derivatives:/data/derivatives_dir:rw \
  -B /path/to/blood:/data/blood_dir:ro \
  -B /tmp:/tmp \
  petfit_latest.sif \
  --func modelling_plasma --mode automatic

# Single step (e.g. weights)
apptainer run --cleanenv \
  -B /path/to/derivatives:/data/derivatives_dir:rw \
  -B /tmp:/tmp \
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

## Volume mounting

Apptainer uses `--bind` (or `-B`) instead of Docker's `-v`:

```bash
--bind /host/path:/container/path

# Multiple mounts
--bind /data/bids:/data/bids_dir \
--bind /analysis:/data/derivatives_dir \
--bind /blood:/data/blood_dir
```

## Troubleshooting

### Directory not found

```bash
# Verify bind mount paths exist
ls -la /host/path/to/data

# Check inside the container
apptainer exec petfit_latest.sif ls -la /data/bids_dir
```

### Port already in use

Apptainer typically uses the host network — pick a different free port and use SSH forwarding (`ssh -L <free-port>:localhost:<free-port>`).

### No internet on compute nodes

Build the SIF on a login node, then copy the `.sif` file to your project space.

### Home directory size limits

Build in a scratch directory and set the cache location:

```bash
export APPTAINER_CACHEDIR=/scratch/$USER/apptainer_cache
apptainer build petfit_latest.sif docker://mathesong/petfit:latest
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

## Performance considerations

| Resource | Interactive mode | Automatic mode |
|----------|-----------------|----------------|
| **RAM** | 4–8 GB recommended | 2–4 GB typically sufficient |
| **CPU** | Mostly single-threaded | I/O intensive, model fitting benefits from multiple cores |
| **Container size** | ~2–3 GB for `.sif` file | Same |
| **Working space** | 2–5x input data size | Same |
| **Report storage** | ~50–100 MB per analysis | Same |

## Docker to Apptainer migration

| Docker | Apptainer |
|--------|-----------|
| `docker run -it --rm -v /data:/data/bids_dir -p 3838:3838 petfit --func modelling_plasma` | `apptainer run --bind /data:/data/bids_dir petfit_latest.sif --func modelling_plasma` |
| `docker build -t petfit .` | `apptainer build petfit_latest.sif apptainer/petfit.def` |
| `docker pull mathesong/petfit:latest` | `apptainer build petfit_latest.sif docker://mathesong/petfit:latest` |

The command-line arguments and functionality are identical between Docker and Apptainer.
