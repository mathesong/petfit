# Changelog

For the full, detailed changelog, see [NEWS.md](https://github.com/mathesong/petfit/blob/main/NEWS.md) in the repository.

## 0.2.1 (current)

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
