# Plan: Ancillary Analysis Folder Feature

## Context

Users with many small brain regions get poor delay/k2prime estimates because the median is polluted by bad fits from tiny regions. The solution: run a quick "ancillary" analysis on a subset of high-quality regions to estimate delay/k2prime, then run the full analysis inheriting those values. This avoids fitting 50+ regions just to get a shared parameter.

## Design Decisions (from user)

- **Name**: "ancillary analysis folder" (not "reference" — avoids confusion with reference regions)
- **Pipelines**: Both plasma (delay) and reference tissue (k2prime)
- **Argument-driven**: `ancillary_analysis_folder` function argument; NOT a UI folder picker
- **UI integration**: New options in EXISTING dropdowns, hidden when no ancillary folder provided
- **Sibling folders only**: Must be under same `derivatives/petfit/` directory
- **Config encoding**: Source strings like `"ancillary_estimate"`, `"ancillary_model1_median"` — folder path NOT in config
- **Validation**: Console message at startup (not Shiny notification)
- **Full analysis includes all regions** (subset regions not excluded)

## Files to Modify

### 1. `R/launch_apps.R` — Add argument
- Add `ancillary_analysis_folder = NULL` to `launch_petfit_apps()`
- Validate it's a sibling subfolder name (not a full path)
- Pass through to `modelling_plasma_app()` and `modelling_ref_app()`

### 2. `R/modelling_plasma_app.R` — Plasma app changes
- Add `ancillary_analysis_folder` parameter to `modelling_plasma_app()`
- **Startup validation**: Resolve ancillary path (`{petfit_dir}/{ancillary_analysis_folder}/`), scan for available files, print console summary via `message()`
- **Delay dropdown**: Add `"Inherit from ancillary analysis folder"` option to delay model choices (only when ancillary provided)
  - Config value: `"ancillary_estimate"`
  - UI: Use `updateSelectInput()` on startup to add the option if ancillary is available
- **Delay step execution**: When `model == "ancillary_estimate"`, skip delay report generation; instead copy delay files from ancillary folder into current analysis folder (so model templates find them with existing glob patterns)
- **Config save/restore**: Handle `"ancillary_estimate"` in FitDelay.model; error on restore if ancillary not provided

### 3. `R/modelling_ref_app.R` — Reference tissue app changes
- Same `ancillary_analysis_folder` parameter
- **k2prime dropdowns** for all 3 models (Models 1, 2, and 3): Add ancillary options
  - New options: `"ancillary_model1_mean"`, `"ancillary_model1_median"`, `"ancillary_model2_mean"`, `"ancillary_model2_median"`, `"ancillary_model3_mean"`, `"ancillary_model3_median"` (no regional — ancillary has different regions than full analysis)
  - Only shown when ancillary folder is provided
- **Startup validation**: Same console summary

### 4. `R/ancillary_utils.R` — NEW file for ancillary utilities
- `validate_ancillary_folder(petfit_dir, ancillary_analysis_folder)` — checks folder exists, is sibling
- `scan_ancillary_contents(ancillary_path)` — returns list of what's available:
  - `delay_files`: list of PET IDs with delay kinpar files
  - `model1_kinpar`: list of PET IDs with model1 kinpar files (+ model type)
  - `model2_kinpar`: same for model2
  - `model3_kinpar`: same for model3
- `print_ancillary_summary(scan_result)` — formatted console message
- `read_ancillary_delay(ancillary_path, pet_ids)` — reads delay files, returns tibble with pet + blood_timeshift
- `read_ancillary_k2prime(ancillary_path, model_num, aggregation, pet_ids)` — reads kinpar files, applies aggregation (mean/median per PET measurement), returns single k2prime value per PET
- `parse_ancillary_k2prime_source(source_string)` — parses `"ancillary_model1_median"` → list(model="model1", aggregation="median")
- `get_ancillary_dropdown_options(scan_result, parameter_type)` — returns named vector of available dropdown options based on what's actually in the ancillary folder

### 5. `R/pipeline_core.R` — Step execution changes
- `execute_delay_step()`: When config model is `"ancillary_estimate"`, skip report generation. Instead, use `read_ancillary_delay()` to copy delay files into current analysis folder (so model templates can find them with existing glob patterns)
- `execute_model_step()`: Pass `ancillary_analysis_folder` through to report params when k2prime_source starts with `"ancillary_"`

### 6. `R/docker_functions.R` — Auto pipeline
- Add `ancillary_analysis_folder = NULL` to `petfit_modelling_auto()`
- Resolve to full path: `{petfit_dir}/{ancillary_analysis_folder}/`
- Validate at startup, print console summary
- Pass to step execution functions
- Error if config references ancillary but arg is NULL

### 7. `R/report_generation.R` — Report generation
- `generate_delay_report()`: No changes needed (copy files approach)
- `generate_model_report()`: Pass `ancillary_analysis_folder` as a param to Rmd templates that need k2prime

### 8. `inst/rmd/delay_report.Rmd` — Delay template
- **No changes needed** — delay step copies ancillary delay files into current analysis folder, so this template is simply not called when inheriting

### 9. `inst/rmd/mrtm2_report.Rmd` — MRTM2 template (k2prime consumer)
- Extend k2prime loading logic to handle `"ancillary_*"` sources
- Parse source string to get model number + aggregation
- Read kinpar files from `ancillary_analysis_folder` param (passed as Rmd param)
- Apply mean/median aggregation (no regional for ancillary — different region sets)
- Display source info in report output

### 10. `inst/rmd/reflogan_report.Rmd` — refLogan template (k2prime consumer)
- Same changes as mrtm2_report.Rmd

### 11. `inst/rmd/srtm2_report.Rmd` — SRTM2 template (k2prime consumer)
- Same changes as mrtm2_report.Rmd

## Implementation Strategy

### Delay: Copy files into current analysis folder

For delay inheritance (`"ancillary_estimate"`), **copy the delay kinpar files** from the ancillary folder into the current analysis folder during the delay step:
- Model report templates need **zero changes** for delay loading (they already glob for `*_desc-delayfit_kinpar.tsv`)
- The delay step becomes: "copy files from ancillary" instead of "run delay estimation"
- A simple provenance report can be generated showing where the values came from

### k2prime: Pass ancillary path to Rmd templates

For k2prime, pass the ancillary folder path as an Rmd parameter. The template's k2prime loading section already parses source strings — extend it to handle `"ancillary_*"` patterns by reading from the ancillary path instead of the current analysis folder.

## Config JSON Examples

### Plasma config with ancillary delay:
```json
{
  "FitDelay": {
    "model": "ancillary_estimate"
  }
}
```

### Reference config with ancillary k2prime:
```json
{
  "Models": {
    "Model1": {
      "type": "MRTM2",
      "k2prime_source": "ancillary_model1_median",
      "k2prime": 0.1
    }
  }
}
```

Note: `k2prime` field still holds a fallback/display value. The `k2prime_source` determines the actual source.

## Dropdown Options

### Delay model dropdown (plasma app):
Existing options plus:
- `"Inherit from ancillary analysis folder"` → config value: `"ancillary_estimate"`

### k2prime source dropdown (ref app, per model):
Existing options plus (only showing models that exist in ancillary):
- `"Ancillary: Model 1 (mean)"` → `"ancillary_model1_mean"`
- `"Ancillary: Model 1 (median)"` → `"ancillary_model1_median"`
- `"Ancillary: Model 2 (mean)"` → `"ancillary_model2_mean"`
- `"Ancillary: Model 2 (median)"` → `"ancillary_model2_median"`
- `"Ancillary: Model 3 (mean)"` → `"ancillary_model3_mean"`
- `"Ancillary: Model 3 (median)"` → `"ancillary_model3_median"`

No "regional" option for ancillary — the ancillary folder has a different region set, so per-region k2prime values wouldn't map to the full analysis regions. Only PET-wide aggregates (mean/median across the ancillary's regions) make sense.

Only options where the ancillary folder actually has the corresponding kinpar files are shown.

## Edge Cases

1. **PET ID mismatch**: Ancillary has sub-01, sub-02; full analysis has sub-01 through sub-10. PET IDs not found in ancillary get delay=0 with a warning.
2. **Ancillary folder incomplete**: User selects ancillary k2prime from Model 2 but Model 2 wasn't run. Caught at startup scan — option not shown in dropdown.
3. **Config references ancillary but arg not provided**: Error at app startup / auto pipeline startup with clear message.
4. **Config restore with ancillary**: If restoring config that has `"ancillary_estimate"` but no ancillary folder provided, show error and reset to default.
5. **Ancillary folder deleted after config saved**: Validate at step execution time too, not just startup.

## Implementation Order

1. **`R/ancillary_utils.R`** — New utility functions (foundation)
2. **`R/launch_apps.R`** — Add argument threading
3. **`R/modelling_plasma_app.R`** — Delay dropdown + ancillary support
4. **`R/modelling_ref_app.R`** — k2prime dropdown + ancillary support
5. **`R/pipeline_core.R`** — Step execution with ancillary
6. **`R/docker_functions.R`** — Auto pipeline argument
7. **`inst/rmd/mrtm2_report.Rmd`** — k2prime from ancillary
8. **`inst/rmd/reflogan_report.Rmd`** — k2prime from ancillary
9. **`inst/rmd/srtm2_report.Rmd`** — k2prime from ancillary
10. **`R/report_generation.R`** — Pass ancillary param to reports
11. **Tests** — Unit tests for ancillary_utils, integration test with two-folder workflow

## Verification

1. **Unit tests**: Test `parse_ancillary_k2prime_source()`, `validate_ancillary_folder()`, `read_ancillary_delay()`, `read_ancillary_k2prime()`
2. **Manual Shiny test**: Launch plasma app with ancillary folder, verify dropdown shows `"ancillary_estimate"` option, verify delay file copying works
3. **Manual Shiny test**: Launch ref app with ancillary folder, verify k2prime dropdown shows ancillary options for all three models
4. **Auto pipeline test**: Run `petfit_modelling_auto()` with ancillary argument, verify it reads delay/k2prime correctly
5. **Integration test**: Create a two-folder workflow fixture — ancillary config with 2 regions, full config with all regions pointing at ancillary
