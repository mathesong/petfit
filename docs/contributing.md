# Contributing

Contributions are welcome! Please report issues or submit pull requests on [GitHub](https://github.com/mathesong/petfit).

## Development setup

1. Clone the repository:

   ```bash
   git clone https://github.com/mathesong/petfit.git
   cd petfit
   ```

2. Install the package in development mode:

   ```r
   # Install dependencies
   remotes::install_deps()

   # Load the package for development
   devtools::load_all()
   ```

3. Open the RStudio project (`petfit.Rproj`) for the best development experience.

## Repository structure

```
petfit/
├── R/                          # Package source code
│   ├── region_definition_app.R # Region definition Shiny app
│   ├── modelling_plasma_app.R  # Plasma input modelling app
│   ├── modelling_ref_app.R     # Reference tissue modelling app
│   ├── region_utils.R          # Region processing utilities
│   ├── pipeline_core.R         # Core pipeline execution
│   ├── docker_functions.R      # Docker/container orchestration
│   ├── report_generation.R     # Report template management
│   ├── subsetting_utils.R      # Data subsetting
│   ├── ancillary_utils.R       # Ancillary analysis folder utilities
│   ├── blood_utils.R           # Blood data handling
│   ├── bids_utils.R            # BIDS attribute parsing
│   ├── launch_apps.R           # App launcher function
│   └── ...
├── man/                        # Auto-generated roxygen2 documentation
├── inst/rmd/                   # Parameterised report templates (Rmd)
├── tests/testthat/             # Unit and integration tests
├── docker/                     # Docker configuration
├── singularity/                # Singularity/Apptainer configuration
├── docs/                       # Sphinx documentation (this site)
├── DESCRIPTION                 # R package metadata
├── NAMESPACE                   # Exported functions
└── CLAUDE.md                   # Developer architecture guide
```

## Coding standards

### Tidyverse conventions

PETFit follows tidyverse conventions throughout:

- Use `tibble()` instead of `data.frame()`
- Use `purrr` functions (`map()`, `walk()`) instead of `apply()` family
- Use `stringr` (`str_detect()`, `str_replace()`) instead of base R string functions
- Use `dplyr` verbs (`mutate()`, `filter()`, `select()`) for data manipulation
- Load `library(tidyverse)` in report templates

### File I/O

- **TSV/CSV files:** Use `readr::read_tsv()` and `readr::write_tsv()` (not base R `read.table()`/`write.table()`)
- **JSON files:** Use `jsonlite` with `auto_unbox = TRUE` for configuration files
- **Why:** `readr` preserves character types (subject `"01"` stays as `"01"`) and handles column names with hyphens correctly

### Spelling

Use British English: "visualisation" not "visualization", "colour" not "color", "analyse" not "analyze".

### Documentation

Functions use roxygen2 documentation. After modifying function documentation, regenerate with:

```r
devtools::document()
```

## Testing

PETFit has two categories of tests: **unit tests** (fast, no external data) and **integration tests** (use real PET data, disabled by default). Both use the [testthat](https://testthat.r-lib.org/) framework.

### Running tests

**Unit tests only** (fast, no setup needed):

```bash
Rscript -e "devtools::test()"
```

**Full integration battery** (R-native, no containers):

```bash
PETFIT_INTEGRATION_TESTS=true \
  Rscript -e "devtools::test()"
```

This runs all unit tests plus all R-native integration tests (region definition, plasma modelling, reference modelling, ancillary inheritance, parallel processing).

**Full integration battery with Docker**:

```bash
PETFIT_INTEGRATION_TESTS=true \
  PETFIT_DOCKER_TESTS=true \
  Rscript -e "devtools::test()"
```

**Full integration battery with Apptainer/Singularity**:

```bash
PETFIT_INTEGRATION_TESTS=true \
  PETFIT_SINGULARITY_TESTS=true \
  Rscript -e "devtools::test()"
```

**Everything** (R-native + Docker + Apptainer):

```bash
PETFIT_INTEGRATION_TESTS=true \
  PETFIT_DOCKER_TESTS=true \
  PETFIT_SINGULARITY_TESTS=true \
  Rscript -e "devtools::test()"
```

**Single test file** (useful during development):

```bash
# A specific unit test
Rscript -e "devtools::test(filter = 'bids_utils')"

# A specific integration test
PETFIT_INTEGRATION_TESTS=true \
  Rscript -e "devtools::test(filter = 'integration-regiondef')"
```

**Persistent cache** (avoids re-extracting test data between runs):

```bash
PETFIT_INTEGRATION_TESTS=true \
  PETFIT_INTEGRATION_CACHE=/tmp/petfit_cache \
  Rscript -e "devtools::test()"
```

### Unit tests

Unit tests are in `tests/testthat/` with the naming convention `test-<module>.R`. They run by default with `devtools::test()` and require no external data or environment variables.

**Current unit test files:**

| File | What it tests |
|------|---------------|
| `test-bids_utils.R` | BIDS attribute formatting, PET identifier extraction |
| `test-blood_utils.R` | Blood file detection, status reporting, pattern matching |
| `test-subsetting_utils.R` | Semicolon parsing, data filtering, individual TACs creation |
| `test-ancillary_utils.R` | Ancillary folder validation, helper utilities |
| `test-report_generation.R` | Model-to-template mapping, reports summary generation |
| `test-petfit_interactive.R` | Interactive app launcher validation |
| `test-petfit_auto.R` | Automatic pipeline launcher validation |

#### Unit test pattern

Each unit test follows this structure:

```r
test_that("function does X correctly", {
  # 1. Create isolated temp directory if needed

temp_dir <- withr::local_tempdir()

  # 2. Set up test data
  test_data <- tibble::tibble(
    sub = c("01", "02"),
    ses = c("01", "02"),
    region = c("Frontal", "Temporal")
  )

  # 3. Call the function under test
  result <- function_under_test(test_data)

  # 4. Assert expectations
  expect_type(result, "character")
  expect_equal(length(result), 2)
  expect_true(all(grepl("sub-", result)))
})
```

**Key patterns:**
- Use `withr::local_tempdir()` for temporary directories (automatically cleaned up).
- Use `tibble::tibble()` for test data (not `data.frame()`).
- Use `readr::write_tsv()` / `readr::read_tsv()` for file I/O in tests.
- Test edge cases: `NULL` inputs, empty strings, missing columns.

#### Writing a new unit test

1. Create a file named `test-<module>.R` in `tests/testthat/`.
2. Write `test_that()` blocks following the pattern above.
3. Run with `Rscript -e "devtools::test(filter = '<module>')"`.

### Integration tests

Integration tests verify full PETFit pipelines end-to-end using real PET data from [OpenNeuro ds004869](https://openneuro.org/datasets/ds004869) (COX-2 PET, 27 subjects, C-11 tracer). They are disabled by default and gated behind environment variables.

**Current integration test files:**

| File | What it tests |
|------|---------------|
| `test-integration-dataset.R` | Test data extraction, file counts, readability |
| `test-integration-regiondef.R` | `petfit_regiondef_auto()`: columns, regions, BIDS metadata, volumes |
| `test-integration-modelling-plasma.R` | Plasma pipeline: datadef, weights, delay, 2TCM model |
| `test-integration-modelling-ref.R` | Reference pipeline: datadef, reference TAC, SRTM model |
| `test-integration-ancillary.R` | Ancillary folder inheritance: delay and k2prime |
| `test-integration-parallel.R` | Parallel processing (R-native) |
| `test-integration-docker.R` | Docker container execution |
| `test-integration-singularity.R` | Singularity/Apptainer container execution |
| `test-integration-parallel-docker.R` | Parallel processing in Docker |
| `test-integration-parallel-singularity.R` | Parallel processing in Singularity |

#### Environment variables

| Variable | Purpose |
|----------|---------|
| `PETFIT_INTEGRATION_TESTS=true` | Enable R-native integration tests |
| `PETFIT_TESTDATA_PATH` | Explicit path to `ds004869_testdata.tar.gz` |
| `PETFIT_INTEGRATION_CACHE` | Persistent cache directory for extracted data |
| `PETFIT_DOCKER_TESTS=true` | Enable Docker container tests |
| `PETFIT_DOCKER_BUILD=true` | Rebuild Docker image before testing |
| `PETFIT_SINGULARITY_TESTS=true` | Enable Singularity/Apptainer tests |
| `PETFIT_SINGULARITY_SIF` | Explicit path to `.sif` container file |

#### Test data

The test data tarball (`ds004869_testdata.tar.gz`, ~2.7 MB) is committed to the repository at `tests/testthat/fixtures/integration/`. It contains real TSV/JSON files from OpenNeuro ds004869 with NIfTI files replaced by empty placeholders.

At test time, the `ensure_testdata()` helper extracts the tarball. It searches for it in order:
1. `PETFIT_TESTDATA_PATH` environment variable
2. Local fixtures directory (normal case)
3. GitHub Release download (fallback)

To regenerate the tarball from scratch (requires datalad):
```bash
cd tests/testthat/fixtures/integration && bash prepare_testdata.sh
```

#### Workspace isolation

Each integration test creates an isolated workspace via `create_integration_workspace()`:
- Symlinks `petprep` derivatives as read-only source data.
- Creates a writable `derivatives/petfit/` directory for outputs.
- Cleaned up automatically via `withr::defer(cleanup_workspace(ws))`.

This ensures tests never modify the shared test data and cannot interfere with each other.

#### Config fixtures

Pre-built configuration files for testing are in `tests/testthat/fixtures/integration/`:

| File | Pipeline | Model |
|------|----------|-------|
| `ds004869_petfit_regions.tsv` | Region definition | 4 regions: Frontal, Temporal, Cerebellum, WhiteMatter |
| `ds004869_plasma_config.json` | Plasma input | 2TCM (2 subjects, 1TCM delay) |
| `ds004869_ref_config.json` | Reference tissue | SRTM (2 subjects, Cerebellum reference) |

#### Integration test pattern

Each integration test follows this structure:

```r
# File header describing what this test covers
# Requires: PETFIT_INTEGRATION_TESTS=true

test_that("pipeline produces expected output", {
  skip_if_no_integration()

  # 1. Get test data (extracted once per session, cached)
  dataset_dir <- ensure_testdata()

  # 2. Create isolated workspace
  ws <- create_integration_workspace(dataset_dir)
  withr::defer(cleanup_workspace(ws))

  # 3. Install config fixtures
  setup_regiondef_config(ws)
  # For modelling tests:
  # setup_modelling_config(ws, "ds004869_plasma_config.json")

  # 4. Run the pipeline
  result <- petfit_regiondef_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  # 5. Assert success
  expect_true(result$success, info = paste(result$messages, collapse = "\n"))

  # 6. Verify outputs
  expect_true(file.exists(result$output_file))
  data <- readr::read_tsv(result$output_file, show_col_types = FALSE)
  expect_true("region" %in% names(data))
  expect_equal(length(unique(data$region)), 4)
})
```

**Key patterns:**
- Always start with `skip_if_no_integration()`.
- Always use `create_integration_workspace()` + `withr::defer(cleanup_workspace(ws))`.
- Use `info = paste(result$messages, collapse = "\n")` in assertions for debugging context.
- For modelling tests, run region definition first (or use `setup_modelling_config()` which assumes regions already exist).

#### Writing a new integration test

1. Create a file named `test-integration-<name>.R` in `tests/testthat/`.
2. Add a file header comment describing what the test covers and which environment variable is required.
3. Create a JSON config fixture in `tests/testthat/fixtures/integration/` if needed (copy from an existing one and modify).
4. Write `test_that()` blocks using the pattern above.
5. Run with:
   ```bash
   PETFIT_INTEGRATION_TESTS=true Rscript -e "devtools::test(filter = 'integration-<name>')"
   ```

#### Config fixture gotchas

- **BIDS description ordering**: `petfit_regions.tsv` description column must use `seg-gtm_desc-preproc` (not `desc-preproc_seg-gtm`). The `create_bids_key_value_pairs()` function gives `seg`/`label` priority, then sorts remaining keys alphabetically.
- **Reference region must be in subsetting**: If `ReferenceTAC.region` is `"Cerebellum"`, then `Subsetting.Regions` must include `"Cerebellum"`.
- **Delay set to zero**: When `FitDelay.model` is `"Set to zero..."`, the delay step is skipped but model reports independently load blood data from raw BIDS `_blood.tsv` files.

### Test infrastructure

**`tests/testthat/helper-integration.R`** provides all the shared utilities:

| Function | Purpose |
|----------|---------|
| `skip_if_no_integration()` | Skip test if `PETFIT_INTEGRATION_TESTS` not set |
| `skip_if_no_docker()` | Skip test if Docker not available |
| `skip_if_no_singularity()` | Skip test if Singularity/Apptainer not available |
| `ensure_testdata()` | Extract test data tarball (cached per session) |
| `create_integration_workspace(dataset_dir)` | Create isolated workspace with symlinks |
| `cleanup_workspace(ws)` | Remove temporary workspace |
| `setup_regiondef_config(ws)` | Copy `petfit_regions.tsv` to workspace |
| `setup_modelling_config(ws, config_name)` | Copy JSON config fixture to analysis folder |
| `run_petfit_docker(...)` | Execute Docker container with proper mounts |
| `run_petfit_singularity(...)` | Execute Singularity container with bind mounts |

**`tests/testthat/helper-setup.R`** loads the `here` package and sets the package root directory.

### CI/CD

Integration tests run automatically on GitHub Actions (`.github/workflows/integration-tests.yml`) with three parallel jobs:

1. **R-native** — Uses test data from the repository, runs all integration tests.
2. **Docker** — Builds the Docker image with layer caching, runs container tests.
3. **Apptainer** — Installs Apptainer, builds from Docker image, runs Singularity tests.

The workflow triggers on pushes to `main`, pull requests, and manual dispatch.

## Configuration management

When adding new features to the modelling apps, always ensure backward compatibility with existing JSON configuration files:

- Use null coalescing (`%||%`) when accessing new config properties
- Provide sensible defaults for missing sections
- Handle missing or invalid data gracefully
- Add UI update logic for any new input fields

## Building documentation

The documentation uses Sphinx with MyST (Markdown). See the [docs/README.md](https://github.com/mathesong/petfit/blob/main/docs/README.md) for full instructions on editing and building the documentation locally.

Quick start:

```bash
pip install -r docs/requirements.txt
cd docs
make html
# Open _build/html/index.html in your browser
```

When making code changes, please update the relevant documentation pages as well.
