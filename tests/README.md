# petfit Test Suite

## Overview

The test suite has two layers:

1. **Unit tests** (fast, no external data needed) — test individual functions with simple inputs
2. **Integration tests** (slower, require real PET data) — test full pipelines end-to-end with real ds004869 data

Unit tests run by default. Integration tests are disabled unless explicitly enabled via environment variables.

---

## Running Tests

### Unit tests only (default)

**Bash:**
```bash
Rscript -e "devtools::test()"
```

**R (e.g. from RStudio console):**
```r
devtools::test()
```

### Integration tests only

**Bash:**
```bash
PETFIT_INTEGRATION_TESTS=true Rscript -e "devtools::test(filter = 'integration')"
```

**R:**
```r
Sys.setenv(PETFIT_INTEGRATION_TESTS = "true")
devtools::test(filter = "integration")
```

### A specific integration test file

**Bash:**
```bash
PETFIT_INTEGRATION_TESTS=true Rscript -e "devtools::test(filter = 'integration-regiondef')"
```

**R:**
```r
Sys.setenv(PETFIT_INTEGRATION_TESTS = "true")
devtools::test(filter = "integration-regiondef")
```

### Everything together

**Bash:**
```bash
PETFIT_INTEGRATION_TESTS=true Rscript -e "devtools::test()"
```

**R:**
```r
Sys.setenv(PETFIT_INTEGRATION_TESTS = "true")
devtools::test()
```

### With persistent cache (avoids re-extracting test data between sessions)

**Bash:**
```bash
PETFIT_INTEGRATION_TESTS=true PETFIT_INTEGRATION_CACHE=/tmp/petfit_cache Rscript -e "devtools::test(filter = 'integration')"
```

**R:**
```r
Sys.setenv(PETFIT_INTEGRATION_TESTS = "true")
Sys.setenv(PETFIT_INTEGRATION_CACHE = "/tmp/petfit_cache")
devtools::test(filter = "integration")
```

### Container tests (Docker)

Requires Docker and the `mathesong/petfit:latest` image:

**Bash:**
```bash
# Pull the image (or build from source -- see below)
docker pull mathesong/petfit:latest

# Run Docker integration tests
PETFIT_INTEGRATION_TESTS=true \
PETFIT_DOCKER_TESTS=true \
  Rscript -e "devtools::test(filter = 'integration-docker')"
```

**R:**
```r
Sys.setenv(PETFIT_INTEGRATION_TESTS = "true")
Sys.setenv(PETFIT_DOCKER_TESTS = "true")
devtools::test(filter = "integration-docker")
```

To rebuild the Docker image from source before testing:

**Bash:**
```bash
PETFIT_INTEGRATION_TESTS=true \
PETFIT_DOCKER_TESTS=true \
PETFIT_DOCKER_BUILD=true \
  Rscript -e "devtools::test(filter = 'integration-docker')"
```

**R:**
```r
Sys.setenv(PETFIT_INTEGRATION_TESTS = "true")
Sys.setenv(PETFIT_DOCKER_TESTS = "true")
Sys.setenv(PETFIT_DOCKER_BUILD = "true")
devtools::test(filter = "integration-docker")
```

### Container tests (Singularity / Apptainer)

Requires `singularity` or `apptainer` CLI:

**Bash:**
```bash
# With a .sif file
PETFIT_INTEGRATION_TESTS=true \
PETFIT_SINGULARITY_TESTS=true \
PETFIT_SINGULARITY_SIF=/path/to/petfit_latest.sif \
  Rscript -e "devtools::test(filter = 'integration-singularity')"

# Or with the Docker image available (uses docker-daemon: reference)
PETFIT_INTEGRATION_TESTS=true \
PETFIT_SINGULARITY_TESTS=true \
  Rscript -e "devtools::test(filter = 'integration-singularity')"
```

**R:**
```r
Sys.setenv(PETFIT_INTEGRATION_TESTS = "true")
Sys.setenv(PETFIT_SINGULARITY_TESTS = "true")
Sys.setenv(PETFIT_SINGULARITY_SIF = "/path/to/petfit_latest.sif")
devtools::test(filter = "integration-singularity")
```

Script validation tests (no container needed) run with just `PETFIT_INTEGRATION_TESTS=true` and are included in the Singularity test file.

### All integration tests (including containers)

**Bash:**
```bash
PETFIT_INTEGRATION_TESTS=true \
PETFIT_DOCKER_TESTS=true \
PETFIT_SINGULARITY_TESTS=true \
  Rscript -e "devtools::test(filter = 'integration')"
```

**R:**
```r
Sys.setenv(PETFIT_INTEGRATION_TESTS = "true")
Sys.setenv(PETFIT_DOCKER_TESTS = "true")
Sys.setenv(PETFIT_SINGULARITY_TESTS = "true")
devtools::test(filter = "integration")
```

---

## Inspecting Test Outputs (Reports, Files, etc.)

By default, each integration test creates a temporary workspace that is **automatically cleaned up** after the test finishes. This means generated reports and output files are deleted. To inspect them, run the pipeline manually in an R session using the same helper functions the tests use:

**R:**
```r
# Load the package and test helpers
devtools::load_all()
source("tests/testthat/helper-integration.R")

# Extract test data (uses cache if available)
Sys.setenv(PETFIT_INTEGRATION_CACHE = "/tmp/petfit_cache")
dataset_dir <- ensure_testdata()

# Create a workspace (this is what each test does internally)
ws <- create_integration_workspace(dataset_dir)

# Set up the region definition config
setup_regiondef_config(ws)

# Run regiondef
regiondef_result <- petfit_regiondef_auto(
  bids_dir = ws$bids_dir,
  derivatives_dir = ws$derivatives_dir
)

# Install a modelling config (e.g. plasma)
setup_modelling_config(ws, "ds004869_plasma_config.json")

# Run the modelling pipeline
result <- petfit_modelling_auto(
  bids_dir = ws$bids_dir,
  derivatives_dir = ws$derivatives_dir
)

# Now inspect outputs — the workspace is still alive!
# Print the workspace paths:
cat("BIDS dir:", ws$bids_dir, "\n")
cat("Derivatives dir:", ws$derivatives_dir, "\n")
cat("Analysis folder:", file.path(ws$derivatives_dir, "petfit", "Primary_Analysis"), "\n")

# List generated reports
list.files(file.path(ws$derivatives_dir, "petfit", "Primary_Analysis", "reports"),
           full.names = TRUE)

# Open a report in your browser
browseURL(file.path(ws$derivatives_dir, "petfit", "Primary_Analysis",
                    "reports", "model1_report.html"))

# When you're done inspecting, clean up manually:
cleanup_workspace(ws)
```

This lets you browse generated HTML reports, check intermediate files (TACs, weights, input functions), and verify everything looks correct before cleaning up.

---

## Unit Tests

These test individual functions in isolation with simple inputs. No external data or special setup required.

| File | What it tests |
|------|---------------|
| `test-bids_utils.R` | BIDS attribute formatting, PET identifier extraction |
| `test-blood_utils.R` | Blood data file detection, status reporting, pattern matching |
| `test-subsetting_utils.R` | Semicolon-separated value parsing, data filtering, individual TACs file creation |
| `test-report_generation.R` | Model-to-template mapping, reports summary generation |
| `test-petfit_interactive.R` | Interactive app launcher function signature and directory validation |
| `test-petfit_auto.R` | Automatic pipeline launcher function signature and argument validation |

---

## Integration Tests

Integration tests verify petfit pipelines end-to-end using real PET data from [OpenNeuro ds004869](https://openneuro.org/datasets/ds004869) (COX-2 PET, 27 subjects, C-11 tracer). Tests are disabled by default and gated behind environment variables.

| File | What it tests |
|------|---------------|
| `test-integration-dataset.R` | Test data extraction, file counts, readability |
| `test-integration-regiondef.R` | Region definition pipeline: columns, regions, BIDS metadata, volumes |
| `test-integration-modelling-plasma.R` | Plasma pipeline: datadef, weights, delay, 2TCM model, single-subject, zero-delay |
| `test-integration-modelling-ref.R` | Reference tissue pipeline: datadef, reference TAC, SRTM model, single-subject |
| `test-integration-docker.R` | Docker container: regiondef, plasma, reference, error handling |
| `test-integration-singularity.R` | Singularity/Apptainer scripts and container execution |

### Test Data

The test data tarball (`ds004869_testdata.tar.gz`, ~2.7 MB) is **included in the repository** at `tests/testthat/fixtures/integration/`. It contains real TSV/JSON files from OpenNeuro ds004869 with NIfTI files replaced by empty placeholders (petfit only needs the tabular data).

The tarball is excluded from the built R package via `.Rbuildignore`, so users who install via `remotes::install_github()` don't get the test data — only developers who clone the repo have it.

**How tests find it:** At test time, `ensure_testdata()` in `helper-integration.R` searches in order:
1. `PETFIT_TESTDATA_PATH` environment variable (explicit path override)
2. Local `tests/testthat/fixtures/integration/` directory (the normal case)
3. GitHub Release download as fallback (R-native HTTP, then `gh` CLI)

**To regenerate the tarball from scratch** (requires [datalad](https://www.datalad.org/)):
```bash
cd tests/testthat/fixtures/integration
bash prepare_testdata.sh
```

### Test Data Lifecycle

```
prepare_testdata.sh (one-time, requires datalad)
  └─ Creates ds004869_testdata.tar.gz (committed to repo)

At test time (no datalad needed):
  └─ ensure_testdata()
       ├─ Checks PETFIT_TESTDATA_PATH env var
       ├─ Checks local fixtures/integration/ directory (normal case)
       ├─ Falls back to GitHub Release download
       └─ Extracts to cache dir, writes sentinel file

Each test_that() block:
  ├─ skip_if_no_integration()
  ├─ ws <- create_integration_workspace(dataset_dir)
  ├─ withr::defer(cleanup_workspace(ws))
  └─ ... test logic with isolated writable workspace ...
```

### Workspace Isolation

Each test creates an isolated workspace via `create_integration_workspace()`:
- Symlinks `petprep` derivatives as read-only source data
- Creates a writable `derivatives/petfit/` directory for outputs
- Cleaned up automatically after each test via `withr::defer(cleanup_workspace(ws))`

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `PETFIT_INTEGRATION_TESTS` | (unset) | Set to `true` to enable integration tests |
| `PETFIT_TESTDATA_PATH` | (unset) | Explicit path to `ds004869_testdata.tar.gz` (rarely needed) |
| `PETFIT_INTEGRATION_CACHE` | `tempdir()/petfit_integration` | Persistent cache for extracted data |
| `PETFIT_DOCKER_TESTS` | (unset) | Set to `true` to enable Docker tests |
| `PETFIT_DOCKER_BUILD` | (unset) | Set to `true` to rebuild Docker image before testing |
| `PETFIT_SINGULARITY_TESTS` | (unset) | Set to `true` to enable Singularity tests |
| `PETFIT_SINGULARITY_SIF` | (unset) | Explicit path to `.sif` container file |

---

## Adding a New Integration Test Configuration

The integration tests are designed so you can easily add new modelling configurations. You need two things: a JSON config fixture and a test file.

### Step 1: Create the JSON config

Create a new file in `tests/testthat/fixtures/integration/`. You can either:

**Option A:** Copy an existing config and modify it:
```bash
cp tests/testthat/fixtures/integration/ds004869_plasma_config.json \
   tests/testthat/fixtures/integration/ds004869_logan_config.json
```

**Option B:** Run the Shiny modelling app interactively with test data, configure your desired settings, and copy the generated `desc-petfitoptions_config.json` to the fixtures directory.

Then edit the JSON. Key fields to check:

| Field | Description | Example |
|-------|-------------|---------|
| `modelling_configuration_type` | Pipeline type | `"plasma input"` or `"reference tissue"` |
| `Subsetting.sub` | Subject filter (use 2 for fast tests, `""` for all) | `"01;02"` |
| `Subsetting.Regions` | Region filter (must include reference region for ref configs) | `"Frontal;Temporal;Cerebellum"` |
| `Models.Model1.type` | Model to fit | `"2TCM"`, `"SRTM"`, `"Logan"`, etc. |
| `Models.Model2.type` | Second model (or skip) | `"No Model"` |
| `FitDelay.model` | Delay method | `"1tcm_singletac"` or `"Set to zero..."` |
| `ReferenceTAC.region` | Reference region name (ref configs only) | `"Cerebellum"` |

**Important gotchas:**
- Reference configs must include the reference region in `Subsetting.Regions`
- The `description` column in `petfit_regions.tsv` uses a specific BIDS key ordering: `seg`/`label` first, then remaining keys alphabetically (e.g., `seg-gtm_desc-preproc`)

**Tips:**
- Subset to 2 subjects (`"sub": "01;02"`) for fast testing. Full 27-subject tests can be added separately.
- You can test a single step by passing `step = "model1"` to `petfit_modelling_auto()` (run prerequisites first).

### Step 2: Create the test file

Create `tests/testthat/test-integration-modelling-<name>.R`:

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

  # Verify reports
  report_path <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis",
                           "reports", "model1_report.html")
  expect_true(file.exists(report_path))
})
```

### Step 3: Run it

**Bash:**
```bash
PETFIT_INTEGRATION_TESTS=true Rscript -e "devtools::test(filter = 'integration-modelling-<name>')"
```

**R:**
```r
Sys.setenv(PETFIT_INTEGRATION_TESTS = "true")
devtools::test(filter = "integration-modelling-<name>")
```

### Existing config fixtures

| File | Pipeline | Model | Notes |
|------|----------|-------|-------|
| `ds004869_plasma_config.json` | Plasma input | 2TCM | 2 subjects, 1TCM delay, all regions |
| `ds004869_ref_config.json` | Reference tissue | SRTM | 2 subjects, Cerebellum ref, Frontal+Temporal+Cerebellum |
| `ds004869_petfit_regions.tsv` | Region definition | 4 regions | All 27 subjects |

---

## Helper Functions (helper-integration.R)

| Function | Purpose |
|----------|---------|
| `skip_if_no_integration()` | Skip test if `PETFIT_INTEGRATION_TESTS` not set |
| `skip_if_no_docker()` | Skip test if Docker not available |
| `skip_if_no_singularity()` | Skip test if Singularity/Apptainer not available |
| `ensure_testdata()` | Extract test data tarball, return dataset path |
| `create_integration_workspace(dataset_dir)` | Create isolated workspace with symlinked source data |
| `cleanup_workspace(ws)` | Remove temporary workspace |
| `setup_regiondef_config(ws)` | Copy `petfit_regions.tsv` to workspace |
| `setup_modelling_config(ws, config_name)` | Copy JSON config fixture to analysis folder |
| `run_petfit_docker(...)` | Execute Docker container |
| `run_petfit_singularity(...)` | Execute Singularity container |

---

## GitHub Actions

The workflow at `.github/workflows/integration-tests.yml` runs three parallel jobs:

1. **R-native**: Uses test data from repo checkout, runs all `integration-*` test files
2. **Docker**: Builds Docker image with GHA layer caching, runs Docker-specific integration tests
3. **Apptainer**: Installs Apptainer, builds Docker image, runs Singularity-specific tests

The workflow triggers on pushes to `main`, pull requests, and manual dispatch.

---

## Troubleshooting

**Tests skip with "Test data tarball not found"**: The tarball should be at `tests/testthat/fixtures/integration/ds004869_testdata.tar.gz`. If missing, run `prepare_testdata.sh` or set `PETFIT_TESTDATA_PATH`.

**Docker tests skip**: Pull the image (`docker pull mathesong/petfit:latest`) or set `PETFIT_DOCKER_BUILD=true`.

**Singularity tests skip**: Provide a `.sif` file via `PETFIT_SINGULARITY_SIF` or ensure the Docker image is available.

**Regiondef fails with "No regions could be matched"**: Check that the `description` column in `petfit_regions.tsv` uses the correct BIDS key ordering (`seg-gtm_desc-preproc`).

**Reference TAC fails**: Ensure the reference region is included in `Subsetting.Regions`.
