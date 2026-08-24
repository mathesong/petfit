# Modelling with plasma input

The plasma input modelling app configures and runs invasive kinetic models that require an arterial blood input function. This is used when you have blood data (either raw `_blood.tsv` files or processed `_inputfunction.tsv` files).

## Pipeline steps

The plasma input pipeline runs these steps in order:

### 1. Data definition

Subsets the combined TACs file by any combination of BIDS entities:

- **sub** — Subject identifiers (semicolon-separated, e.g. `01;02;03`)
- **ses** — Session
- **trc** — Tracer
- **rec** — Reconstruction
- **task** — Task
- **run** — Run
- **Regions** — Brain regions to include

This creates individual TAC files for each PET measurement in the analysis folder.

### 2. Weights

Calculates frame-by-frame weights for the kinetic model fits. The weights account for differences in noise across frames (e.g. later frames have lower counts and higher noise).

**Region type options:**

- **Mean of all combined regions** — Uses the average TAC across all regions in the analysis.
- **Mean of external segmentation** — Uses the pre-calculated `seg_meanTAC` from the combined TACs file. This is the recommended approach.
- **Single region** — Uses a specific named region.

**Weighting methods** are based on established PET weighting approaches. You can also provide a custom formula.

**Additional settings:**

- **Radioisotope** — Used for decay correction (C11, F18, O15, or custom half-life).
- **Minimum weight** — Floor value to prevent any frame from having zero weight (default: 0.25).

### 3. Delay fitting

Estimates the temporal delay between the blood input function and the tissue TACs. This is important because blood sampling and PET scanning may not be perfectly synchronised.

**Delay estimation approaches** (ordered by speed):

1. **Set to zero** — Skip delay estimation entirely.
2. **1TCM from single representative TAC (quick)** — Fits a 1TCM to one representative or high-quality region.
3. **2TCM from single representative TAC (less quick)** — Fits a 2TCM to one representative or high-quality region.
4. **1TCM median from multiple regions (recommended)** — Fits 1TCM to multiple regions and takes the median delay. This is the default.
5. **2TCM median from multiple regions (very slow)** — Fits 2TCM to multiple regions and takes the median delay.
6. **Nested 1TCM shared delay from multiple regions (slow)** — Fits 1TCM to all the chosen regions *jointly*, estimating one delay shared across them.
7. **Nested 2TCM shared delay from multiple regions (very slow)** — The same, with a 2TCM.

The delay is a property of the measurement, not of any one region, so the nested methods estimate a single one directly rather than summarising independent per-region estimates. Like the other [nested models](../models.md#nested-models), they need at least two regions per measurement, and they take a fixed `vB` — the "Fit vB parameter" option is not offered for them. They always run with a single starting point regardless of the multistart setting: the nested fit refits every region at each evaluation of the delay, and the delay search itself already covers the range.

**Regions for multiple regions analysis:**

The multiple-regions and nested methods use every region in the analysis by default. The optional regions field restricts them to the regions you name, separated by `;`, with a leading `-` to exclude instead of include — the same syntax as the subsetting fields.


**Blood input time shift controls:**

- Lower limit (default: -0.5 min) and upper limit (default: 0.5 min) define the search range for the delay parameter.

### 4. Model fitting

Fits kinetic models to each PET measurement and region. You can configure up to three models simultaneously for comparison.

**Available models:** 1TCM, 2TCM, nested2TCM, 2TCM_irr, Logan, MA1, Patlak. See [Supported models](../models.md) for details.

Each model has configurable:
- Start values, lower bounds, and upper bounds for all parameters
- Whether to fit vB (blood volume fraction)
- Whether to use weights

**nested2TCM** is configured differently from the others: it fits all the regions of a measurement together, so its parameters are given in the macro parameterisation (`K1`, `Vnd`, `BPp`, `k4`), you choose which of `Vnd` and `k4` are shared within each measurement, `vB` is a fixed value rather than a fitted one, and a region weighting setting controls how much each region pulls on the shared estimates. See [Nested models](../models.md#nested-models).

## Running the pipeline

`````{tab-set}

````{tab-item} Docker
```bash
# Interactive
petfit-docker /path/to/your/bids /path/to/your/derivatives participant \
  --app modelling_plasma \
  --blood-dir /path/to/your/blood
# Then open http://localhost:3838

# Automatic — full pipeline
petfit-docker /path/to/your/bids /path/to/your/derivatives participant \
  --app modelling_plasma \
  --blood-dir /path/to/your/blood \
  --automatic

# Automatic — custom analysis folder
petfit-docker /path/to/your/bids /path/to/your/derivatives participant \
  --app modelling_plasma \
  --blood-dir /path/to/your/blood \
  --automatic \
  --analysis-foldername Baseline_only

# Automatic — single step
petfit-docker /path/to/your/bids /path/to/your/derivatives participant \
  --app modelling_plasma \
  --blood-dir /path/to/your/blood \
  --automatic \
  --step weights
```

Install the wrapper with `pip install petfit-docker`; see the
[Docker guide](../containers/docker.md) for the equivalent raw `docker run` commands.
````

````{tab-item} Apptainer
```bash
# Interactive
apptainer run \
  --bind /path/to/your/bids:/data/bids_dir \
  --bind /path/to/your/derivatives:/data/derivatives_dir \
  --bind /path/to/your/blood:/data/blood_dir \
  petfit_latest.sif \
  --func modelling_plasma
# Then open http://localhost:3838

# Automatic — full pipeline
apptainer run \
  --bind /path/to/your/bids:/data/bids_dir \
  --bind /path/to/your/derivatives:/data/derivatives_dir \
  --bind /path/to/your/blood:/data/blood_dir \
  petfit_latest.sif \
  --func modelling_plasma \
  --mode automatic

# Automatic — custom analysis folder
apptainer run \
  --bind /path/to/your/derivatives:/data/derivatives_dir \
  --bind /path/to/your/blood:/data/blood_dir \
  petfit_latest.sif \
  --func modelling_plasma \
  --mode automatic \
  --analysis_foldername Baseline_only

# Automatic — single step
apptainer run \
  --bind /path/to/your/derivatives:/data/derivatives_dir \
  --bind /path/to/your/blood:/data/blood_dir \
  petfit_latest.sif \
  --func modelling_plasma \
  --mode automatic \
  --step weights
```
````

````{tab-item} R
```r
library(petfit)

# Interactive
petfit_interactive(
  app = "modelling_plasma",
  bids_dir = "/path/to/your/bids/dataset",
  derivatives_dir = "/path/to/derivatives",
  blood_dir = "/path/to/blood/data"
)

# Automatic — full pipeline
petfit_auto(
  app = "modelling_plasma",
  derivatives_dir = "/path/to/derivatives",
  blood_dir = "/path/to/blood"
)

# Automatic — custom analysis folder
petfit_auto(
  app = "modelling_plasma",
  analysis_foldername = "Baseline_only",
  derivatives_dir = "/path/to/derivatives",
  blood_dir = "/path/to/blood"
)

# Automatic — single step
petfit_auto(
  app = "modelling_plasma",
  derivatives_dir = "/path/to/derivatives",
  blood_dir = "/path/to/blood",
  step = "weights"
)
```
````

`````

## Interactive exploration

*In progress*

The Interactive tab lets you manually load and visualise individual TAC data. This is useful for validating model configurations before running the full pipeline:

1. Click "Scan Analysis Folder" to discover available PET measurements and regions.
2. Select a PET measurement, region, and model. Nested models are not available here — they fit all regions together, which is not what this tab does.
3. Click "Load Data" to view the TAC.
4. Click "Fit Model" to test the model fit.

## State persistence

The app automatically saves your configuration to a JSON file (`desc-petfitoptions_config.json`) in the analysis folder. When you reopen the app, all settings are restored to their previous state.
