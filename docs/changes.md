# Changelog

## 0.1.3 (current)

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
- Docker and Singularity container support
- Parameterised HTML reports for quality control
- Interactive data exploration tabs in modelling apps
