# Quick start

PETFit analyses have two steps: **region definition** (once per dataset) and **kinetic modelling** (once per analysis). Both can be run interactively (GUI) or automatically (command line).

You will need a BIDS dataset with PET preprocessing derivatives (e.g. from [PETPrep](https://petprep.readthedocs.io/)).

## Step 1: Define regions

Region definition combines individual brain regions from your preprocessing derivatives into analysis-ready TACs. This produces a shared `desc-combinedregions_tacs.tsv` file used by all subsequent analyses.

`````{tab-set}

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
petfit_regiondef_auto(
  bids_dir = "/path/to/bids",
  derivatives_dir = "/path/to/derivatives"
)
```
````

````{tab-item} Docker
```bash
# Interactive
docker run -it --rm \
  -v /path/to/bids:/data/bids_dir:ro \
  -v /path/to/derivatives:/data/derivatives_dir:rw \
  -p 3838:3838 \
  mathesong/petfit:latest \
  --func regiondef
# Then open http://localhost:3838

# Automatic
docker run --rm \
  -v /path/to/bids:/data/bids_dir:ro \
  -v /path/to/derivatives:/data/derivatives_dir:rw \
  mathesong/petfit:latest \
  --func regiondef --mode automatic
```
````

````{tab-item} Apptainer
```bash
# Interactive (using wrapper script)
cd singularity/
./run-interactive.sh --func regiondef \
  --bids-dir /path/to/bids

# Automatic (using wrapper script)
./run-automatic.sh --func regiondef \
  --derivatives-dir /path/to/derivatives

# Or directly with apptainer/singularity
apptainer run \
  --bind /path/to/bids:/data/bids_dir \
  --bind /path/to/derivatives:/data/derivatives_dir \
  petfit_latest.sif \
  --func regiondef --mode automatic
```
````

`````

## Step 2: Run kinetic modelling

Choose the modelling pipeline that matches your data:

- **`modelling_plasma`** — for invasive models (1TCM, 2TCM, Logan, MA1, Patlak) that require arterial blood input data.
- **`modelling_ref`** — for non-invasive models (SRTM, refLogan, MRTM1, MRTM2) that use a reference brain region.

The interactive app guides you through configuration and generates a JSON config file. In automatic mode, this config file drives the pipeline without any user interaction.

`````{tab-set}

````{tab-item} R (plasma input)
```r
# Interactive
petfit_interactive(
  app = "modelling_plasma",
  bids_dir = "/path/to/bids",
  derivatives_dir = "/path/to/derivatives",
  blood_dir = "/path/to/blood"
)

# Automatic (full pipeline)
petfit_modelling_auto(
  derivatives_dir = "/path/to/derivatives",
  blood_dir = "/path/to/blood"
)

# Automatic (single step)
petfit_modelling_auto(
  derivatives_dir = "/path/to/derivatives",
  blood_dir = "/path/to/blood",
  step = "weights"
)
```
````

````{tab-item} R (reference tissue)
```r
# Interactive
petfit_interactive(
  app = "modelling_ref",
  bids_dir = "/path/to/bids",
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
  -v /path/to/bids:/data/bids_dir:ro \
  -v /path/to/derivatives:/data/derivatives_dir:rw \
  -v /path/to/blood:/data/blood_dir:ro \
  -p 3838:3838 \
  mathesong/petfit:latest \
  --func modelling_plasma

# Automatic
docker run --rm \
  -v /path/to/bids:/data/bids_dir:ro \
  -v /path/to/derivatives:/data/derivatives_dir:rw \
  -v /path/to/blood:/data/blood_dir:ro \
  mathesong/petfit:latest \
  --func modelling_plasma --mode automatic
```
````

````{tab-item} Docker (reference tissue)
```bash
# Interactive
docker run -it --rm \
  -v /path/to/bids:/data/bids_dir:ro \
  -v /path/to/derivatives:/data/derivatives_dir:rw \
  -p 3838:3838 \
  mathesong/petfit:latest \
  --func modelling_ref

# Automatic
docker run --rm \
  -v /path/to/bids:/data/bids_dir:ro \
  -v /path/to/derivatives:/data/derivatives_dir:rw \
  mathesong/petfit:latest \
  --func modelling_ref --mode automatic
```
````

````{tab-item} Apptainer (plasma input)
```bash
# Interactive
cd singularity/
./run-interactive.sh --func modelling_plasma \
  --bids-dir /path/to/bids \
  --blood-dir /path/to/blood

# Automatic
./run-automatic.sh --func modelling_plasma \
  --derivatives-dir /path/to/derivatives \
  --blood-dir /path/to/blood
```
````

````{tab-item} Apptainer (reference tissue)
```bash
# Interactive
cd singularity/
./run-interactive.sh --func modelling_ref \
  --bids-dir /path/to/bids

# Automatic
./run-automatic.sh --func modelling_ref \
  --derivatives-dir /path/to/derivatives
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
