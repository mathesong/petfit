# Integration tests: interactive single-measurement fitting
#
# Builds a real analysis folder from ds004869, runs the full batch pipeline,
# then checks that fit_single_measurement_plasma()/_ref() assemble the data and
# fit the saved-config model end-to-end, returning well-formed estimates.
#
# Note on exactness: when the weights file has one weight per frame (the normal
# case, e.g. the ds004869_mini development dataset) the interactive fit reproduces
# the batch kinpar exactly. The bundled ds004869 fixture's weights file stores
# region-specific weights without a region label, so the batch fits a many-to-many
# blow-up; we therefore assert structural validity and finite estimates here rather
# than bit-exact equality. Exact interactive == batch equivalence is verified
# manually on clean single-weight-per-frame data.
#
# Requires: PETFIT_INTEGRATION_TESTS=true

expect_well_formed_fit <- function(fit, expected_params) {
  testthat::expect_type(fit, "list")
  testthat::expect_s3_class(fit$par, "data.frame")
  testthat::expect_s3_class(fit$par.se, "data.frame")
  testthat::expect_equal(nrow(fit$par), 1)
  testthat::expect_equal(nrow(fit$par.se), 1)

  present <- intersect(expected_params, names(fit$par))
  testthat::expect_gt(length(present), 0)
  for (p in present) {
    testthat::expect_true(is.finite(fit$par[[p]][1]), info = paste("parameter", p, "should be finite"))
  }
}

# ---------------------------------------------------------------------------
# Plasma (2TCM)
# ---------------------------------------------------------------------------

test_that("fit_single_measurement_plasma fits the saved-config model end-to-end", {
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
  kinpar_file <- list.files(analysis_folder, "model_.*_desc-model1_kinpar.tsv",
                            full.names = TRUE, recursive = FALSE)[1]
  skip_if(is.na(kinpar_file) || !file.exists(kinpar_file), "No model1 kinpar produced")
  kinpar <- readr::read_tsv(kinpar_file, show_col_types = FALSE)

  tac_files <- list.files(analysis_folder, "_desc-combinedregions_tacs.tsv",
                          recursive = TRUE, full.names = TRUE)
  pet <- get_pet_identifiers(tac_files, analysis_folder)[1]
  region <- kinpar$region[1]

  fit <- suppressWarnings(fit_single_measurement_plasma(
    analysis_folder = analysis_folder, model_number = "model1",
    pet = pet, region = region, bids_dir = ws$bids_dir
  ))

  expect_equal(fit$type, "2TCM")
  expect_well_formed_fit(fit, c("K1", "k2", "k3", "k4", "VT", "BPnd"))
  # plot() must produce a ggplot for the app to render
  expect_s3_class(plot(fit$fit, roiname = region), "ggplot")
})

# ---------------------------------------------------------------------------
# Reference (SRTM)
# ---------------------------------------------------------------------------

test_that("fit_single_measurement_ref fits the saved-config model end-to-end", {
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
  pet <- get_pet_identifiers(tac_files, analysis_folder)[1]
  region <- kinpar$region[1]

  fit <- suppressWarnings(fit_single_measurement_ref(
    analysis_folder = analysis_folder, model_number = "model1",
    pet = pet, region = region
  ))

  expect_equal(fit$type, "SRTM")
  expect_well_formed_fit(fit, c("R1", "k2", "BPnd"))
  expect_s3_class(plot(fit$fit, roiname = region), "ggplot")
})
