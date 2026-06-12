# Changelog

## 0.1.5 (current)

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
