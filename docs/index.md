# PETFit: A BIDS App for PET Kinetic Modelling

PETFit is a [BIDS App](https://bids-apps.neuroimaging.io/) for fitting kinetic models to PET time activity curve (TAC) data. It takes preprocessed PET data in [BIDS](https://bids-specification.readthedocs.io/) format and runs a configurable kinetic modelling pipeline, producing parameter estimates and detailed HTML reports for quality control.

```{note}
PETFit is currently in active development (v0.1.3). If you encounter any bugs, please report them on the [GitHub issues page](https://github.com/mathesong/petfit/issues) — they are extremely valuable for making this pipeline robust.
```

## How it works

PETFit can be used in two ways:

- **Interactive mode**: Use graphical web applications to configure your analysis step-by-step, preview results, and generate configuration files.
- **Automatic mode**: Run the full pipeline non-interactively using a pre-defined configuration file. This is ideal for batch processing and HPC environments.

The typical workflow has two stages:

1. **Region definition** — Combine individual brain regions from PET preprocessing derivatives into analysis-ready TACs.
2. **Kinetic modelling** — Configure and run kinetic models on the combined TACs, with steps for data subsetting, weights calculation, delay fitting (plasma input) or reference TAC setup (reference tissue), and model fitting.

## Three apps

PETFit provides three separate Shiny web applications:

- **Region Definition App** — Creates combined regional TACs from PET preprocessing derivative data.
- **Modelling App with Plasma Input** — Configures invasive kinetic models (1TCM, 2TCM, Logan, MA1, Patlak) that require blood input data.
- **Modelling App with Reference Tissue** — Configures non-invasive kinetic models (SRTM, refLogan, MRTM1, MRTM2) that use a reference region.

## Getting started

::::{grid} 2
:gutter: 3

:::{grid-item-card} Installation
:link: installation
:link-type: doc

Install the R package, pull a Docker image, or build a Singularity container.
:::

:::{grid-item-card} Quick start
:link: quickstart
:link-type: doc

A minimal end-to-end example to get you up and running.
:::

:::{grid-item-card} Supported models
:link: models
:link-type: doc

Full reference for all invasive and non-invasive kinetic models.
:::

:::{grid-item-card} Folder structures
:link: usage/folder-structure
:link-type: doc

How PETFit organises region definitions, analyses, and ancillary workflows.
:::

:::{grid-item-card} Outputs
:link: outputs
:link-type: doc

What files PETFit produces and how they are organised.
:::

::::


```{toctree}
:maxdepth: 2
:caption: Getting Started

installation
quickstart
```

```{toctree}
:maxdepth: 2
:caption: User Guide

usage/index
containers/index
outputs
models
```

```{toctree}
:maxdepth: 2
:caption: Reference

troubleshooting
api
configuration
citation
changes
license
```

```{toctree}
:maxdepth: 2
:caption: Development

contributing
```
