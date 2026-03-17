# Integration tests: Modelling Pipeline with Reference Tissue
#
# Tests petfit_modelling_auto() with real ds004869 data using
# the reference tissue (non-invasive) pipeline: datadef -> weights -> reference_tac -> model.
#
# Uses 2 subjects (sub-01, sub-02), Frontal+Temporal regions,
# Cerebellum as reference. SRTM model is fitted.
#
# Requires: PETFIT_INTEGRATION_TESTS=true

# ---------------------------------------------------------------------------
# Helper: run regiondef + modelling setup for reference tissue
# ---------------------------------------------------------------------------

setup_ref_workspace <- function() {
  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  setup_regiondef_config(ws)

  # Run regiondef to create combined TACs
  regiondef_result <- petfit_regiondef_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  if (!regiondef_result$success) {
    testthat::skip(paste("Regiondef failed:", paste(regiondef_result$messages, collapse = "\n")))
  }

  # Install reference tissue modelling config
  setup_modelling_config(ws, "ds004869_ref_config.json")

  ws
}

# ---------------------------------------------------------------------------
# Full pipeline test
# ---------------------------------------------------------------------------

test_that("reference tissue pipeline runs end-to-end", {
  skip_if_no_integration()

  ws <- setup_ref_workspace()
  withr::defer(cleanup_workspace(ws))

  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  expect_true(result$success, info = paste(result$messages, collapse = "\n"))
})

# ---------------------------------------------------------------------------
# Data definition step with region subsetting
# ---------------------------------------------------------------------------

test_that("datadef step subsets to Frontal and Temporal regions", {
  skip_if_no_integration()

  ws <- setup_ref_workspace()
  withr::defer(cleanup_workspace(ws))

  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    step = "datadef"
  )

  expect_true(result$success, info = paste(result$messages, collapse = "\n"))

  # Check individual TACs files
  analysis_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  tacs_files <- list.files(analysis_dir, pattern = "_desc-combinedregions_tacs\\.tsv$",
                           recursive = TRUE)

  # 2 subjects * 2 sessions = 4 files
  expect_equal(length(tacs_files), 4)

  # Verify region subsetting applied (Frontal, Temporal, Cerebellum -- not WhiteMatter)
  first_file <- file.path(analysis_dir, tacs_files[1])
  tacs_data <- readr::read_tsv(first_file, show_col_types = FALSE)

  actual_regions <- sort(unique(tacs_data$region))
  # Cerebellum must be included since it's the reference region
  expect_true("Frontal" %in% actual_regions)
  expect_true("Temporal" %in% actual_regions)
  expect_true("Cerebellum" %in% actual_regions)
  expect_false("WhiteMatter" %in% actual_regions)
})

# ---------------------------------------------------------------------------
# Reference TAC step
# ---------------------------------------------------------------------------

test_that("reference TAC step succeeds with Cerebellum reference", {
  skip_if_no_integration()

  ws <- setup_ref_workspace()
  withr::defer(cleanup_workspace(ws))

  # Run prerequisite steps
  petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    step = "datadef"
  )
  petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    step = "weights"
  )

  # Run reference TAC step
  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    step = "reference_tac"
  )

  expect_true(result$success, info = paste(result$messages, collapse = "\n"))

  # Check reference TAC report
  report_path <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis",
                           "reports", "reference_tac_report.html")
  expect_true(file.exists(report_path),
              info = "Reference TAC report should be generated")
})

# ---------------------------------------------------------------------------
# SRTM model fitting
# ---------------------------------------------------------------------------

test_that("SRTM model fitting generates report", {
  skip_if_no_integration()

  ws <- setup_ref_workspace()
  withr::defer(cleanup_workspace(ws))

  # Run all prerequisite steps
  petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    step = "datadef"
  )
  petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    step = "weights"
  )
  petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    step = "reference_tac"
  )

  # Run SRTM model fitting
  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    step = "model1"
  )

  expect_true(result$success, info = paste(result$messages, collapse = "\n"))

  report_path <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis",
                           "reports", "model1_report.html")
  expect_true(file.exists(report_path),
              info = "Model 1 (SRTM) report should be generated")
})

# ---------------------------------------------------------------------------
# Single-subject run
# ---------------------------------------------------------------------------

test_that("reference tissue pipeline succeeds with single subject", {
  skip_if_no_integration()

  ws <- setup_ref_workspace()
  withr::defer(cleanup_workspace(ws))

  # Modify config to subset to single subject
  config_path <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis",
                           "desc-petfitoptions_config.json")
  config <- jsonlite::fromJSON(config_path)
  config$Subsetting$sub <- "01"
  jsonlite::write_json(config, config_path, pretty = TRUE, auto_unbox = TRUE)

  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  expect_true(result$success, info = paste(result$messages, collapse = "\n"))

  # Verify model report was generated
  report_path <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis",
                           "reports", "model1_report.html")
  expect_true(file.exists(report_path),
              info = "Model 1 report should be generated for single-subject run")
})

# ---------------------------------------------------------------------------
# Pipeline type detection
# ---------------------------------------------------------------------------

test_that("pipeline type is detected as reference from config", {
  skip_if_no_integration()

  config <- jsonlite::fromJSON(
    testthat::test_path("fixtures", "integration", "ds004869_ref_config.json")
  )

  detected <- determine_pipeline_type(config)
  expect_equal(detected, "reference")
})
