# Repository Guidelines

## Project Structure & Module Organization
Core Shiny logic lives in `R/`, where `modelling_app.R` and `region_definition_app.R` orchestrate workflows and helpers (for example `bids_utils.R`, `report_generation.R`) handle BIDS parsing and report creation. Combined TACs, configs, and analysis artifacts land under `{derivatives}/petfit/` with per-analysis subfolders (default `Primary_Analysis`), while the apps read auxiliary configs from `{bids}/code/petfit/`. Static assets stay in `www/`, parameterised Rmd templates in `inst/rmd/`, and container tooling under `docker/` and `singularity/`. Tests are organised in `tests/testthat`. Kinetic model fitting is delegated to the upstream `kinfitr` package.

## Build, Test, and Development Commands
Run `Rscript -e "devtools::load_all()"` to bootstrap the package for iterative development or debugging. Launch both Shiny apps with `Rscript -e "petfit::launch_apps(bids_dir='...')"` or individually via `region_definition_app()` / `modelling_app()`. Execute `Rscript -e "devtools::test()"` for unit tests and `Rscript -e "devtools::check()"` before release candidates; both should pass using the sample derivatives. Container verification happens through `bash docker/build_and_push.sh`, `docker compose up` in `docker/`, or the Singularity scripts in `singularity/` for HPC parity. Non-interactive processing uses Docker `--mode automatic` or the corresponding Singularity wrappers.

## Coding Style & Naming Conventions
Follow tidyverse conventions: two-space indents, `snake_case` function and object names, and descriptive Shiny reactive IDs prefixed by their domain (for example `region_upload_*`). Exported functions need roxygen2 blocks mirroring existing headers; regenerate documentation with `Rscript -e "devtools::document()"`. Prefer tidyverse helpers (`stringr`, `purrr`, `glue`) over ad-hoc utilities, keep UI modules grouped within `R/ui_modules.R`, and when extending Plotly reports wrap lists with `htmltools::tagList()` and set dimensions via `layout(width=..., height=...)`.

## Testing Guidelines
All tests use `testthat` (edition 3); add new specs under `tests/testthat/test-<feature>.R` with clear arrange/act/assert sections. Focus coverage on deterministic helpers (`bids_utils.R`, `validation.R`) and use temporary directories (`tempdir()`) when touching filesystem logic. Exercise Shiny modules through their server functions, and when reports drive computation, render the relevant Rmd with `rmarkdown::render()` against fixture data to catch template regressions.

## Commit & Pull Request Guidelines
Commit history favors concise, sentence-case summaries (examples include “Updated title of README” and “add build and push script”); follow that style and keep each change focused. Reference issues or tasks inline (e.g. `#123`) and include a brief rationale in the commit body when behavior changes. Pull requests should describe motivation, list verification commands executed (tests, Docker build), and attach UI screenshots when modifying layouts or theming; call out new configuration fields or migration steps.

## Deployment & Configuration Tips
Generated configuration files land in `{derivatives}/petfit/{analysis}/` (for example `desc-petfitoptions_config.json` and `reports/`); avoid committing participant data and scrub absolute paths before sharing. Ensure combined TACs (`desc-combinedregions_tacs.tsv`) stay synced between region-definition runs and modelling runs. When updating container flows, mirror changes in `docker/run_petfit.R` and the Singularity scripts to preserve feature parity, and document required environment variables or volume mappings near the affected scripts so operators can reproduce runs without guesswork.

## Reporting & Automation Workflow
Report templates in `inst/rmd/` drive the heavy lifting for data definition, weights, delay, and model fitting; extend them using the dynamic mapping helpers in `R/report_generation.R`. Keep output filenames consistent (`model1_report.html`, `data_definition_report.html`) to match the app’s expectations. Provide user-friendly notifications (use `showNotification()` / `removeNotification()`) around long-running report generation and prefer `code_folding: hide` plus timestamps within YAML headers to maintain reproducibility.
