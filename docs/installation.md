# Installation

PETFit can be installed and run in three ways. Choose the approach that best suits your environment.

## R package

Install the development version directly from GitHub:

```r
# Install remotes if needed
install.packages("remotes")

# Install petfit
remotes::install_github("mathesong/petfit")
```

### Prerequisites

- **R** >= 4.0
- The [kinfitr](https://github.com/mathesong/kinfitr) package (installed automatically as a dependency)
- Standard R package build tools (`Rtools` on Windows, `r-base-dev` on Linux)

### Verifying the installation

```r
library(petfit)
?petfit_interactive
```

## Docker

Docker is the recommended approach for most users. It bundles all dependencies and avoids package installation issues.

### Pull the pre-built image

```bash
docker pull mathesong/petfit:latest
```

### Build from source

If you prefer to build locally:

```bash
git clone https://github.com/mathesong/petfit.git
cd petfit
docker build -f docker/Dockerfile -t mathesong/petfit:latest .
```

See [Docker usage](containers/docker.md) for full details on running the container.

## Apptainer

[Apptainer](https://apptainer.org/) (formerly Singularity) is the standard container runtime on HPC clusters. PETFit's Apptainer definition file lives in the `apptainer/` directory.

### Build from the Docker image

The fastest path is to convert the published Docker image directly into a SIF file:

```bash
apptainer build petfit_latest.sif docker://mathesong/petfit:latest
```

### Build from the definition file

If you need to customise the build (e.g. work offline or modify dependencies):

```bash
apptainer build petfit_latest.sif apptainer/petfit.def
```

### Prerequisites

- Apptainer installed on your system (or Singularity, which uses the same commands)
- `sudo` access for building (not required for running)
- Internet access during the build

See [Apptainer usage](containers/apptainer.md) for full details, including HPC integration with SLURM, PBS, and LSF.
