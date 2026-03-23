# Installation

PETFit can be installed and run in three ways. Docker is the recommended approach for most users.

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

## Singularity / Apptainer

Singularity (now called [Apptainer](https://apptainer.org/)) is the standard container runtime on HPC clusters. PETFit provides build scripts and run wrappers in the `singularity/` directory.

### Build from the Docker image

```bash
cd singularity/
./build.sh
```

This creates a `petfit_latest.sif` file. You can customise the build:

```bash
# Custom name and tag
./build.sh --name petfit --tag v1.0

# Build as writable sandbox for development
./build.sh --sandbox
```

### Prerequisites

- Singularity or Apptainer installed on your system
- `sudo` access for building (not required for running)
- Internet access during the build

See [Singularity usage](containers/singularity.md) for full details, including HPC integration with SLURM, PBS, and LSF.

## R package (for development)

If you need to run PETFit outside a container — for example, during development or debugging — you can install the R package directly.

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
