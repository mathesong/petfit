# Bugs Found During Integration Testing

These bugs were discovered during integration testing with real ds004869 data.
Issues 1 and 2 are fixed (unstaged changes on the `add_full_tests` branch, ready to commit).
Issue 3 is an unfixed design issue that needs a proper solution.

Regression tests for all three issues are in `tests/testthat/test-integration-bug-regressions.R`.

---

## Issue 1: `petfit_regiondef_auto()` crashes — return value used as file path

**Status**: Fixed (unstaged change in `R/docker_functions.R`, not yet committed)
**File**: `R/docker_functions.R:231`
**Severity**: Critical — regiondef automatic mode is completely broken
**Regression test**: "BUG REGRESSION: petfit_regiondef_auto succeeds with real data"

### Description

`petfit_regiondef_auto()` calls `create_petfit_regions_files()` and stores its return value in `petfit_regions_files_path`. However, `create_petfit_regions_files()` returns a **data frame** (the mapping table), not a file path. This data frame is then passed to `create_petfit_combined_tacs()` which calls `file.exists()` on it, causing the error:

```
Error: invalid 'file' argument
```

### Root Cause

In `R/docker_functions.R` around line 231:

```r
# This returns a data frame, NOT a path:
petfit_regions_files_path <- create_petfit_regions_files(petfit_regions_file, derivatives_dir)
```

Then later, `petfit_regions_files_path` (a data frame) is passed to `create_petfit_combined_tacs()` which expects a file path string and calls `file.exists()` on it.

### Fix

In `R/docker_functions.R`, change line 231 from:

```r
petfit_regions_files_path <- create_petfit_regions_files(petfit_regions_file, derivatives_dir)
```

To:

```r
create_petfit_regions_files(petfit_regions_file, derivatives_dir)
petfit_regions_files_path <- file.path(petfit_base_dir, "petfit_regions_files.tsv")
```

The function `create_petfit_regions_files()` writes the mapping file to `{petfit_base_dir}/petfit_regions_files.tsv` internally. We just need to construct that same path ourselves rather than using the return value.

### How to verify

```r
PETFIT_INTEGRATION_TESTS=true Rscript -e "devtools::test(filter = 'integration-bug-regressions')"
```

The test "BUG REGRESSION: petfit_regiondef_auto succeeds with real data" should pass after the fix.

---

## Issue 2: `execute_model_step()` crashes on "No Model" model slots

**Status**: Fixed (unstaged change in `R/pipeline_core.R`, not yet committed)
**File**: `R/pipeline_core.R:405`
**Severity**: Critical — any automatic pipeline run crashes if Model2 or Model3 is "No Model"
**Regression test**: "BUG REGRESSION: execute_model_step handles No Model gracefully"

### Description

When a model slot (Model1, Model2, or Model3) is set to `"No Model"` in the config, `execute_model_step()` still proceeds to call `generate_model_report()`, which calls `get_model_template("No Model")`. There is no template for "No Model", so report generation fails and the entire pipeline aborts.

This affects the full pipeline because the automatic mode iterates through all three model slots (model1, model2, model3) and stops on the first failure.

### Root Cause

In `R/pipeline_core.R`, the function `execute_model_step()` reads `model_type` from the config but never checks if it's `"No Model"` before calling `generate_model_report()`. The function `get_model_template()` in `R/report_generation.R` has no mapping for "No Model" and fails.

### Fix

In `R/pipeline_core.R`, add an early return in `execute_model_step()` after line 405 (after `model_type` is assigned), before the report generation call:

```r
model_type <- config$Models[[model_key]]$type

# Add this block:
if (model_type == "No Model") {
  result$success <- TRUE
  result$message <- paste("Model", model_num, "set to 'No Model' - skipping")
  notify(result$message, "message")
  return(result)
}
```

### How to verify

```r
PETFIT_INTEGRATION_TESTS=true Rscript -e "devtools::test(filter = 'integration-bug-regressions')"
```

The test "BUG REGRESSION: execute_model_step handles No Model gracefully" should pass after the fix.

---

## Issue 3: Plasma model fitting fails when delay is set to "no delay" — missing `_inputfunction.tsv` files

**Status**: NOT FIXED — requires design decision and implementation
**Severity**: Medium — any plasma config with "Set to zero" delay will fail at model fitting
**Regression test**: "BUG REGRESSION: plasma pipeline succeeds with delay set to zero"

### Description

When the `FitDelay.model` config field is set to `"Set to zero (i.e. no delay fitting to be performed)"`, the delay step is skipped entirely via an early return in `execute_delay_step()` (`R/pipeline_core.R:248`). This means no `_inputfunction.tsv` files are ever created from the raw `_blood.tsv` files.

However, the model report templates (e.g., `inst/rmd/2tcm_report.Rmd`) look for `_inputfunction.tsv` files to load blood input data. When these don't exist, model fitting fails with:

```
No inputfunction.tsv files found in blood_dir
```

### Blood data pipeline flow

1. Raw `_blood.tsv` files exist in the BIDS directory (e.g., `sub-01/ses-baseline/pet/sub-01_ses-baseline_recording-continuous_blood.tsv`)
2. The **delay report Rmd** (`inst/rmd/delay_report.Rmd`) reads raw blood files, processes them into input functions, writes `_inputfunction.tsv` files, and estimates delay
3. Model report Rmds (`inst/rmd/2tcm_report.Rmd`, etc.) load `_inputfunction.tsv` for fitting

If step 2 is skipped (delay = "Set to zero"), the `_inputfunction.tsv` files never get created, and step 3 fails.

### Key files involved

- `R/pipeline_core.R:246-252` — `execute_delay_step()` early return when delay is "none"/"Set to zero"
- `inst/rmd/delay_report.Rmd` — creates `_inputfunction.tsv` as a side effect of delay estimation
- `inst/rmd/2tcm_report.Rmd` (and other model Rmds) — expects `_inputfunction.tsv` to exist

### Recommended fix: Decouple input function creation from delay estimation

The creation of `_inputfunction.tsv` files should not depend on whether delay estimation is performed. The fix should:

1. **Extract the blood-to-inputfunction conversion** from `delay_report.Rmd` into a standalone function or a new pipeline step
2. **Always create `_inputfunction.tsv` files** for plasma input pipelines, regardless of delay settings
3. When delay is "Set to zero", create input functions with `inpshift = 0` (no time correction)
4. When delay is estimated, create input functions with the estimated `inpshift` value

This way "no delay" means "create input functions with zero delay correction" rather than "skip creating input functions entirely".

### Current workaround

Use `"1tcm_singletac"` (or another delay estimation method) instead of `"Set to zero..."` in plasma pipeline configs. This runs the delay Rmd, creates `_inputfunction.tsv` files, and model fitting works. The integration test configs (`ds004869_plasma_config.json`) use this workaround.

### How to verify once fixed

```r
PETFIT_INTEGRATION_TESTS=true Rscript -e "devtools::test(filter = 'integration-bug-regressions')"
```

The test "BUG REGRESSION: plasma pipeline succeeds with delay set to zero" should pass after the fix. This test creates a config with `FitDelay.model` set to `"Set to zero (i.e. no delay fitting to be performed)"` and runs the full plasma pipeline expecting success.

---

## Notes

These bugs were all discovered because the automatic mode functions (`petfit_regiondef_auto()`, `petfit_modelling_auto()`) had never been tested against real data before the integration test suite was created. Issues 1 and 2 are straightforward fixes. Issue 3 requires refactoring how blood data is processed in the pipeline.
