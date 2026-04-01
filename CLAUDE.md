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
- **Modelling App - Plasma Input** (`modelling_plasma_app.R`): Invasive models (1TCM, 2TCM, 2TCM_irr, Logan, MA1, Patlak) requiring blood data
- **Modelling App - Reference Tissue** (`modelling_ref_app.R`): Non-invasive models (SRTM, SRTM2, refLogan, MRTM1, MRTM2) using reference regions

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
- **Singularity/Apptainer**: HPC-compatible, scripts in `singularity/` folder

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
- `singularity/`: Singularity/Apptainer build and run scripts
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
- **Model reports**: `1tcm`, `2tcm`, `2tcmirr`, `logan`, `ma1`, `patlak`, `srtm`, `srtm2`, `reflogan`, `mrtm1`, `mrtm2`
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
- Dimensions: Set in `layout(width = 800, height = 500)` not CSS
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

### Config File Gotchas
- When `FitDelay.model` is `"Set to zero..."`, delay step is skipped but model reports independently load blood data from raw BIDS `_blood.tsv` files (via `determine_blood_source()`) and default `inpshift` to 0
- Reference region must be included in `Subsetting.Regions` (e.g., if `ReferenceTAC.region` is `"Cerebellum"`, subsetting must include it)
- Templates read `config$ReferenceTAC$region` (not `reference_region`)

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
PETFIT_INTEGRATION_TESTS=true PETFIT_SINGULARITY_TESTS=true Rscript -e "devtools::test(filter = 'integration')"

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
| `PETFIT_SINGULARITY_TESTS=true` | Enable Singularity/Apptainer tests |
| `PETFIT_SINGULARITY_SIF` | Explicit path to `.sif` container file |

### Test Data
The tarball (`ds004869_testdata.tar.gz`, ~2.7 MB) is in `tests/testthat/fixtures/integration/`. Contains real TSV/JSON with NIfTI placeholders. At test time, `ensure_testdata()` extracts it automatically.

To regenerate: `cd tests/testthat/fixtures/integration && bash prepare_testdata.sh` (requires datalad)

### Adding New Config Fixtures
1. Create JSON config in `tests/testthat/fixtures/integration/` (copy existing)
2. Create test file using template in `tests/README.md`
3. Run with `PETFIT_INTEGRATION_TESTS=true Rscript -e "devtools::test(filter = 'integration-modelling-<name>')"`
