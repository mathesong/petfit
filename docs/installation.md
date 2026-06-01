# Installation

PETFit can be installed and run in three ways. Docker and Apptainer are the recommended approaches for most users; the R package is intended mainly for development.

## Docker

Docker is the recommended approach for most users on their local computers. It bundles all dependencies and avoids package installation issues.

### Pull the pre-built image

```bash
docker pull mathesong/petfit:latest
```

See [Docker usage](containers/docker.md) for more details on running the container.

## Apptainer

[Apptainer](https://apptainer.org/) (formerly Singularity) is the standard container runtime on HPC clusters. PETFit's Apptainer definition file lives in the `apptainer/` directory.

### Build from the Docker image

The fastest path is to convert the published Docker image directly into a SIF file:

```bash
apptainer build petfit_latest.sif docker://mathesong/petfit:latest
```

### Prerequisites

- Apptainer installed on your system (or Singularity, which uses the same commands)
- `sudo` access for building (not required for running)
- Internet access during the build

See [Apptainer usage](containers/apptainer.md) for more details.

## R package (for development)

If you need to run PETFit outside a container — for example, during development or debugging, or if you just like using R — you can install the R package directly.

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

