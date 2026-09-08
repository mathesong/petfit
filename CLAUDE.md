# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

An R Shiny web application (R package) that creates customised petfit BIDS App configuration files for PET imaging analysis, runs within a Docker container. Includes parameterised reports using configuration file parameters. Delegates kinetic model fitting to the `kinfitr` package.

**Usage modes:**
1. **Non-interactive**: Run kinetic modelling with pre-existing .json configs via `petfit_auto()`
2. **GUI-assisted**: Use Shiny apps via `petfit_interactive()` to create configs, then run processing
3. **Interactive exploration**: Test model fits on individual TACs in the modelling app's Interactive tab

**Three independent apps:**
- **Region Definition App** (`region_definition_app.R`): Brain region definitions and combined TACs
- **Modelling App - Plasma Input** (`modelling_plasma_app.R`): Invasive models (1TCM, 2TCM, nested2TCM, 2TCM_irr, Logan, MA1, Patlak) requiring blood data
- **Modelling App - Reference Tissue** (`modelling_ref_app.R`): Non-invasive models (SRTM, nestedSRTM, SRTM2, refLogan, MRTM1, MRTM2) using reference regions

## Commands

### Running the Application
```r
library(petfit)

# Interactive (Shiny apps)
petfit_interactive(bids_dir = "/path/to/bids")  # regiondef by default
petfit_interactive(app = "modelling_plasma", bids_dir = "/path/to/bids", blood_dir = "/path/to/blood")
petfit_interactive(app = "modelling_ref", bids_dir = "/path/to/bids")

# Non-interactive (automatic processing)
petfit_auto(app = "regiondef", bids_dir = "/path/to/bids")
petfit_auto(app = "modelling_plasma", bids_dir = "/path/to/bids", blood_dir = "/path/to/blood")

# Ancillary analysis (inherits delay/k2prime from sibling analysis)
petfit_interactive(app = "modelling_ref", bids_dir = "/path/to/bids",
                   ancillary_analysis_folder = "Primary_Analysis")
```

### Container Usage
- **Docker**: Interactive and automatic processing modes
- **Apptainer** (formerly Singularity): HPC-compatible, definition file in `apptainer/` folder

### Development
```bash
# Run unit tests
Rscript -e "devtools::test()"

# Run R CMD check
Rscript -e "devtools::check()"

# Regenerate roxygen docs
Rscript -e "devtools::document()"

# Run integration tests (disabled by default)
PETFIT_INTEGRATION_TESTS=true Rscript -e "devtools::test(filter = 'integration')"
```

## Architecture

### Package Structure
- `R/`: Source files - apps, utilities, pipeline logic, report generation
- `inst/rmd/`: Parameterised R Markdown report templates (rendered as interactive Plotly HTML)
- `man/`: Roxygen-generated documentation
- `tests/testthat/`: Unit and integration tests
- `apptainer/`: Apptainer definition file
- `.github/workflows/`: CI for integration tests (R-native, Docker, Apptainer)

### Directory Structure (BIDS Convention)
- `{bids_dir}/code/petfit/`: Region config files (`petfit_regions.tsv`)
- `{derivatives_dir}/petfit/`: Shared resources (`desc-combinedregions_tacs.tsv` with `seg_meanTAC` column)
- `{derivatives_dir}/petfit/{analysis_foldername}/`: Analysis-specific outputs, configs, and `reports/` subfolder

### Key Dependencies
- `kinfitr`: Core kinetic modelling (external)
- `shiny`, `bslib`, `shinythemes`: Web UI
- `tidyverse` ecosystem: Data manipulation (preferred over base R)
- `plotly`, `crosstalk`, `htmltools`: Interactive report visualisations
- `readr`: File I/O (replaces base R `read.table`/`write.table`)
- `jsonlite`: JSON config generation
- `rmarkdown`, `knitr`: Report rendering
- `future`, `furrr`: Parallel execution

### Report Templates
Located in `inst/rmd/`. Template selection is dynamic based on model choice:
- **Step reports**: `data_definition_report`, `weights_report`, `delay_report`, `reference_tac_report`, `tstar_finder_report`, `config_validation`
- **Model reports**: `1tcm`, `2tcm`, `nested2tcm`, `2tcmirr`, `logan`, `ma1`, `patlak`, `srtm`, `nestedsrtm`, `srtm2`, `reflogan`, `mrtm1`, `mrtm2`
- Output naming: `model1_report.html`, `model2_report.html`, `model3_report.html`

**IMPORTANT**: Report templates perform actual computational work (analysis logic) for transparency and reproducibility - they are not just display templates.

## Coding Standards

**IMPORTANT**: Follow tidyverse conventions throughout.

- Use `tidyverse` over base R: `tibble()` not `data.frame()`, `map()` not `sapply()`, `str_detect()` not `grepl()`
- Load `library(tidyverse)` in reports (not individual packages)
- **Use British English spelling**: "visualisation", "colour", "analyse", etc.

### File I/O Standards

**Tabular data**: Always use `readr::read_tsv()` / `readr::write_tsv()` (never `read.table()` / `write.table()`)
- Preserves character types (subject IDs stay "01" not 1)
- Preserves hyphens in column names (no `Left-Accumbens-area` -> `Left.Accumbens.area` conversion)
- Use `show_col_types = FALSE` to suppress messages

**JSON data**: Use `jsonlite` with `auto_unbox = TRUE` for config files (prevents `["value"]` instead of `"value"`)

### Interactive Plotly Report Patterns
- Render multiple plots: `htmltools::tagList(plot_list)` (not direct printing)
- Dimensions: Set in `ggplotly(p, width = 800, height = 500)`, not in `layout()` (deprecated by plotly) and not in CSS
- Legends: `guides(colour = "none")`, never `guides(colour = FALSE)` (deprecated in ggplot2 3.3.4)
- Spacing: `htmltools::div(.x, style="margin: 20px 0 50px 0;")`
- Cross-filtering: `crosstalk::SharedData$new()` with `highlight(on = "plotly_hover", off = "plotly_doubleclick")`

## Critical Gotchas

### readr Migration (Column Names)
- `readr::read_tsv()` preserves hyphens: morph column is `` `volume-mm3` `` (with backticks), not `volume.mm3`
- Do NOT convert hyphens to dots in region matching logic
- No `colClasses` needed - character types preserved automatically

### dplyr `any_of()` Syntax
```r
# CORRECT
select(-any_of(c("vB", "inpshift")))

# WRONG - causes errors
select(-any_of("vB", "inpshift"))
```

### JSON Configuration Backward Compatibility
When adding new features, always use null coalescing (`%||%`) for safe loading:
```r
if (!is.null(existing_config$NewFeature)) {
  updateTextInput(session, "new_input", value = existing_config$NewFeature$parameter %||% "default")
}
```
Set unused conditional fields to `""` in JSON; convert to `NULL` in R templates.

### BIDS Entity Ordering in `petfit_regions.tsv`
The `description` column must use `seg-gtm_desc-preproc` (not `desc-preproc_seg-gtm`). The `create_bids_key_value_pairs()` function gives `seg`/`label` priority, then sorts remaining keys alphabetically.

### External Config and Regions Files
- `--config-file` (wrapper) / `--config_file` (container) / `config_file` (R) supplies a modelling config from outside the dataset; `--regions-file` / `--regions_file` / `regions_file` does the same for `petfit_regions.tsv`
- The file is **copied into the canonical location** (`analysis_folder/desc-petfitoptions_config.json`, `derivatives/petfit/petfit_regions.tsv`) by `install_external_file()` in `R/external_files.R`, not read in place — so everything downstream is unchanged and the derivative stays self-contained
- Supplying a config creates the analysis folder if absent, so `run_petfit.R`'s "analysis folder must exist" guard is skipped when `--config_file` is given
- `check_external_config()` / `check_external_regions_file()` validate before copying, so a bad file never clobbers a good one. The config check enforces `modelling_configuration_type` against `config_type_for_pipeline(pipeline_type)` — necessary because `determine_pipeline_type()` gives the explicit `pipeline_type` priority over the config's own declaration, and `run_petfit.R` always passes it from `--func`. The regions check requires ≥1 row and ≥1 `folder` present in `derivatives_dir`
- `install_external_file()` returns `list(messages, destination, backup)`; a failure before any step runs calls `restore_external_file()` via each pipeline's local `abandon_run()`, which puts the replaced file back (or deletes the copy when there was nothing to replace)
- The file belonging to the other app is ignored with a console note (never an error)
- New arguments are appended **after** all existing ones in the exported signatures, so positional callers keep working; `tests/testthat/test-external_files.R` pins the pre-existing argument order
- The Docker wrapper bind-mounts the single file at `/data/config.json` or `/data/petfit_regions.tsv`, and rejects a missing path itself — Docker would otherwise create a *directory* there

### Run Merging
- Set in the **region definition** step, on by default: `merge_runs` on
  `create_petfit_combined_tacs()`, `petfit_regiondef_auto()`, `petfit_auto()`,
  `region_definition_app()`, `petfit_interactive()`; `--no_merge_runs`
  (container) / `--no-merge-runs` (wrapper). The modelling apps have no say --
  they read what the combined TACs already record
- `merge_tacs_runs()` in `R/run_merging.R` does the work: the combined TACs are
  already long format, so merging is largely **setting `run` to `NA`** and
  letting `reconstruct_pet_column()` rebuild identifiers without it
- Frame times are aligned by the **`TimeZero` clock difference**
  (`run_clock_offsets()`), deliberately the same rule bloodstream's
  `run_time_offsets()` applies to blood samples — worth lifting into kinfitr
  rather than being stated in both repos. `TimeZero` comes from the raw
  `_pet.json` via `lookup_pet_time_zero()`, so it needs `bids_dir`; the
  pipelines' `_tacs.json` sidecars do not carry it, so derivatives-only runs
  fall back to assuming a shared time zero. The overlap check is a
  **post-condition** either way, and its advice differs depending on whether a
  clock was available
- The `time_zero` column is scaffolding: added by the worker in
  `create_petfit_combined_tacs()` and dropped before the TSV is written (in both
  the merge and no-merge paths)
- Where anything merges, `run` is set to `NA` for **every** measurement,
  single-run ones included, so identity does not depend on which runs a
  measurement happens to have (same reasoning as `pet_key()` vs
  `attributes_to_title()`). Where **nothing** merges the data is returned
  untouched — dropping a `run-01` every measurement carries singly would rename
  every output of a dataset the merge never changed, and the app hides the
  checkbox in exactly that case, so the user could not see or stop it
- **Errors** on frames overlapping between runs (names the measurements);
  **warns** and keeps the earliest run's value when runs disagree on
  `InjectedRadioactivity`, `bodyweight` or a region's `volume_mm3`. "Earliest" is
  read from `frame_start`, never the run label
- `desc-combinedregions_tacs.json` records `MergedRuns` from
  `merge_tacs_runs()`'s returned `merged` flag — the outcome, not the request —
  because an empty `run` column otherwise looks identical to a dataset with no
  runs, and a requested-but-inert merge would be recorded as a real one
- The raw-BIDS blood merge uses the same offsets, via
  `merge_inputfunction_tables(offsets = )`, so petfit's fallback is not weaker
  than bloodstream's
- Blood: `create_analysis_inputfunctions()` in `R/blood_utils.R` replaces what
  the `load-from-bids-raw` chunk used to do inline in all 8 plasma/delay
  templates. It matches on whatever entities the TACs carry, so a merged
  measurement matches every run and their curves are pooled by
  `merge_inputfunction_tables()` — interpolate each, clip later runs to their own
  measured span (`bd_create_input()` always starts at 0, so a later run's table
  opens with padding), lay end to end, re-interpolate. Runs with no samples are
  dropped with a warning
- `check_blood_run_alignment()` is called in every plasma template after blood
  loading, and guards **both** directions, because the natural join simply drops
  `run` when only one side has it. Per-run input functions against run-less TACs
  would model a merged measurement with one run's blood; run-less input
  functions against per-run TACs (bloodstream defaults `MergeRuns` to TRUE, so
  this is easy to hit) would model every run against samples from all of them.
  The second check fires only where a measurement has >1 run — one run plus a
  run-less input function is the same acquisition
- Subsetting by `run` is impossible once merged (`run` is all `NA`);
  `describe_available_values()` says why
- The app's checkbox is rendered only when `dataset_has_multiple_runs()` is
  `TRUE`. Its absence is the answer, not a missing one: `isTRUE(input$merge_runs)`
  is `FALSE`, which is correct — nothing was merged

### Config File Gotchas
- When `FitDelay.model` is `"Set to zero..."`, delay step is skipped but model reports independently load blood data from raw BIDS `_blood.tsv` files (via `determine_blood_source()`) and default `inpshift` to 0
- Reference region must be included in `Subsetting.Regions` (e.g., if `ReferenceTAC.region` is `"Cerebellum"`, subsetting must include it)
- Templates read `config$ReferenceTAC$region` (not `reference_region`)

### Nested Models (shared parameters within each measurement)
- `nested2TCM` (plasma) fits all regions of a measurement jointly via `kinfitr::nested_2tcm()`. Config uses the **macro parameterisation** (`K1`, `Vnd`, `BPp`, `k4` limit objects), plus `shared` (`"Vnd"`, `"k4"`, or `"Vnd_k4"`), a fixed scalar `vB_value` (vB cannot be fitted), and `roiweights` (`"volume"` or `"equal"`)
- `nestedSRTM` (reference) fits via `kinfitr::nested_srtm()` with `R1`/`BPnd`/`k2prime` limit objects and `roiweights`; k2prime is always the shared parameter. Its kinpar output carries a `k2prime` column, so SRTM2/refLogan/MRTM2 `inherit_modelN_*` sources work on it
- `FitDelay.model` accepts `nested_1tcm`/`nested_2tcm`: one shared delay per measurement (no median step); output files use `model-nested1TCM`/`model-nested2TCM`
- Nested models require **at least 2 regions per measurement**: templates call `validate_min_regions_per_pet()` (R/validation.R), warn about and drop insufficient measurements, and error if none qualify
- Nested Shiny inputs are prefixed `nested_` (e.g. `nested_K1.start2`), including a separate `nested_multstart_iter` per model slot
- Nested fit objects hold an `optim` result in `$fit` (not `nls`): templates compute RSS from `$tacs` and skip AIC/BIC; the Interactive Sandbox rejects nested types

### Potential Bug: `fit_delay_report.Rmd`
`get_model_template()` in `report_generation.R` maps `"Fit Delay"` to `fit_delay_report.Rmd`, but only `delay_report.Rmd` exists in `inst/rmd/`. This may cause a runtime error if the "Fit Delay" model type is used.

## Troubleshooting

- **No TACs files found**: Files missing `seg` or `label` BIDS attributes
- **TACs/Morph mismatch**: Check case-sensitive match for `sub` and `seg`/`label`; missing morph uses volume=1 fallback
- **Column name issues**: Ensure using `readr::read_tsv()` and backticks for hyphenated names like `` `volume-mm3` ``
- **Report generation fails**: Check templates in `inst/rmd/`, verify `rmarkdown`/`knitr` installed

## Integration Testing

Tests use real PET data from OpenNeuro ds004869 (COX-2 PET, C-11 tracer). Disabled by default.

### Running Tests
```bash
# All integration tests
PETFIT_INTEGRATION_TESTS=true Rscript -e "devtools::test(filter = 'integration')"

# Single test file
PETFIT_INTEGRATION_TESTS=true Rscript -e "devtools::test(filter = 'integration-regiondef')"

# With container tests
PETFIT_INTEGRATION_TESTS=true PETFIT_DOCKER_TESTS=true Rscript -e "devtools::test(filter = 'integration')"
PETFIT_INTEGRATION_TESTS=true PETFIT_APPTAINER_TESTS=true Rscript -e "devtools::test(filter = 'integration')"

# Persistent cache (avoids re-extracting tarball)
PETFIT_INTEGRATION_TESTS=true PETFIT_INTEGRATION_CACHE=/tmp/petfit_cache Rscript -e "devtools::test(filter = 'integration')"
```

### Environment Variables

| Variable | Purpose |
|---|---|
| `PETFIT_INTEGRATION_TESTS=true` | Enable R-native integration tests |
| `PETFIT_TESTDATA_PATH` | Explicit path to `ds004869_testdata.tar.gz` |
| `PETFIT_INTEGRATION_CACHE` | Persistent cache directory for extracted data |
| `PETFIT_DOCKER_TESTS=true` | Enable Docker container tests |
| `PETFIT_DOCKER_BUILD=true` | Rebuild Docker image before testing |
| `PETFIT_APPTAINER_TESTS=true` | Enable Apptainer tests |
| `PETFIT_APPTAINER_SIF` | Explicit path to `.sif` container file |

### Test Data
The tarball (`ds004869_testdata.tar.gz`, ~2.7 MB) is in `tests/testthat/fixtures/integration/`. Contains real TSV/JSON with NIfTI placeholders. At test time, `ensure_testdata()` extracts it automatically.

To regenerate: `cd tests/testthat/fixtures/integration && bash prepare_testdata.sh` (requires datalad)

### Adding New Config Fixtures
1. Create JSON config in `tests/testthat/fixtures/integration/` (copy existing)
2. Create test file using template in `tests/README.md`
3. Run with `PETFIT_INTEGRATION_TESTS=true Rscript -e "devtools::test(filter = 'integration-modelling-<name>')"`
