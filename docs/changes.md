# Changelog

For the full, detailed changelog, see [NEWS.md](https://github.com/mathesong/petfit/blob/main/NEWS.md) in the repository.

## 0.2.3 (current)

- **Runs of a single injection are merged by default.** Where a measurement was acquired as two scanning occasions from one injection (`run-01` and `run-02`, or `run-early` and `run-late`), its runs are now pooled into one measurement and fitted together, and the `run` entity is dropped from the outputs. Untick **Merge runs of the same measurement** in the region definition app, or pass `--no-merge-runs` / `--no_merge_runs` / `merge_runs = FALSE`, for datasets where each run is its own injection. Blood data is pooled to match when it comes from the raw BIDS `_blood.tsv` files; already-processed input functions must already be merged, and the reports say so rather than pairing a merged measurement with one run's blood curve. Runs are placed on one clock by their `TimeZero` difference, matching `bloodstream`'s rule; without a usable `TimeZero` (a derivatives-only run) the times are taken as already shared, and overlapping frames are an error either way. See [Merging runs](usage/region-definition.md#merging-runs)
- The default upper bound on BPnd is now 25, up from 5 in the reference tissue app and 15 in the report and sandbox fallbacks
- Fixed: the reference tissue app read an old config's `k2a` bounds into the `BPnd` fields, carrying a binding-potential ceiling of 0.5 that would peg every fit at the bound. The compatibility branch is removed; such configs now open with the current `BPnd` defaults
- Removed unreachable model branches from both modelling apps' config save and restore paths — reference tissue models (`refLogan`, `SRTM`, `MRTM1`, `MRTM2`) from the plasma input app and plasma models (`1TCM`, `2TCM`, `Logan`, `MA1`) from the reference tissue app — left over from before the two apps were split
- Fixed: deprecation warnings from ggplot2 (`guides(colour = FALSE)`) and plotly (plot dimensions in `layout()`) on every data definition and weights report
- Fixed: a pipeline folder holding TACs files but no morph files failed with `object 'seg' not found` and left the region definition app with no TACs files at all. Such a folder is now mapped to `NA` morph paths and combined with equal weighting
- Fixed: errors from dplyr and purrr pipelines reported the line that was running rather than the cause. `petfit_error_detail()` walks the condition chain, and the region definition app uses it
- **External config and regions files:** the CLI can now be pointed at a config file, or a `petfit_regions.tsv`, which lives outside the dataset — `--config-file` and `--regions-file` in the `petfit-docker` wrapper, `--config_file` and `--regions_file` on the container, `config_file` and `regions_file` in the R functions. The file is copied into the folder petfit reads it from, so the settings which produced a run are always stored beside its outputs, and supplying a config creates the analysis folder if it does not yet exist
- Fixed: the `config_file` argument of `petfit_interactive()` and the modelling apps was accepted and validated but never actually applied

## 0.2.2

- **New `SUVR` outcome, reporting both SUV and SUVR.** A reference-tissue outcome which integrates rather than fits: the target region's area under the TAC over a window, over the reference region's area over the same window. It needs no blood data, and the window is set under **TAC Subset Selection**. Thanks to @mnoergaard (#37)
- SUVR is always available; SUV is reported only when the injected radioactivity is known, falling back to an assumed 70 kg body weight — applied to every measurement so SUV means the same thing across the cohort, and stated as a warning in the reports
- **Units in the JSON sidecars:** every output sidecar now states its units in the BIDS data dictionary form, read from `desc-combinedregions_tacs.json` rather than asserted per report. `petfit_tac_units()` is the accessor
- Fixed: a dose with `InjectedRadioactivity` but no `InjectedRadioactivityUnits` was silently passed through untouched. It is now read as MBq, warning once per measurement
- **Reference TAC fixes**, all thanks to @mnoergaard (#38, #39): the configured spline degrees of freedom now actually reach the fit; a reference TAC which cannot be splined falls back to the raw TAC and says so; and spline-fitted TACs are plotted and saved on the PET frame timing
- Fixed: the analysis folder's own path was being read as BIDS entities when inheriting a delay, `vB` or k2prime, so a hyphenated directory could act as a join key and silently drop rows. The inherited file's `model` entity no longer follows it out either
- `k2a` now appears in the MRTM1 and MRTM2 parameter histograms
- Fixed: a saved TAC subset window was not restored in the reference tissue app, and a window was recorded even under a selection method of "None"

## 0.2.1

- New **nested models**, which fit all the regions of a PET measurement jointly and share the parameters that belong to the measurement rather than the region: `nested2TCM` (plasma input, sharing V<sub>ND</sub> and/or k4) and `nestedSRTM` (reference tissue, sharing k2prime). See [Nested models](models.md#nested-models)
- New **nested delay estimation** methods (`nested_1tcm`, `nested_2tcm`), estimating one shared delay per measurement instead of taking the median of independent per-region estimates
- Nested models require at least two regions per measurement; measurements with fewer are dropped with a warning
- **Behaviour change:** the delay step's "Regions for Multiple Regions Analysis" field now actually filters the regions it names. It was previously saved and displayed but never applied, so median-delay analyses ran on all regions regardless — configurations that set it will give different delay estimates on re-running
- Fixed the model-type fallback in pipeline-type detection, which did not recognise `2TCM_irr`, `Patlak` or `SRTM2`
- Requires kinfitr >= 0.9.4

## 0.2.0

- **Reproducibility:** all reports now set a fixed seed, so re-running an identical configuration reproduces it exactly, whatever `--cores` is set to. *This changes numerical output once*
- petfit records its version in saved configurations and in the combined TACs sidecar, and warns when inputs were written by an older version
- **Behaviour change:** weights are now computed within each measurement rather than across the whole analysis, so a subject's weights no longer depend on which other measurements are analysed alongside it. *This changes numerical results*
- **Behaviour change:** measurement identifiers are built from each measurement's own filename rather than from whichever entities vary across the cohort, so identity no longer depends on the cohort. Filenames from earlier versions may change on regeneration
- Subsetting values are validated: a value matching nothing in the data is an error naming it, rather than a silent filter to nothing. Commas are rejected, and a field can be prefixed with `-` to exclude rather than include
- Re-running data definition now clears the analysis folder's derived outputs, and refuses a folder that does not look like an analysis folder
- Cleanup no longer follows filesystem links, and a directory holding only hidden files is no longer treated as empty
- Model artifacts are named `model-2TCM` rather than `model_2TCM`, so the model is a readable BIDS entity
- Warnings raised while fitting now appear in the reports; other warnings reach the console or step log instead of being discarded
- Both containers set a UTF-8 locale explicitly

## 0.1.5

- New `petfit-docker` command-line wrapper: a BIDS-App-style CLI that builds the `docker run` command for you, published on PyPI (`pip install petfit-docker`)
- `--patch` option in the wrapper to run a local petfit checkout inside the container, for testing changes without rebuilding the image
- t\* finder and interactive-mode improvements: clearer t\* selection help text and styling, delay warnings, and improved interactive plot layout
- Interactive fitting fixes: `mean_combined` weights bug and `vB` default
- Modelling fixes: prerequisite warnings, frame/blood joins, and k2prime handling
- Major documentation overhaul: restructured Read the Docs site with quickstart, per-app usage guides, container/HPC guides, and troubleshooting

## 0.1.4

- Apptainer improvements: automatic selection of a free port, explicit `--bids_dir`/`--derivatives_dir`/`--blood_dir` path arguments (useful with HPC home auto-mounts), and more robust blood-data detection
- More robust region definition: matching now catches anatomical outputs across sessions
- Improved grabbing of derivatives data, with added integration tests
- Fixes to configuration and reference-tissue inheritance (delay/k2prime, `vB` limits)

## 0.1.3

- Ancillary analysis folder support for delay and k2prime inheritance
- Parallel execution support for automatic pipelines (`--cores` flag)
- API consistency improvements: renamed `launch_petfit_apps()` to `petfit_interactive()`, `analysis_subfolder` to `analysis_foldername`
- Added `petfit_output_foldername`, `config_file`, `cores`, `save_logs` parameters across app functions
- Docker CLI updated with `--petfit_output_foldername`, `--cores`, `--analysis_foldername` flags
- Expanded documentation with PETFit folder structures guide, testing guide, and troubleshooting page

## 0.1.2

- Initial Read the Docs documentation
- Region definition with BIDS entity matching
- Plasma input modelling pipeline (1TCM, 2TCM, 2TCM_irr, Logan, MA1, Patlak)
- Reference tissue modelling pipeline (SRTM, SRTM2, refLogan, MRTM1, MRTM2, refPatlak)
- Docker and Apptainer container support
- Parameterised HTML reports for quality control
- Interactive data exploration tabs in modelling apps
