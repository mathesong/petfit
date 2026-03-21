# Modelling with plasma input

The plasma input modelling app configures and runs invasive kinetic models that require an arterial blood input function. This is used when you have blood data (either raw `_blood.tsv` files or processed `_inputfunction.tsv` files).

## Launching the app

`````{tab-set}

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
petfit_modelling_auto(
  derivatives_dir = "/path/to/derivatives",
  blood_dir = "/path/to/blood"
)

# Automatic — single step
petfit_modelling_auto(
  derivatives_dir = "/path/to/derivatives",
  blood_dir = "/path/to/blood",
  step = "weights"
)

# Automatic — custom analysis folder
petfit_modelling_auto(
  analysis_foldername = "Baseline_only",
  derivatives_dir = "/path/to/derivatives",
  blood_dir = "/path/to/blood"
)
```
````

````{tab-item} Docker
```bash
# Interactive
docker run -it --rm \
  -v /path/to/your/bids:/data/bids_dir:ro \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  -v /path/to/your/blood:/data/blood_dir:ro \
  -p 3838:3838 \
  mathesong/petfit:latest \
  --func modelling_plasma

# Automatic — full pipeline
docker run --rm \
  -v /path/to/your/bids:/data/bids_dir:ro \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  -v /path/to/your/blood:/data/blood_dir:ro \
  mathesong/petfit:latest \
  --func modelling_plasma \
  --mode automatic

# Automatic — single step
docker run --rm \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  -v /path/to/your/blood:/data/blood_dir:ro \
  mathesong/petfit:latest \
  --func modelling_plasma \
  --mode automatic \
  --step weights
```
````

`````

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
2. **1TCM from single representative TAC (quick)** — Fits a 1TCM to one region.
3. **2TCM from single representative TAC (less quick)** — Fits a 2TCM to one region.
4. **1TCM median from multiple regions (recommended)** — Fits 1TCM to multiple regions and takes the median delay. This is the default.
5. **2TCM median from multiple regions (very slow)** — Most comprehensive approach.

**Blood input time shift controls:**

- Lower limit (default: -0.5 min) and upper limit (default: 0.5 min) define the search range for the delay parameter.

### 4. Model fitting

Fits kinetic models to each PET measurement and region. You can configure up to three models simultaneously for comparison.

**Available models:** 1TCM, 2TCM, 2TCM_irr, Logan, MA1, Patlak. See [Supported models](../models.md) for details.

Each model has configurable:
- Start values, lower bounds, and upper bounds for all parameters
- Whether to fit vB (blood volume fraction)
- Whether to use weights

## Interactive exploration

The Interactive tab lets you manually load and visualise individual TAC data. This is useful for validating model configurations before running the full pipeline:

1. Click "Scan Analysis Folder" to discover available PET measurements and regions.
2. Select a PET measurement, region, and model.
3. Click "Load Data" to view the TAC.
4. Click "Fit Model" to test the model fit.

## State persistence

The app automatically saves your configuration to a JSON file (`desc-petfitoptions_config.json`) in the analysis folder. When you reopen the app, all settings are restored to their previous state.
