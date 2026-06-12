# Quick start

PETFit analyses have two steps: **region definition** (once per dataset) and **kinetic modelling** (once per analysis). Both can be run interactively (GUI) or automatically (command line).

You will need a BIDS dataset with PET preprocessing derivatives (e.g. from [PETPrep](https://petprep.readthedocs.io/)).

The Docker examples below use the [`petfit-docker`](https://pypi.org/project/petfit-docker/) wrapper (`pip install petfit-docker`), which builds the `docker run` command for you. Run `petfit-docker --help` to see all options, and see the [Docker guide](containers/docker.md) for the equivalent raw `docker run` commands.

## Step 1: Define regions

Region definition combines individual brain regions from your preprocessing derivatives into analysis-ready TACs. This produces a shared `desc-combinedregions_tacs.tsv` file used by all subsequent analyses.

`````{tab-set}

````{tab-item} Docker
```bash
# Interactive
petfit-docker /path/to/bids /path/to/derivatives participant \
  --app regiondef \
  --cores 1
# Then open http://localhost:3838

# Automatic
petfit-docker /path/to/bids /path/to/derivatives participant \
  --app regiondef --automatic \
  --cores 1
```
````

````{tab-item} Apptainer
```bash
# Interactive
apptainer run --cleanenv \
  -B /path/to/bids:/data/bids_dir:ro \
  -B /path/to/derivatives:/data/derivatives_dir:rw \
  -B /tmp:/tmp \
  petfit_latest.sif \
  --func regiondef
# Then open http://localhost:3838

# Automatic
apptainer run --cleanenv \
  -B /path/to/bids:/data/bids_dir:ro \
  -B /path/to/derivatives:/data/derivatives_dir:rw \
  -B /tmp:/tmp \
  petfit_latest.sif \
  --func regiondef --mode automatic
```
````

````{tab-item} R
```r
library(petfit)

# Interactive — opens the region definition app in your browser
petfit_interactive(
  app = "regiondef",
  bids_dir = "/path/to/bids",
  derivatives_dir = "/path/to/derivatives"
)

# Automatic — runs non-interactively using an existing petfit_regions.tsv
petfit_auto(
  app = "regiondef",
  bids_dir = "/path/to/bids",
  derivatives_dir = "/path/to/derivatives"
)
```
````

`````

## Step 2: Run kinetic modelling

Choose the modelling pipeline that matches your data:

- **`modelling_plasma`** — for invasive models (1TCM, 2TCM, Logan, MA1, Patlak) that require arterial blood input data.
- **`modelling_ref`** — for non-invasive models (SRTM, refLogan, MRTM1, MRTM2) that use a reference brain region.

The interactive app guides you through configuration and generates a JSON config file. In automatic mode, this config file drives the pipeline without any user interaction.

### Plasma input models

`````{tab-set}

````{tab-item} Docker
```bash
# Interactive
petfit-docker /path/to/bids /path/to/derivatives participant \
  --app modelling_plasma \
  --blood-dir /path/to/blood \
  --cores 1
# Then open http://localhost:3838

# Automatic
petfit-docker /path/to/bids /path/to/derivatives participant \
  --app modelling_plasma \
  --blood-dir /path/to/blood \
  --automatic \
  --cores 1
```
````

````{tab-item} Apptainer
```bash
# Interactive
apptainer run --cleanenv \
  -B /path/to/bids:/data/bids_dir:ro \
  -B /path/to/derivatives:/data/derivatives_dir:rw \
  -B /path/to/blood:/data/blood_dir:ro \
  -B /tmp:/tmp \
  petfit_latest.sif \
  --func modelling_plasma
# Then open http://localhost:3838

# Automatic
apptainer run --cleanenv \
  -B /path/to/bids:/data/bids_dir:ro \
  -B /path/to/derivatives:/data/derivatives_dir:rw \
  -B /path/to/blood:/data/blood_dir:ro \
  -B /tmp:/tmp \
  petfit_latest.sif \
  --func modelling_plasma --mode automatic
```
````

````{tab-item} R
```r
# Interactive
petfit_interactive(
  app = "modelling_plasma",
  bids_dir = "/path/to/bids",
  derivatives_dir = "/path/to/derivatives",
  blood_dir = "/path/to/blood"
)

# Automatic (full pipeline)
petfit_auto(
  app = "modelling_plasma",
  derivatives_dir = "/path/to/derivatives",
  blood_dir = "/path/to/blood"
)

# Automatic (single step)
petfit_auto(
  app = "modelling_plasma",
  derivatives_dir = "/path/to/derivatives",
  blood_dir = "/path/to/blood",
  step = "weights"
)
```
````

`````

### Reference tissue models

`````{tab-set}

````{tab-item} Docker
```bash
# Interactive
petfit-docker /path/to/bids /path/to/derivatives participant \
  --app modelling_ref \
  --cores 1
# Then open http://localhost:3838

# Automatic
petfit-docker /path/to/bids /path/to/derivatives participant \
  --app modelling_ref --automatic \
  --cores 1
```
````

````{tab-item} Apptainer
```bash
# Interactive
apptainer run --cleanenv \
  -B /path/to/bids:/data/bids_dir:ro \
  -B /path/to/derivatives:/data/derivatives_dir:rw \
  -B /tmp:/tmp \
  petfit_latest.sif \
  --func modelling_ref
# Then open http://localhost:3838

# Automatic
apptainer run --cleanenv \
  -B /path/to/bids:/data/bids_dir:ro \
  -B /path/to/derivatives:/data/derivatives_dir:rw \
  -B /tmp:/tmp \
  petfit_latest.sif \
  --func modelling_ref --mode automatic
```
````

````{tab-item} R
```r
# Interactive
petfit_interactive(
  app = "modelling_ref",
  bids_dir = "/path/to/bids",
  derivatives_dir = "/path/to/derivatives"
)

# Automatic
petfit_auto(
  app = "modelling_ref",
  derivatives_dir = "/path/to/derivatives"
)
```
````

`````

## Step 3: Review reports

PETFit generates interactive HTML reports for every analysis step in `derivatives/petfit/<analysis_folder>/reports/`. Open them in your browser to review data quality, model fits, and parameter estimates.

## Key arguments

These arguments are shared across `petfit_interactive()`, `petfit_auto()`, and the container CLI:

| Argument | Purpose | Default |
|----------|---------|---------|
| `bids_dir` | Path to BIDS dataset (raw data, participants.tsv) | — |
| `derivatives_dir` | Path to derivatives directory (PETFit reads and writes here) | `bids_dir/derivatives` |
| `blood_dir` | Path to blood data (plasma input only) | — |
| `analysis_foldername` | Name for this analysis subfolder | `"Primary_Analysis"` |
| `cores` | Number of cores for parallel processing | `1` |
| `ancillary_analysis_folder` | Sibling folder to inherit delay/k2prime from | — |

See the [API reference](api.md) for full details, or the [usage guide](usage/index.md) for in-depth documentation of each app.
