# API reference

This page documents PETFit's main R functions for launching apps and running pipelines.

## Interactive apps

### `petfit_interactive()`

Launch a PETFit Shiny app in your browser.

```r
petfit_interactive(
  app = c("regiondef", "modelling_plasma", "modelling_ref"),
  bids_dir = NULL,
  derivatives_dir = NULL,
  blood_dir = NULL,
  petfit_output_foldername = "petfit",
  analysis_foldername = "Primary_Analysis",
  config_file = NULL,
  cores = 1L,
  save_logs = FALSE,
  ancillary_analysis_folder = NULL
)
```

**Arguments:**

| Argument | Description |
|----------|-------------|
| `app` | Which app to launch: `"regiondef"`, `"modelling_plasma"`, or `"modelling_ref"` |
| `bids_dir` | Path to the BIDS directory |
| `derivatives_dir` | Path to derivatives directory. Defaults to `bids_dir/derivatives` if `bids_dir` is provided |
| `blood_dir` | Path to blood data directory (for `modelling_plasma`) |
| `petfit_output_foldername` | Name of the petfit output folder within derivatives (default: `"petfit"`) |
| `analysis_foldername` | Name of the analysis subfolder (default: `"Primary_Analysis"`) |
| `config_file` | Path to an existing configuration file (for modelling apps) |
| `cores` | Number of cores for parallel processing (default: `1L`) |
| `save_logs` | Whether to save processing logs (default: `FALSE`) |
| `ancillary_analysis_folder` | Name of a sibling analysis subfolder to inherit delay or k2prime estimates from. Must be a folder name (e.g. `"Ancillary_Analysis"`), not a full path |

## Automatic pipelines

### `petfit_auto()`

Unified entry point for running any PETFit pipeline non-interactively.

```r
petfit_auto(
  app = c("regiondef", "modelling_plasma", "modelling_ref"),
  bids_dir = NULL,
  derivatives_dir = NULL,
  blood_dir = NULL,
  petfit_output_foldername = "petfit",
  analysis_foldername = "Primary_Analysis",
  step = NULL,
  cores = 1L,
  save_logs = FALSE,
  ancillary_analysis_folder = NULL
)
```

Dispatches to `petfit_regiondef_auto()` or `petfit_modelling_auto()` based on `app`.

### `petfit_regiondef_auto()`

Run region definition non-interactively.

```r
petfit_regiondef_auto(
  bids_dir = NULL,
  derivatives_dir = NULL,
  petfit_output_foldername = "petfit",
  cores = 1L
)
```

### `petfit_modelling_auto()`

Run the modelling pipeline non-interactively.

```r
petfit_modelling_auto(
  bids_dir = NULL,
  derivatives_dir = NULL,
  petfit_output_foldername = "petfit",
  analysis_foldername = "Primary_Analysis",
  blood_dir = NULL,
  step = NULL,
  pipeline_type = NULL,
  cores = 1L,
  save_logs = FALSE,
  ancillary_analysis_folder = NULL
)
```

| Argument | Description |
|----------|-------------|
| `step` | Run a specific step: `"datadef"`, `"weights"`, `"delay"`, `"reference_tac"`, `"model1"`, `"model2"`, `"model3"`. If `NULL`, runs all steps |
| `pipeline_type` | Explicit pipeline type: `"plasma"` or `"reference"`. If `NULL`, auto-detected from the configuration file |
| `ancillary_analysis_folder` | Name of a sibling analysis subfolder to inherit delay or k2prime estimates from |

All other arguments are the same as `petfit_interactive()`.

## Container command-line options

When running PETFit in Docker or Apptainer, the container accepts these flags:

| Flag | Description |
|------|-------------|
| `--func` | App to run: `regiondef`, `modelling_plasma`, or `modelling_ref` (required) |
| `--mode` | `interactive` (default) or `automatic` |
| `--step` | Specific step for automatic mode (see `petfit_modelling_auto()` above) |
| `--analysis_foldername` | Analysis subfolder name (default: `Primary_Analysis`) |
| `--petfit_output_foldername` | Name of petfit output folder within derivatives (default: `petfit`) |
| `--cores` | Number of cores for parallel processing (default: `1`) |
