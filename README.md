# PETFit: A BIDS App for PET Kinetic Modelling

PETFit is a [BIDS App](https://bids-apps.neuroimaging.io/) for fitting kinetic models to PET time activity curve (TAC) data. It runs a configurable, step-by-step pipeline — each step accompanied by detailed HTML reports for quality control — and delegates the kinetic model fitting to [kinfitr](https://github.com/mathesong/kinfitr).

**Full documentation: https://petfit.readthedocs.io**

This README is only a brief overview. For the complete installation guide, tutorials, command reference, container/HPC usage, supported models, and troubleshooting, see the documentation site.

**Note:** PETFit is currently in active development, and there may be bugs. Please report them on the [GitHub issues page](https://github.com/mathesong/petfit/issues) — they are extremely valuable for making the pipeline robust for all datasets.

## Overview

PETFit can be used in two ways:

- **Interactive mode** — graphical web apps to configure analyses step-by-step, run individual steps, and save configuration files for reproducible processing.
- **Automatic mode** — run the full pipeline non-interactively from a saved configuration file, locally or on a server/HPC.

It provides three apps for interactive usage:

- **Region Definition** — combines regional TACs from BIDS PET preprocessing derivatives.
- **Modelling with Plasma Input** — invasive models requiring a blood input function (1TCM, 2TCM, 2TCM_irr, Logan, MA1, Patlak).
- **Modelling with Reference Tissue** — non-invasive models using a reference region (SRTM, SRTM2, refLogan, MRTM1, MRTM2, refPatlak).

## Installation

PETFit can be run as a container (Docker / Apptainer), or as an R package.

**Docker:**

```bash
docker pull mathesong/petfit:latest
```

The easiest way to drive the Docker image is the [`petfit-docker`](https://pypi.org/project/petfit-docker/) command-line wrapper. It turns a simple BIDS-App-style command into the matching `docker run` invocation, mapping your directories into the container for you:

```bash
pip install petfit-docker
petfit-docker --help   # see all options
```

**R package:**

```r
# install.packages("remotes")
remotes::install_github("mathesong/petfit")
```

See the [installation guide](https://petfit.readthedocs.io/en/latest/installation.html) for full details, including Apptainer/HPC usage.

## Quick start

A PETFit workflow has two stages: define regions once for the dataset, then run one or more modelling analyses. Launch each app interactively with the `petfit-docker` wrapper, then open `http://localhost:3838` in your browser.

**Region definition:**

```bash
petfit-docker /path/to/bids /path/to/derivatives participant \
  --app regiondef \
  --cores 1
```

**Modelling with plasma input:**

```bash
petfit-docker /path/to/bids /path/to/derivatives participant \
  --app modelling_plasma \
  --blood-dir /path/to/blood \
  --cores 1
```

**Modelling with reference tissue:**

```bash
petfit-docker /path/to/bids /path/to/derivatives participant \
  --app modelling_ref \
  --cores 1
```

For the equivalent raw `docker run` commands (useful if you ever hit an issue with the wrapper), see the [Docker usage guide](https://petfit.readthedocs.io/en/latest/containers/docker.html).

For the full walkthrough — automatic processing, Apptainer/HPC, configuration, outputs, and troubleshooting — see the [Quick start](https://petfit.readthedocs.io/en/latest/quickstart.html) and [Usage](https://petfit.readthedocs.io/en/latest/usage/index.html) guides.

## Citation

If you use PETFit in your research, please cite *kinfitr* for now:

An introduction to the package:

> Matheson, G. J. (2019). *Kinfitr: Reproducible PET Pharmacokinetic Modelling in R*. bioRxiv: 755751. https://doi.org/10.1101/755751

A validation study compared against commercial software:

> Tjerkaski, J., Cervenka, S., Farde, L., & Matheson, G. J. (2020). *Kinfitr – an open source tool for reproducible PET modelling: Validation and evaluation of test-retest reliability*. EJNMMI Res 10, 77 (2020). https://doi.org/10.1186/s13550-020-00664-8

## Contributing

Contributions are welcome! Please report issues or submit pull requests on GitHub at https://github.com/mathesong/petfit.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

