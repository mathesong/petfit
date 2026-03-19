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

### Unit tests

```bash
Rscript -e "devtools::test()"
```

### Integration tests

Integration tests use real PET data from OpenNeuro ds004869 and are disabled by default:

```bash
# Run all integration tests
PETFIT_INTEGRATION_TESTS=true Rscript -e "devtools::test(filter = 'integration')"

# Run a specific integration test
PETFIT_INTEGRATION_TESTS=true Rscript -e "devtools::test(filter = 'integration-regiondef')"

# Include Docker container tests
PETFIT_INTEGRATION_TESTS=true PETFIT_DOCKER_TESTS=true Rscript -e "devtools::test(filter = 'integration')"

# Use a persistent cache to avoid re-extracting test data
PETFIT_INTEGRATION_TESTS=true PETFIT_INTEGRATION_CACHE=/tmp/petfit_cache Rscript -e "devtools::test(filter = 'integration')"
```

### Test data

The test data tarball (`ds004869_testdata.tar.gz`, ~2.7 MB) is committed in `tests/testthat/fixtures/integration/`. It contains real TSV/JSON files with NIfTI placeholders. The `ensure_testdata()` helper function extracts it at test time.

### Workspace isolation

Each integration test creates an isolated workspace via `create_integration_workspace()`, with symlinked source data and a writable derivatives directory. Workspaces are cleaned up automatically.

See `tests/README.md` for the full testing guide.

## Configuration management

When adding new features to the modelling apps, always ensure backward compatibility with existing JSON configuration files:

- Use null coalescing (`%||%`) when accessing new config properties
- Provide sensible defaults for missing sections
- Handle missing or invalid data gracefully
- Add UI update logic for any new input fields

## Building documentation

The documentation uses Sphinx with MyST (Markdown). To build locally:

```bash
pip install -r docs/requirements.txt
cd docs
make html
# Open _build/html/index.html in your browser
```

When making code changes, please update the relevant documentation pages as well.
