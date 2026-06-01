# Modelling with reference tissue

The reference tissue modelling app configures and runs non-invasive kinetic models that use a reference brain region instead of arterial blood data. This is the appropriate choice when blood data is not available.

## Pipeline steps

The reference tissue pipeline runs these steps in order:

### 1. Data definition

Same as the [plasma input pipeline](modelling-plasma.md#1-data-definition). Subsets the combined TACs by BIDS entities and creates individual TAC files.

```{important}
The reference region must be included in your region subsetting. For example, if your reference region is "Cerebellum", then the Regions field must include "Cerebellum".
```

### 2. Weights

Same as the [plasma input pipeline](modelling-plasma.md#2-weights). Calculates frame-by-frame weights for model fitting.

### 3. Reference TAC

Configures how the reference region TAC is handled before being used for model fitting.

**Reference TAC methods:**

- **Raw reference TAC** (default) — Uses the reference region TAC without modification.
- **Feng+1TC reference model** — Fits the reference TAC with a pharmacokinetic model to reduce noise.
- **Spline model** — Fits the reference TAC with a smooth spline function.

**Noise approximation** (available with Raw reference TAC only):

When enabled, compares the noise level in the reference region to target regions using a spline-based estimate. This helps identify whether the reference region is particularly noisy relative to targets — useful for quality control.

**Reference TAC weighting:**

- Same weights as the target TAC (default)
- Independent weighting method
- Custom formula

### 4. Model fitting

Fits non-invasive kinetic models to each PET measurement and region. You can configure up to three models simultaneously.

**Available models:** SRTM, SRTM2, refLogan, MRTM1, MRTM2, refPatlak. See [Supported models](../models.md) for details.

Models that require a **k2prime** value (SRTM2, MRTM2, refLogan) can obtain it from:

- A fixed value you provide
- The fitted results of another model in the same analysis (e.g. MRTM1's k2a estimate)
- An ancillary analysis folder (when using the ancillary analysis workflow)

## Running the pipeline

`````{tab-set}

````{tab-item} Docker
```bash
# Interactive
docker run -it --rm \
  -v /path/to/your/bids:/data/bids_dir:ro \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  -p 3838:3838 \
  mathesong/petfit:latest \
  --func modelling_ref
# Then open http://localhost:3838

# Automatic — full pipeline
docker run --rm \
  -v /path/to/your/bids:/data/bids_dir:ro \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  mathesong/petfit:latest \
  --func modelling_ref \
  --mode automatic

# Automatic — single step
docker run --rm \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  mathesong/petfit:latest \
  --func modelling_ref \
  --mode automatic \
  --step model1
```
````

````{tab-item} Apptainer
```bash
# Interactive
apptainer run \
  --bind /path/to/your/bids:/data/bids_dir \
  --bind /path/to/your/derivatives:/data/derivatives_dir \
  petfit_latest.sif \
  --func modelling_ref
# Then open http://localhost:3838

# Automatic — full pipeline
apptainer run \
  --bind /path/to/your/bids:/data/bids_dir \
  --bind /path/to/your/derivatives:/data/derivatives_dir \
  petfit_latest.sif \
  --func modelling_ref \
  --mode automatic

# Automatic — single step
apptainer run \
  --bind /path/to/your/derivatives:/data/derivatives_dir \
  petfit_latest.sif \
  --func modelling_ref \
  --mode automatic \
  --step model1
```
````

````{tab-item} R
```r
library(petfit)

# Interactive
petfit_interactive(
  app = "modelling_ref",
  derivatives_dir = "/path/to/derivatives"
)

# Automatic — full pipeline
petfit_modelling_auto(
  derivatives_dir = "/path/to/derivatives"
)

# Automatic — single step
petfit_modelling_auto(
  derivatives_dir = "/path/to/derivatives",
  step = "model1"
)
```
````

`````

## Interactive exploration

Same as the [plasma input app](modelling-plasma.md#interactive-exploration). The Interactive tab lets you manually load TAC data and test model fits on individual PET measurements and regions.

## State persistence

Same as the [plasma input app](modelling-plasma.md#state-persistence). All configuration is saved to and restored from `desc-petfitoptions_config.json`.
