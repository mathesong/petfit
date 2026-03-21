# API reference

This page documents PETFit's exported R functions, organised by functional area.

## App launchers

### `petfit_interactive()`

Launch a PETFit Shiny app.

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
- `app` — Which app to launch: `"regiondef"`, `"modelling_plasma"`, or `"modelling_ref"`.
- `bids_dir` — Path to the BIDS directory.
- `derivatives_dir` — Path to derivatives directory. Defaults to `bids_dir/derivatives` if `bids_dir` is provided.
- `blood_dir` — Path to blood data directory (for `modelling_plasma`).
- `petfit_output_foldername` — Name of the petfit output folder within derivatives (default: `"petfit"`).
- `analysis_foldername` — Name of the analysis subfolder (default: `"Primary_Analysis"`).
- `config_file` — Path to an existing configuration file (for modelling apps).
- `cores` — Number of cores for parallel processing (default: `1L`).
- `save_logs` — Whether to save processing logs (default: `FALSE`).
- `ancillary_analysis_folder` — Name of a sibling analysis subfolder to inherit delay or k2prime estimates from. Must be a folder name (e.g. `"Ancillary_Analysis"`), not a full path.

### `region_definition_app()`

Launch the region definition app directly.

```r
region_definition_app(
  bids_dir = NULL,
  derivatives_dir = NULL,
  petfit_output_foldername = "petfit",
  cores = 1L
)
```

### `modelling_plasma_app()`

Launch the plasma input modelling app directly.

```r
modelling_plasma_app(
  bids_dir = NULL,
  derivatives_dir = NULL,
  blood_dir = NULL,
  analysis_foldername = "Primary_Analysis",
  config_file = NULL,
  cores = 1L,
  save_logs = FALSE,
  ancillary_analysis_folder = NULL
)
```

### `modelling_ref_app()`

Launch the reference tissue modelling app directly.

```r
modelling_ref_app(
  bids_dir = NULL,
  derivatives_dir = NULL,
  blood_dir = NULL,
  analysis_foldername = "Primary_Analysis",
  config_file = NULL,
  cores = 1L,
  save_logs = FALSE,
  ancillary_analysis_folder = NULL
)
```

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

Dispatches to `petfit_regiondef_auto()` or `petfit_modelling_auto()` based on the `app` parameter.

### `petfit_regiondef_auto()`

Run the region definition pipeline non-interactively.

```r
petfit_regiondef_auto(
  bids_dir = NULL,
  derivatives_dir = NULL,
  petfit_output_foldername = "petfit",
  cores = 1L
)
```

**Returns:** List with `success`, `messages`, and `output_file`.

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

**Arguments:**
- `step` — Run a specific step: `"datadef"`, `"weights"`, `"delay"`, `"reference_tac"`, `"model1"`, `"model2"`, `"model3"`. If `NULL`, runs all steps.
- `pipeline_type` — Explicit pipeline type: `"plasma"` or `"reference"`. If `NULL`, auto-detected from the configuration file.
- `ancillary_analysis_folder` — Name of a sibling analysis subfolder to inherit delay or k2prime estimates from.

## Pipeline step execution

### `execute_datadef_step()`

Execute the data definition step of the modelling pipeline.

### `execute_weights_step()`

Execute the weights calculation step.

### `execute_delay_step()`

Execute the delay fitting step (plasma input pipeline).

### `execute_reference_tac_step()`

Execute the reference TAC setup step (reference tissue pipeline).

### `execute_model_step()`

Execute a model fitting step.

## Region processing

### `create_petfit_combined_tacs()`

Create the combined TACs file from PET preprocessing derivatives.

### `create_petfit_regions_files()`

Create the `petfit_regions.tsv` file and combined TACs.

### `process_all_petfit_regions()`

Process all regions defined in the regions TSV file.

### `combine_regions_from_files()`

Combine multiple brain regions into a single TAC using volume-weighted averaging.

### `combine_single_region_tac()`

Combine a single region's TAC from constituent parts.

### `create_tacs_morph_mapping()`

Create a mapping between TAC files and their corresponding morphometry files using BIDS entity matching.

### `calculate_segmentation_mean_tac()`

Calculate the volume-weighted mean TAC across all regions within a segmentation.

### `get_region_volumes_from_morph()`

Read region volumes from a morphometry file. Falls back to volume = 1 if no morph file is found.

## BIDS utilities

### `extract_bids_attributes_from_filename()`

Parse BIDS entities (sub, ses, seg, label, etc.) from a filename.

### `interpret_bids_key_value_pairs()`

Interpret BIDS key-value pairs from a filename string.

### `get_pet_identifiers()`

Extract PET measurement identifiers from BIDS data.

### `determine_varying_attributes()`

Determine which BIDS attributes vary across a dataset.

### `find_tacs_folders()`

Find directories containing TAC files in a BIDS derivatives structure.

### `reconstruct_pet_column()`

Reconstruct the `pet` column from BIDS attributes.

## Data processing

### `subset_combined_tacs()`

Subset the combined TACs by BIDS entities and regions.

### `subset_tacs_by_frames()`

Subset TACs by frame timing (e.g. restrict to early frames).

### `create_individual_tacs_files()`

Create individual TAC files for each PET measurement.

### `cleanup_individual_tacs_files()`

Remove previously created individual TAC files.

### `load_participant_data()`

Load participant data from BIDS `participants.tsv` and `participants.json`.

### `extract_pet_metadata()`

Extract PET metadata (e.g. injected radioactivity) from BIDS JSON sidecars.

### `extract_pet_metadata_from_tacs_json()`

Extract PET metadata from TACs JSON description files.

## Report generation

### `generate_step_report()`

Generate an HTML report for a pipeline step (data definition, weights, delay).

### `generate_model_report()`

Generate an HTML report for a model fitting step with dynamic template selection.

### `generate_tstar_report()`

Generate an HTML report for t* finder analysis.

### `generate_reports_summary()`

Generate a summary page linking all reports for an analysis.

### `get_model_template()`

Map a model type name to its R Markdown template file.

## Blood data

### `get_blood_data_status()`

Check for blood data files and return detection status.

### `determine_blood_source()`

Determine the source of blood input data for model fitting.

### `validate_blood_requirements()`

Validate that required blood data is available.

### `blooddata2inputfunction_tsv()`

Convert raw blood data to input function TSV format.

## Ancillary analysis

### `validate_ancillary_folder()`

Validate that an ancillary analysis folder exists and is a sibling of the current analysis.

```r
validate_ancillary_folder(petfit_dir, ancillary_analysis_folder)
```

### `scan_ancillary_contents()`

Scan an ancillary analysis folder and return available delay and kinpar files.

```r
scan_ancillary_contents(ancillary_path)
```

### `print_ancillary_summary()`

Print a formatted summary of ancillary folder contents.

### `read_ancillary_delay()`

Read delay estimates (inpshift values) from an ancillary analysis folder.

```r
read_ancillary_delay(ancillary_path, pet_ids = NULL)
```

### `read_ancillary_k2prime()`

Read and aggregate k2prime values from ancillary kinpar files.

```r
read_ancillary_k2prime(ancillary_path, model_num, aggregation, pet_ids = NULL)
```

**Arguments:**
- `model_num` — Which model's kinpar files to read (1, 2, or 3).
- `aggregation` — How to aggregate k2prime across regions: `"mean"` or `"median"`.

### `parse_ancillary_k2prime_source()`

Parse an ancillary k2prime source string (e.g. `"ancillary_model1_median"`) into its components.

### `get_ancillary_delay_options()`

Get available delay options from an ancillary folder scan.

### `get_ancillary_k2prime_options()`

Get available k2prime options from an ancillary folder scan.

### `copy_ancillary_delay_files()`

Copy delay files from an ancillary folder into the current analysis.

## Validation

### `validate_directory_requirements()`

Validate that required directories exist and contain expected files.

### `coerce_bounds_numeric()`

Safely coerce model parameter bounds to numeric values.

## Utilities

### `parse_semicolon_values()`

Parse semicolon-separated strings into vectors.

### `summarise_tacs_descriptions()`

Summarise TAC descriptions from a combined TACs file.

### `attributes_to_title()`

Convert BIDS attributes to a human-readable title string.

### `determine_pipeline_type()`

Determine whether a configuration is for plasma input or reference tissue.

### `extract_pet_id_from_kinpar_filename()`

Extract the PET measurement ID from a kinpar output filename.

### `minify_dir()`

Create a minified copy of a BIDS directory for testing.
