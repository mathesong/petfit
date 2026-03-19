# Quick start

This guide walks through a minimal PETFit analysis from start to finish. You will need a BIDS dataset with PET preprocessing derivatives (e.g. from [PETPrep](https://petprep.readthedocs.io/)).

## Usage summary

| Mode | R | Docker |
|------|---|--------|
| Interactive — Region Definition | `launch_petfit_apps(bids_dir = "...")` | `docker run -p 3838:3838 ... --func regiondef` |
| Interactive — Plasma Modelling | `launch_petfit_apps(app = "modelling_plasma", ...)` | `docker run -p 3838:3838 ... --func modelling_plasma` |
| Interactive — Reference Modelling | `launch_petfit_apps(app = "modelling_ref", ...)` | `docker run -p 3838:3838 ... --func modelling_ref` |
| Automatic — Region Definition | `petfit_regiondef_auto(derivatives_dir = "...")` | `docker run ... --func regiondef --mode automatic` |
| Automatic — Modelling | `petfit_modelling_auto(derivatives_dir = "...")` | `docker run ... --func modelling_plasma --mode automatic` |

## Step 1: Region definition

Region definition combines individual brain regions from your PET preprocessing derivatives into analysis-ready TACs. You need a `petfit_regions.tsv` file that defines which regions to combine — this can be created interactively or written manually.

`````{tab-set}

````{tab-item} R
```r
library(petfit)

# Interactive: opens the region definition app in your browser
launch_petfit_apps(
  app = "regiondef",
  derivatives_dir = "/path/to/derivatives"
)

# Automatic: runs non-interactively using an existing petfit_regions.tsv
petfit_regiondef_auto(
  derivatives_dir = "/path/to/derivatives"
)
```
````

````{tab-item} Docker
```bash
# Interactive
docker run -it --rm \
  -v /path/to/your/bids:/data/bids_dir:ro \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  -p 3838:3838 \
  mathesong/petfit:latest \
  --func regiondef
# Then open http://localhost:3838

# Automatic
docker run --rm \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  mathesong/petfit:latest \
  --func regiondef \
  --mode automatic
```
````

`````

This produces a `desc-combinedregions_tacs.tsv` file in the `derivatives/petfit/` directory.

## Step 2: Kinetic modelling

Once you have combined TACs, run the modelling pipeline. Choose either plasma input or reference tissue depending on your data.

`````{tab-set}

````{tab-item} R (plasma input)
```r
# Interactive
launch_petfit_apps(
  app = "modelling_plasma",
  bids_dir = "/path/to/your/bids/dataset",
  derivatives_dir = "/path/to/derivatives",
  blood_dir = "/path/to/blood/data"
)

# Automatic
petfit_modelling_auto(
  derivatives_dir = "/path/to/derivatives",
  blood_dir = "/path/to/blood"
)
```
````

````{tab-item} R (reference tissue)
```r
# Interactive
launch_petfit_apps(
  app = "modelling_ref",
  derivatives_dir = "/path/to/derivatives"
)

# Automatic
petfit_modelling_auto(
  derivatives_dir = "/path/to/derivatives"
)
```
````

````{tab-item} Docker (plasma input)
```bash
# Interactive
docker run -it --rm \
  -v /path/to/your/bids:/data/bids_dir:ro \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  -v /path/to/your/blood:/data/blood_dir:ro \
  -p 3838:3838 \
  mathesong/petfit:latest \
  --func modelling_plasma
# Then open http://localhost:3838

# Automatic
docker run --rm \
  -v /path/to/your/bids:/data/bids_dir:ro \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  -v /path/to/your/blood:/data/blood_dir:ro \
  mathesong/petfit:latest \
  --func modelling_plasma \
  --mode automatic
```
````

````{tab-item} Docker (reference tissue)
```bash
# Interactive
docker run -it --rm \
  -v /path/to/your/bids:/data/bids_dir:ro \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  -p 3838:3838 \
  mathesong/petfit:latest \
  --func modelling_ref
# Then open http://localhost:3838

# Automatic
docker run --rm \
  -v /path/to/your/bids:/data/bids_dir:ro \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  mathesong/petfit:latest \
  --func modelling_ref \
  --mode automatic
```
````

`````

## Step 3: Review reports

PETFit generates HTML reports for every analysis step. You will find them in:

```
derivatives/petfit/<analysis_folder>/reports/
```

Open these in your browser to review data quality, model fits, and parameter estimates. Each report includes interactive plots and detailed diagnostics.

## What's next?

- [Usage guide](usage/index.md) — Detailed documentation for each app and pipeline step
- [Supported models](models.md) — Full reference for all kinetic models
- [Outputs](outputs.md) — Description of all output files and directory structure
- [Configuration files](configuration.md) — JSON configuration file reference
