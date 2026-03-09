# Issues Found During Integration Testing

These issues were discovered during integration testing with real ds004869 data.

Test results: `[ FAIL 0 | WARN 56 | SKIP 10 | PASS 157 ]`

---

## Warnings to Fix

The 56 warnings come from two root causes, both in `create_petfit_regions_files()` in `R/region_utils.R`. Every test that calls `petfit_regiondef_auto()` triggers both warnings, and since most tests need regiondef as a prerequisite, they accumulate across the suite.

### Warning 1: Deprecated `cur_data()` (dplyr 1.1.0+)

**Status**: Unfixed
**File**: `R/region_utils.R:184-196`
**Occurrences**: ~26 (2 per `dplyr::mutate()` call, across 13 test contexts)

**Message**:
```
`cur_data()` was deprecated in dplyr 1.1.0.
Please use `pick()` instead.
```

**Root cause**: The `create_petfit_regions_files()` function uses `dplyr::cur_data()` twice at line 193-194 to access the current data frame inside a `mutate()` call:

```r
all_mappings <- all_mappings %>%
  dplyr::mutate(
    description = create_bids_key_value_pairs(
      dplyr::cur_data(),
      setdiff(colnames(dplyr::cur_data()), c("tacs_path", "morph_path", ...))
    )$description
  )
```

**Fix**: Replace `cur_data()` with `pick(everything())` (the dplyr 1.1.0+ equivalent).

---

### Warning 2: Many-to-many join relationship

**Status**: Unfixed
**File**: `R/region_utils.R:199-203`
**Occurrences**: ~26 (1 per `inner_join()` call, across 13 test contexts)

**Message**:
```
Detected an unexpected many-to-many relationship between `x` and `y`.
Row 1 of `x` matches multiple rows in `y`.
Row 1 of `y` matches multiple rows in `x`.
If a many-to-many relationship is expected, set `relationship = "many-to-many"` to silence this warning.
```

**Root cause**: The `inner_join()` at line 199 joins `regions_config` with `all_mappings` by `c("folder", "description")`. Multiple rows in `regions_config` can share the same `folder`/`description` pair (different regions from the same segmentation), and multiple rows in `all_mappings` can also share the same pair (different subjects/sessions). This many-to-many relationship is **intentional** — it's how one region definition maps to multiple subject files.

```r
regions_files <- regions_config %>%
  dplyr::inner_join(
    all_mappings %>% dplyr::select(folder, description, tacs_filename, morph_filename),
    by = c("folder", "description")
  )
```

**Fix**: Add `relationship = "many-to-many"` to the `inner_join()` call to explicitly declare that this is expected behaviour and silence the warning.

---

### Warning 3: `system2()` non-zero exit codes in Singularity validation tests

**Status**: Unfixed — cosmetic only
**File**: `tests/testthat/test-integration-singularity.R:128-153`
**Occurrences**: 4

**Message**:
```
running command ''bash' ../../singularity/run-automatic.sh --derivatives-dir /tmp --step invalid 2>&1' had status 1
```

**Root cause**: The Singularity validation tests intentionally pass invalid arguments to shell scripts to verify they reject bad input. The scripts correctly exit with status 1, but `system2()` generates a warning about the non-zero exit code.

**Fix**: Wrap the `system2()` calls in `suppressWarnings()` since the non-zero exit is the expected behaviour being tested.

---

## Resolved Issues (for reference)

### Issue 1: `petfit_regiondef_auto()` crashes — return value used as file path

**Status**: Fixed (committed on `add_full_tests` branch)
**File**: `R/docker_functions.R:231`

`create_petfit_regions_files()` returns a data frame, not a path. The return value was being passed to `create_petfit_combined_tacs()` which expects a file path. Fix: construct the path explicitly instead of using the return value.

### Issue 2: `execute_model_step()` crashes on "No Model" model slots

**Status**: Fixed (committed on `add_full_tests` branch)
**File**: `R/pipeline_core.R:405`

When a model slot is set to "No Model", `execute_model_step()` tried to generate a report for it. Fix: add an early return that skips "No Model" slots gracefully.

### Issue 3: Plasma model fitting when delay is set to "no delay" — NOT A BUG

**Status**: Not a bug

When `FitDelay.model` is "Set to zero...", the delay step skips creating `_inputfunction.tsv` files. However, all 7 plasma model report templates (`1tcm`, `2tcm`, `2tcmirr`, `logan`, `ma1`, `patlak`, plus `delay`) have a 3-path blood data fallback that creates `_inputfunction.tsv` files on-the-fly from raw BIDS `_blood.tsv` data. The `bids_dir` parameter is passed through the entire call chain, and the "Loading Delay Information" section handles missing delay files by defaulting `inpshift = 0`. See `test-integration-bug-regressions.R` for verification.

### Issue 4: Single-subject report generation fails — n_distinct drops BIDS columns

**Status**: Fixed (committed on `add_full_tests` branch)
**Files**: All 11 model report templates in `inst/rmd/` (3 occurrences each, 33 edits total)

In all model report templates, `par_table`, `par_se_table`, and `gof_table` were created with `select(where(~ n_distinct(.x) > 1))` to remove constant columns for cleaner display tables. For single-subject runs, this removed all BIDS identifier columns (`sub`, `ses`, `trc`, `rec`, `task`, `run`, `pet`) since they each had only one unique value. The downstream `inner_join(folder_data)` then failed with `"by must be supplied when x and y have no common variables"` because the join keys had been removed.

**Error message**: `Failed to generate MRTM2 report for Model 1: 'by' must be supplied when 'x' and 'y' have no common variables.`

**Fix**: Moved `select(where(~ n_distinct(.x) > 1))` from the data creation pipeline to the display-only pipeline (before `DT::datatable()`). This preserves BIDS columns in the underlying data for joins while still showing clean tables in reports.

**Affected templates**: `1tcm_report.Rmd`, `2tcm_report.Rmd`, `2tcmirr_report.Rmd`, `logan_report.Rmd`, `ma1_report.Rmd`, `patlak_report.Rmd`, `srtm_report.Rmd`, `srtm2_report.Rmd`, `mrtm1_report.Rmd`, `mrtm2_report.Rmd`, `reflogan_report.Rmd`
