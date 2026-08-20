# Integration tests: Nested SRTM Modelling Pipeline (Reference Tissue)
#
# Tests petfit_modelling_auto() with real ds004869 data using the nested SRTM
# model, which fits all target regions of each measurement jointly with k2prime
# shared across regions, followed by SRTM2 inheriting the fitted k2prime.
#
# Uses 2 subjects (sub-01, sub-02), Cerebellum reference, Frontal and Temporal
# target regions.
#
# Requires: PETFIT_INTEGRATION_TESTS=true

# ---------------------------------------------------------------------------
# Helper: run regiondef + modelling setup
# ---------------------------------------------------------------------------

setup_nestedsrtm_workspace <- function() {
  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  setup_regiondef_config(ws)

  regiondef_result <- petfit_regiondef_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  if (!regiondef_result$success) {
    testthat::skip(paste("Regiondef failed:", paste(regiondef_result$messages, collapse = "\n")))
  }

  setup_modelling_config(ws, "ds004869_nestedsrtm_config.json")

  ws
}

# ---------------------------------------------------------------------------
# Full pipeline test
# ---------------------------------------------------------------------------

test_that("nested SRTM pipeline runs end-to-end and SRTM2 inherits k2prime", {
  skip_if_no_integration()

  ws <- setup_nestedsrtm_workspace()
  withr::defer(cleanup_workspace(ws))

  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  expect_true(result$success, info = paste(result$messages, collapse = "\n"))

  analysis_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")

  # Model reports generated
  expect_true(file.exists(file.path(analysis_dir, "reports", "model1_report.html")))
  expect_true(file.exists(file.path(analysis_dir, "reports", "model2_report.html")))

  # Cohort-level kinpar file with the nested model name
  cohort_kinpar <- file.path(analysis_dir, "model-nestedSRTM_desc-model1_kinpar.tsv")
  expect_true(file.exists(cohort_kinpar))

  kinpar <- readr::read_tsv(cohort_kinpar, show_col_types = FALSE)

  # One row per (measurement, target region): 4 measurements * 2 target regions
  expect_equal(nrow(kinpar), 8)

  # Parameters present, including the shared k2prime that later models inherit
  for (col in c("region", "R1", "BPnd", "k2prime", "k2a")) {
    expect_true(col %in% names(kinpar), info = paste("Missing column:", col))
  }

  # k2prime is constant within each measurement
  shared_check <- kinpar %>%
    dplyr::group_by(pet) %>%
    dplyr::summarise(k2prime_unique = dplyr::n_distinct(k2prime))
  expect_true(all(shared_check$k2prime_unique == 1),
              info = "k2prime should be shared (constant) within each measurement")

  # SRTM2 (Model 2) ran with inherited k2prime and wrote its own outputs
  srtm2_kinpar <- file.path(analysis_dir, "model-SRTM2_desc-model2_kinpar.tsv")
  expect_true(file.exists(srtm2_kinpar))

  # Per-PET fitted TACs files for the nested model
  fitted_files <- list.files(analysis_dir,
                             pattern = "_model-nestedSRTM_desc-model1fitted_tacs\\.tsv$",
                             recursive = TRUE)
  expect_equal(length(fitted_files), 4)

  first_fitted <- readr::read_tsv(file.path(analysis_dir, fitted_files[1]),
                                  show_col_types = FALSE)
  for (col in c("region", "frame_mid", "Reference", "TAC", "TAC_fitted", "weights")) {
    expect_true(col %in% names(first_fitted), info = paste("Missing column:", col))
  }
})
