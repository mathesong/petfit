# Container usage

PETFit provides container images for both Docker and Singularity/Apptainer. Containers bundle all dependencies, so you do not need to install R or any packages on your system.

## Which container runtime?

| Feature | Docker | Singularity/Apptainer |
|---------|--------|----------------------|
| **Best for** | Desktops, cloud servers | HPC clusters, shared systems |
| **Security model** | Root daemon | User-space, no daemon |
| **Networking** | Port mapping (`-p`) | Direct host network |
| **File permissions** | May need `--user` flag on Linux | Preserves user permissions |
| **Build requirements** | Docker daemon | `sudo` for build only |
| **Container format** | Layered images | Single `.sif` file |

Both use the same command-line arguments and produce identical results.

```{toctree}
:maxdepth: 2

docker
singularity
```
