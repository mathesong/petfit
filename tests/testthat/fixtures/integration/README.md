# Integration Testing Guide

Integration tests verify petfit pipelines end-to-end using real PET data from [OpenNeuro ds004869](https://openneuro.org/datasets/ds004869) (COX-2 PET, 27 subjects, C-11 tracer).

Tests are **disabled by default** and never run during `devtools::test()` or `R CMD check` unless explicitly enabled via environment variables.

---

## Quick Start

### 1. Get the test data

Run the preparation script once (requires [datalad](https://www.datalad.org/)):

```bash
cd tests/testthat/fixtures/integration
bash prepare_testdata.sh
```

This creates `ds004869_testdata.tar.gz` (~50-80 MB). The tarball contains real TSV/JSON files from the dataset with NIfTI files replaced by empty placeholders (petfit only needs the tabular data).

### 2. Run R-native integration tests

```bash
PETFIT_INTEGRATION_TESTS=true Rscript -e "devtools::test(filter = 'integration')"
```

### 3. Run a specific test file

```bash
# Just dataset validation
PETFIT_INTEGRATION_TESTS=true Rscript -e "devtools::test(filter = 'integration-dataset')"

# Just region definition
PETFIT_INTEGRATION_TESTS=true Rscript -e "devtools::test(filter = 'integration-regiondef')"

# Just plasma modelling
PETFIT_INTEGRATION_TESTS=true Rscript -e "devtools::test(filter = 'integration-modelling-plasma')"

# Just reference tissue modelling
PETFIT_INTEGRATION_TESTS=true Rscript -e "devtools::test(filter = 'integration-modelling-ref')"
```

---

## Running Container Tests

### Docker

Requires Docker and the `mathesong/petfit:latest` image:

```bash
# Pull the image (or build from source -- see below)
docker pull mathesong/petfit:latest

# Run Docker integration tests
PETFIT_INTEGRATION_TESTS=true \
PETFIT_DOCKER_TESTS=true \
  Rscript -e "devtools::test(filter = 'integration-docker')"
```

To rebuild the Docker image from source before testing:

```bash
PETFIT_INTEGRATION_TESTS=true \
PETFIT_DOCKER_TESTS=true \
PETFIT_DOCKER_BUILD=true \
  Rscript -e "devtools::test(filter = 'integration-docker')"
```

### Singularity / Apptainer

Requires `singularity` or `apptainer` CLI:

```bash
# With a .sif file
PETFIT_INTEGRATION_TESTS=true \
PETFIT_SINGULARITY_TESTS=true \
PETFIT_SINGULARITY_SIF=/path/to/petfit_latest.sif \
  Rscript -e "devtools::test(filter = 'integration-singularity')"

# Or with the Docker image available (uses docker-daemon:// reference)
PETFIT_INTEGRATION_TESTS=true \
PETFIT_SINGULARITY_TESTS=true \
  Rscript -e "devtools::test(filter = 'integration-singularity')"
```

Script validation tests (no container needed) run with just `PETFIT_INTEGRATION_TESTS=true` and are included in the Singularity test file.

### Run everything

```bash
PETFIT_INTEGRATION_TESTS=true \
PETFIT_DOCKER_TESTS=true \
PETFIT_SINGULARITY_TESTS=true \
  Rscript -e "devtools::test(filter = 'integration')"
```

---

## Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `PETFIT_INTEGRATION_TESTS` | (unset) | Set to `true` to enable integration tests |
| `PETFIT_TESTDATA_PATH` | (unset) | Explicit path to `ds004869_testdata.tar.gz` |
| `PETFIT_INTEGRATION_CACHE` | `tempdir()/petfit_integration` | Persistent cache for extracted data |
| `PETFIT_DOCKER_TESTS` | (unset) | Set to `true` to enable Docker tests |
| `PETFIT_DOCKER_BUILD` | (unset) | Set to `true` to rebuild Docker image before testing |
| `PETFIT_SINGULARITY_TESTS` | (unset) | Set to `true` to enable Singularity tests |
| `PETFIT_SINGULARITY_SIF` | (unset) | Explicit path to `.sif` container file |

### Persistent cache for faster re-runs

By default, the tarball is extracted into `tempdir()` which is cleaned up when R exits. For repeated test runs, use a persistent cache:

```bash
PETFIT_INTEGRATION_TESTS=true \
PETFIT_INTEGRATION_CACHE=/tmp/petfit_integration_cache \
  Rscript -e "devtools::test(filter = 'integration')"
```

---

## Adding New Config Files for Testing

The test suite is designed so you can add new modelling configurations by creating a JSON fixture and a small test file. Here is the step-by-step process:

### Step 1: Create the config JSON

Create a new JSON config file in `tests/testthat/fixtures/integration/`. Name it descriptively:

```
tests/testthat/fixtures/integration/ds004869_my_new_config.json
```

The easiest way to create a config is to:

1. Run the Shiny modelling app interactively with test data
2. Configure your desired settings
3. Copy the generated `desc-petfitoptions_config.json` to the fixtures directory

Or copy an existing config and modify it:

```bash
cp tests/testthat/fixtures/integration/ds004869_plasma_config.json \
   tests/testthat/fixtures/integration/ds004869_logan_config.json
```

Then edit the JSON to change the model type, parameters, etc.

**Key fields to check:**

- `modelling_configuration_type`: `"plasma input"` or `"reference tissue"`
- `Subsetting.sub`: Use `"01;02"` for fast tests (2 subjects) or `""` for all subjects
- `Subsetting.Regions`: Include the reference region here if using reference tissue pipeline
- `Models.Model1.type`: The model type (e.g., `"2TCM"`, `"SRTM"`, `"Logan"`, etc.)
- `Models.Model2.type` / `Model3.type`: Set to `"No Model"` to skip
- `FitDelay.model`: Use `"1tcm_singletac"` for plasma configs (not `"Set to zero..."` unless you truly want no delay)
- `ReferenceTAC.region`: Must match a region name in the data (for reference configs)

### Step 2: Create the test file

Create a new test file at `tests/testthat/test-integration-modelling-<name>.R`. Use this template:

```r
# Integration tests: <Description>
#
# Tests petfit_modelling_auto() with real ds004869 data using
# <describe your pipeline>.
#
# Requires: PETFIT_INTEGRATION_TESTS=true

# ---------------------------------------------------------------------------
# Helper: run regiondef + modelling setup
# ---------------------------------------------------------------------------

setup_my_workspace <- function() {
  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  setup_regiondef_config(ws)

  # Run regiondef to create combined TACs
  regiondef_result <- petfit_regiondef_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  if (!regiondef_result$success) {
    testthat::skip(paste("Regiondef failed:",
                         paste(regiondef_result$messages, collapse = "\n")))
  }

  # Install your config file
  setup_modelling_config(ws, "ds004869_my_new_config.json")

  ws
}

# ---------------------------------------------------------------------------
# Full pipeline test
# ---------------------------------------------------------------------------

test_that("my new pipeline runs end-to-end", {
  skip_if_no_integration()

  ws <- setup_my_workspace()
  withr::defer(cleanup_workspace(ws))

  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  expect_true(result$success,
              info = paste(result$messages, collapse = "\n"))
})

# ---------------------------------------------------------------------------
# Add more specific tests as needed
# ---------------------------------------------------------------------------

test_that("my new config generates expected reports", {
  skip_if_no_integration()

  ws <- setup_my_workspace()
  withr::defer(cleanup_workspace(ws))

  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  # Check for model1 report
  report_path <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis",
                           "reports", "model1_report.html")
  expect_true(file.exists(report_path),
              info = "Model 1 report should be generated")
})
```

### Step 3: Run your new test

```bash
PETFIT_INTEGRATION_TESTS=true \
  Rscript -e "devtools::test(filter = 'integration-modelling-<name>')"
```

### Tips for new configs

- **Subset to 2 subjects** (`"sub": "01;02"`) for fast testing. Full 27-subject tests can be added separately.
- **Plasma configs must run delay estimation** — set `FitDelay.model` to `"1tcm_singletac"` or similar. Setting it to `"Set to zero..."` skips creating `_inputfunction.tsv` files that model reports need.
- **Reference configs must include the reference region** in `Subsetting.Regions`. E.g., if `ReferenceTAC.region` is `"Cerebellum"`, then Regions must include `"Cerebellum"`.
- **Test a single step** by passing `step = "model1"` to `petfit_modelling_auto()`. Run prerequisites first.

---

## Existing Config Files

| File | Pipeline | Models | Notes |
|---|---|---|---|
| `ds004869_plasma_config.json` | Plasma input | 2TCM | 2 subjects, 1TCM delay, all regions |
| `ds004869_ref_config.json` | Reference tissue | SRTM | 2 subjects, Cerebellum ref, Frontal+Temporal+Cerebellum |

---

## Test File Overview

| File | What it tests | Assertions |
|---|---|---|
| `test-integration-dataset.R` | Test data extraction, file counts, readability | ~46 |
| `test-integration-regiondef.R` | `petfit_regiondef_auto()`: columns, regions, BIDS metadata, volumes | ~46 |
| `test-integration-modelling-plasma.R` | Plasma pipeline: datadef, weights, delay, 2TCM model | ~26 |
| `test-integration-modelling-ref.R` | Reference pipeline: datadef, reference TAC, SRTM model | ~12 |
| `test-integration-docker.R` | Docker container: regiondef, plasma, reference, error handling | ~15 |
| `test-integration-singularity.R` | Singularity scripts, container: regiondef, plasma, reference | ~20 |

---

## Test Data Lifecycle

```
prepare_testdata.sh (one-time, requires datalad)
  └─ Creates ds004869_testdata.tar.gz
       └─ Upload to GitHub Release (tag: testdata-v1.0)

At test time (no datalad needed):
  └─ ensure_testdata()
       ├─ Checks PETFIT_TESTDATA_PATH env var
       ├─ Checks local fixtures/integration/ directory
       ├─ Falls back to GitHub Release download (gh CLI)
       └─ Extracts to cache dir, writes sentinel file

Each test_that() block:
  ├─ skip_if_no_integration()
  ├─ ws <- create_integration_workspace(dataset_dir)
  ├─ withr::defer(cleanup_workspace(ws))
  └─ ... test logic with isolated writable workspace ...
```

---

## GitHub Actions

The workflow at `.github/workflows/integration-tests.yml` runs three parallel jobs:

1. **R-native**: Installs R + dependencies, downloads test data from GitHub Release (cached), runs all `integration-*` test files.
2. **Docker**: Builds Docker image with layer caching, runs Docker-specific integration tests.
3. **Apptainer**: Installs Apptainer, builds Docker image, runs Singularity-specific tests.

The workflow triggers on pushes to `main`, pull requests, and manual dispatch. Test data is cached across runs using the release tag as cache key.

---

## Troubleshooting

**Tests skip with "Test data tarball not found"**: Run `prepare_testdata.sh` or set `PETFIT_TESTDATA_PATH` to point to the tarball.

**Docker tests skip with "Docker image not available"**: Pull the image (`docker pull mathesong/petfit:latest`) or set `PETFIT_DOCKER_BUILD=true`.

**Singularity tests skip with "No Singularity container found"**: Provide a `.sif` file via `PETFIT_SINGULARITY_SIF` or ensure the Docker image is available.

**Regiondef fails with "No regions could be matched"**: The `description` column in `ds004869_petfit_regions.tsv` must match the BIDS key-value pair ordering generated by `create_bids_key_value_pairs()`. Currently: `seg-gtm_desc-preproc` (seg has priority, then alphabetical).

**Plasma model fails with "No inputfunction.tsv files found"**: The delay step must actually run (not be skipped) to create `_inputfunction.tsv` files. Set `FitDelay.model` to `"1tcm_singletac"` in the config.

**Reference TAC fails with "No reference region"**: Ensure the reference region (e.g., `Cerebellum`) is included in `Subsetting.Regions`.
