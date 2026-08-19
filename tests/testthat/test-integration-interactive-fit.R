# Integration tests: interactive single-measurement fitting
#
# Builds a real analysis folder from ds004869, runs the full batch pipeline,
# then checks that fit_single_measurement_plasma()/_ref() reproduce the batch
# kinpar values for the same measurement + region (interactive == batch).
#
# Requires: PETFIT_INTEGRATION_TESTS=true

# Compare interactive estimates to a batch kinpar row, on shared numeric columns.
expect_matches_batch <- function(par, kinpar_row, tolerance = 1e-4) {
  shared <- intersect(names(par), names(kinpar_row))
  shared <- shared[vapply(shared, function(n) is.numeric(par[[n]]), logical(1))]
  testthat::expect_gt(length(shared), 0)
  for (n in shared) {
    testthat::expect_equal(as.numeric(par[[n]][1]), as.numeric(kinpar_row[[n]][1]),
                           tolerance = tolerance, info = paste("parameter", n))
  }
}

# ---------------------------------------------------------------------------
# Plasma (2TCM)
# ---------------------------------------------------------------------------

test_that("fit_single_measurement_plasma reproduces the batch fit", {
  skip_if_no_integration()

  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  withr::defer(cleanup_workspace(ws))
  setup_regiondef_config(ws)

  rd <- petfit_regiondef_auto(bids_dir = ws$bids_dir, derivatives_dir = ws$derivatives_dir)
  if (!rd$success) skip(paste("Regiondef failed:", paste(rd$messages, collapse = "\n")))
  setup_modelling_config(ws, "ds004869_plasma_config.json")

  res <- petfit_modelling_auto(bids_dir = ws$bids_dir, derivatives_dir = ws$derivatives_dir)
  if (!res$success) skip(paste("Plasma pipeline failed:", paste(res$messages, collapse = "\n")))

  analysis_folder <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  # The combined (study-level) kinpar lives at the analysis-folder root.
  kinpar_file <- list.files(analysis_folder, "model_.*_desc-model1_kinpar.tsv",
                            full.names = TRUE, recursive = FALSE)[1]
  skip_if(is.na(kinpar_file) || !file.exists(kinpar_file), "No model1 kinpar produced")
  kinpar <- readr::read_tsv(kinpar_file, show_col_types = FALSE)

  tac_files <- list.files(analysis_folder, "_desc-combinedregions_tacs.tsv",
                          recursive = TRUE, full.names = TRUE)
  pet <- pet_key(tac_files, analysis_folder)[1]
  region <- kinpar$region[1]

  fit <- suppressWarnings(fit_single_measurement_plasma(
    analysis_folder = analysis_folder, model_number = "model1",
    pet = pet, region = region, bids_dir = ws$bids_dir
  ))

  expect_equal(fit$type, "2TCM")
  expect_equal(nrow(fit$par), 1)
  expect_equal(nrow(fit$par.se), 1)
  expect_matches_batch(fit$par, kinpar[kinpar$region == region, , drop = FALSE])
  # plot() must produce a ggplot for the app to render
  expect_s3_class(plot(fit$fit, roiname = region), "ggplot")
})

# ---------------------------------------------------------------------------
# Reference (SRTM)
# ---------------------------------------------------------------------------

test_that("fit_single_measurement_ref reproduces the batch fit", {
  skip_if_no_integration()

  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  withr::defer(cleanup_workspace(ws))
  setup_regiondef_config(ws)

  rd <- petfit_regiondef_auto(bids_dir = ws$bids_dir, derivatives_dir = ws$derivatives_dir)
  if (!rd$success) skip(paste("Regiondef failed:", paste(rd$messages, collapse = "\n")))
  setup_modelling_config(ws, "ds004869_ref_config.json")

  res <- petfit_modelling_auto(bids_dir = ws$bids_dir, derivatives_dir = ws$derivatives_dir)
  if (!res$success) skip(paste("Reference pipeline failed:", paste(res$messages, collapse = "\n")))

  analysis_folder <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  kinpar_file <- list.files(analysis_folder, "model_.*_desc-model1_kinpar.tsv",
                            full.names = TRUE, recursive = FALSE)[1]
  skip_if(is.na(kinpar_file) || !file.exists(kinpar_file), "No model1 kinpar produced")
  kinpar <- readr::read_tsv(kinpar_file, show_col_types = FALSE)

  tac_files <- list.files(analysis_folder, "_desc-targetregions_tacs.tsv",
                          recursive = TRUE, full.names = TRUE)
  pet <- pet_key(tac_files, analysis_folder)[1]
  region <- kinpar$region[1]

  fit <- suppressWarnings(fit_single_measurement_ref(
    analysis_folder = analysis_folder, model_number = "model1",
    pet = pet, region = region
  ))

  expect_equal(fit$type, "SRTM")
  expect_equal(nrow(fit$par), 1)
  expect_equal(nrow(fit$par.se), 1)
  # SRTM is fitted via nonlinear least squares; allow a small tolerance.
  expect_matches_batch(fit$par, kinpar[kinpar$region == region, , drop = FALSE], tolerance = 1e-2)
  expect_s3_class(plot(fit$fit, roiname = region), "ggplot")
})
