# Integration tests: Parallel Processing
#
# Tests that parallel processing with cores=2 produces identical results
# to sequential processing (cores=1).
#
# Uses existing ds004869 test data (2 subjects).
#
# Requires: PETFIT_INTEGRATION_TESTS=true AND PETFIT_PARALLEL_TESTS=true

# ---------------------------------------------------------------------------
# Skip helper
# ---------------------------------------------------------------------------

skip_if_no_parallel <- function() {
  skip_if_no_integration()
  if (!identical(Sys.getenv("PETFIT_PARALLEL_TESTS"), "true")) {
    testthat::skip("Parallel tests disabled (set PETFIT_PARALLEL_TESTS=true)")
  }
}

# ---------------------------------------------------------------------------
# Helper: run regiondef + modelling setup for a given core count
# ---------------------------------------------------------------------------

setup_plasma_workspace_with_cores <- function(cores = 1L) {
  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  setup_regiondef_config(ws)

  regiondef_result <- petfit_regiondef_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    cores = cores
  )

  if (!regiondef_result$success) {
    testthat::skip(paste("Regiondef failed:", paste(regiondef_result$messages, collapse = "\n")))
  }

  setup_modelling_config(ws, "ds004869_plasma_config.json")

  ws
}

setup_ref_workspace_with_cores <- function(cores = 1L) {
  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  setup_regiondef_config(ws)

  regiondef_result <- petfit_regiondef_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    cores = cores
  )

  if (!regiondef_result$success) {
    testthat::skip(paste("Regiondef failed:", paste(regiondef_result$messages, collapse = "\n")))
  }

  setup_modelling_config(ws, "ds004869_ref_config.json")

  ws
}

# ---------------------------------------------------------------------------
# Test: Parallel regiondef produces identical combined TACs
# ---------------------------------------------------------------------------

test_that("parallel regiondef produces identical output to sequential", {
  skip_if_no_parallel()

  dataset_dir <- ensure_testdata()

  # Sequential
  ws_seq <- create_integration_workspace(dataset_dir)
  withr::defer(cleanup_workspace(ws_seq))
  setup_regiondef_config(ws_seq)

  result_seq <- petfit_regiondef_auto(
    bids_dir = ws_seq$bids_dir,
    derivatives_dir = ws_seq$derivatives_dir,
    cores = 1L
  )

  # Parallel
  ws_par <- create_integration_workspace(dataset_dir)
  withr::defer(cleanup_workspace(ws_par))
  setup_regiondef_config(ws_par)

  result_par <- petfit_regiondef_auto(
    bids_dir = ws_par$bids_dir,
    derivatives_dir = ws_par$derivatives_dir,
    cores = 2L
  )

  expect_true(result_seq$success)
  expect_true(result_par$success)

  # Compare combined TACs files
  tacs_seq <- readr::read_tsv(
    file.path(ws_seq$derivatives_dir, "petfit", "desc-combinedregions_tacs.tsv"),
    show_col_types = FALSE
  )
  tacs_par <- readr::read_tsv(
    file.path(ws_par$derivatives_dir, "petfit", "desc-combinedregions_tacs.tsv"),
    show_col_types = FALSE
  )

  expect_equal(nrow(tacs_seq), nrow(tacs_par))
  expect_equal(sort(colnames(tacs_seq)), sort(colnames(tacs_par)))

  # Compare numeric columns (TAC values should be identical)
  expect_equal(tacs_seq$TAC, tacs_par$TAC)
  expect_equal(tacs_seq$seg_meanTAC, tacs_par$seg_meanTAC)
})

# ---------------------------------------------------------------------------
# Test: Parallel plasma pipeline runs successfully with cores=2
# ---------------------------------------------------------------------------

test_that("plasma pipeline runs successfully with cores=2", {
  skip_if_no_parallel()

  ws <- setup_plasma_workspace_with_cores(cores = 2L)
  withr::defer(cleanup_workspace(ws))

  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    cores = 2L
  )

  expect_true(result$success, info = paste(result$messages, collapse = "\n"))

  # Check reports were generated
  analysis_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  reports_dir <- file.path(analysis_dir, "reports")
  report_files <- list.files(reports_dir, pattern = "\\.html$")

  expect_true(length(report_files) >= 3,
              info = paste("Expected at least 3 reports, found:", length(report_files)))
})

# ---------------------------------------------------------------------------
# Test: Parallel reference pipeline runs successfully with cores=2
# ---------------------------------------------------------------------------

test_that("reference pipeline runs successfully with cores=2", {
  skip_if_no_parallel()

  ws <- setup_ref_workspace_with_cores(cores = 2L)
  withr::defer(cleanup_workspace(ws))

  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    pipeline_type = "reference",
    cores = 2L
  )

  expect_true(result$success, info = paste(result$messages, collapse = "\n"))

  # Check reports were generated
  analysis_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  reports_dir <- file.path(analysis_dir, "reports")
  report_files <- list.files(reports_dir, pattern = "\\.html$")

  expect_true(length(report_files) >= 3,
              info = paste("Expected at least 3 reports, found:", length(report_files)))
})
