# Apptainer

[Apptainer](https://apptainer.org/) (formerly Singularity) is the standard container runtime on HPC clusters. PETFit's Apptainer definition file lives in the `apptainer/` directory of the repository.

## Building the container

### Prerequisites

- Apptainer installed (or Singularity, which uses the same commands)
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

## Simplified workflow: the `petfit` alias

Apptainer auto-mounts your `$HOME`, `$PWD`, and `/tmp`, and runs as your own user. So for data under your home directory you need no `-B` flags at all. Define an alias once (in `~/.bashrc`):

```bash
alias petfit='apptainer run petfit_latest.sif'
```

then run with bare host paths:

```bash
petfit --func modelling_plasma --bids_dir ~/data/bids --blood_dir ~/data/blood
```

For data outside `$HOME` (e.g. `/scratch`), add an explicit `-B /scratch:/scratch`, or ask your admin to add `bind path = /scratch` to `/etc/apptainer/apptainer.conf`. Otherwise, the explicit `-B` examples below work everywhere.

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

Then open the address the container prints in your browser — `http://localhost:3838` by default. Because Apptainer shares the host network, if port 3838 is already in use on the node the container automatically scans upward for the next free port (3838–3858) and prints a line such as:

```text
Requested Shiny port 3838 is in use. Using 3839 instead.
```

On a remote HPC, use SSH port forwarding first in order to be able to access the browser interface on your local machine. Forward whichever port the container reports:

```bash
ssh -L 3838:localhost:3838 username@servername
```

To request a specific starting port instead of 3838, set `SHINY_PORT` (with `--cleanenv` you must pass it explicitly):

```bash
apptainer run --cleanenv --env SHINY_PORT=8080 \
  -B /path/to/derivatives:/data/derivatives_dir:rw \
  -B /tmp:/tmp \
  petfit_latest.sif \
  --func regiondef
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



## Volume mounting

Apptainer uses `--bind` (or `-B`) instead of Docker's `-v`:

```bash
--bind /host/path:/container/path

# Multiple mounts
--bind /data/bids:/data/bids_dir \
--bind /analysis:/data/derivatives_dir \
--bind /blood:/data/blood_dir
```

## External config and regions files

A config file or `petfit_regions.tsv` kept outside the dataset can be pointed at
directly. Bind the file itself and name it with `--config_file` (modelling apps)
or `--regions_file` (`regiondef`). PETFit copies it into the analysis folder, or
the petfit output folder, before running, so the settings which produced the
outputs sit beside them:

```bash
apptainer run \
  -B /scratch/project/derivatives:/data/derivatives_dir:rw \
  -B /home/user/configs/petfit_config.json:/data/config.json:ro \
  petfit_latest.sif \
  --func modelling_ref \
  --mode automatic \
  --analysis_foldername Shared_Settings \
  --config_file /data/config.json
```

Because Apptainer auto-mounts your home directory, a config already under `$HOME`
needs no bind at all -- pass its host path straight to `--config_file`, the same
way `--bids_dir` and `--derivatives_dir` are used above.

The console reports each copy, and says explicitly when a file already in that
folder was replaced.

## Merging runs

Region definition pools a measurement's runs into one measurement by default,
for the common case where `run-01` and `run-02` are two scanning occasions from
a single injection. Pass `--no_merge_runs` for datasets where each run is a
separate injection:

```bash
apptainer run \
  -B /scratch/project/derivatives:/data/derivatives_dir:rw \
  petfit_latest.sif \
  --func regiondef \
  --mode automatic \
  --no_merge_runs
```

The option belongs to `regiondef` alone -- merging is decided there and is then a
property of the combined TACs -- and is ignored by the modelling apps. See
[Merging runs](../usage/region-definition.md#merging-runs).

## Troubleshooting

### Directory not found

```bash
# Verify bind mount paths exist
ls -la /host/path/to/data

# Check inside the container
apptainer exec petfit_latest.sif ls -la /data/bids_dir
```

### Port already in use

Apptainer shares the host network, so a busy port 3838 on the node would otherwise clash. The container detects this automatically and binds the next free port in the range 3838–3858, printing the address to use (e.g. `Requested Shiny port 3838 is in use. Using 3839 instead.`). Set up SSH forwarding to whichever port it reports (`ssh -L <port>:localhost:<port>`). To choose the starting port yourself, pass `--env SHINY_PORT=<port>`.

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
