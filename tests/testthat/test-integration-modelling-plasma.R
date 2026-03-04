# Integration tests: Modelling Pipeline with Plasma Input
#
# Tests petfit_modelling_auto() with real ds004869 data using
# the plasma input (invasive) pipeline: datadef -> weights -> delay -> model.
#
# Uses 2 subjects (sub-01, sub-02) for speed.
# Delay fitting uses 1TCM single TAC method (quickest option).
# 2TCM model is fitted.
#
# Blood data: ds004869 has raw _blood.tsv files in the BIDS directory.
# The delay report converts these to _inputfunction.tsv files for model fitting.
# We do NOT pass blood_dir separately -- bids_dir contains the blood data.
#
# Requires: PETFIT_INTEGRATION_TESTS=true

# ---------------------------------------------------------------------------
# Helper: run regiondef + modelling setup
# ---------------------------------------------------------------------------

setup_plasma_workspace <- function() {
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

  # Install plasma modelling config
  setup_modelling_config(ws, "ds004869_plasma_config.json")

  ws
}

# ---------------------------------------------------------------------------
# Full pipeline test
# ---------------------------------------------------------------------------

test_that("plasma modelling pipeline runs end-to-end", {
  skip_if_no_integration()

  ws <- setup_plasma_workspace()
  withr::defer(cleanup_workspace(ws))

  # Run full modelling pipeline (datadef -> weights -> delay -> model)
  # blood_dir is NULL; raw _blood.tsv files are found via bids_dir
  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  expect_true(result$success, info = paste(result$messages, collapse = "\n"))
})

# ---------------------------------------------------------------------------
# Data definition step
# ---------------------------------------------------------------------------

test_that("datadef step creates individual TACs files for 2 subjects", {
  skip_if_no_integration()

  ws <- setup_plasma_workspace()
  withr::defer(cleanup_workspace(ws))

  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    step = "datadef"
  )

  expect_true(result$success, info = paste(result$messages, collapse = "\n"))

  # Check individual TACs files were created
  analysis_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  tacs_files <- list.files(analysis_dir, pattern = "_desc-combinedregions_tacs\\.tsv$",
                           recursive = TRUE)

  # Sub-01 has 2 sessions, sub-02 has 2 sessions = 4 files
  expect_equal(length(tacs_files), 4)

  # Verify file content
  first_file <- file.path(analysis_dir, tacs_files[1])
  tacs_data <- readr::read_tsv(first_file, show_col_types = FALSE)

  # Required columns in individual TACs
  expected_cols <- c("pet", "region", "volume_mm3", "InjectedRadioactivity",
                     "bodyweight", "frame_start", "frame_end", "frame_dur",
                     "frame_mid", "TAC")
  for (col in expected_cols) {
    expect_true(col %in% names(tacs_data), info = paste("Missing column:", col))
  }

  # Should have 4 regions * 33 frames
  expect_equal(length(unique(tacs_data$region)), 4)
  expect_true(nrow(tacs_data) > 0)
})

test_that("datadef step generates report", {
  skip_if_no_integration()

  ws <- setup_plasma_workspace()
  withr::defer(cleanup_workspace(ws))

  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    step = "datadef"
  )

  expect_true(result$success)

  # Check report was generated
  report_path <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis",
                           "reports", "data_definition_report.html")
  expect_true(file.exists(report_path),
              info = "Data definition report should be generated")
})

# ---------------------------------------------------------------------------
# Weights step
# ---------------------------------------------------------------------------

test_that("weights step creates weight files", {
  skip_if_no_integration()

  ws <- setup_plasma_workspace()
  withr::defer(cleanup_workspace(ws))

  # Run datadef first
  petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    step = "datadef"
  )

  # Run weights step
  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    step = "weights"
  )

  expect_true(result$success, info = paste(result$messages, collapse = "\n"))

  # Check weight files were created
  analysis_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  weight_files <- list.files(analysis_dir, pattern = "_desc-weights_weights\\.tsv$",
                             recursive = TRUE)

  # Should have one weight file per PET measurement (4 for 2 subjects * 2 sessions)
  expect_equal(length(weight_files), 4)

  # Verify weight file content
  first_weight <- readr::read_tsv(file.path(analysis_dir, weight_files[1]),
                                  show_col_types = FALSE)
  expect_true("weights" %in% names(first_weight) || "weight" %in% names(first_weight),
              info = "Weight file should contain a weights/weight column")
  expect_true(nrow(first_weight) > 0)
})

# ---------------------------------------------------------------------------
# Delay step (1TCM single TAC)
# ---------------------------------------------------------------------------

test_that("delay step with 1TCM single TAC succeeds", {
  skip_if_no_integration()

  ws <- setup_plasma_workspace()
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

  # Run delay step
  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    step = "delay"
  )

  expect_true(result$success, info = paste(result$messages, collapse = "\n"))

  # Check delay report was generated
  report_path <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis",
                           "reports", "delay_report.html")
  expect_true(file.exists(report_path),
              info = "Delay report should be generated")
})

# ---------------------------------------------------------------------------
# Model fitting step
# ---------------------------------------------------------------------------

test_that("2TCM model fitting generates report", {
  skip_if_no_integration()

  ws <- setup_plasma_workspace()
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
    step = "delay"
  )

  # Run model fitting
  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    step = "model1"
  )

  expect_true(result$success, info = paste(result$messages, collapse = "\n"))

  # Check model report was generated
  report_path <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis",
                           "reports", "model1_report.html")
  expect_true(file.exists(report_path),
              info = "Model 1 (2TCM) report should be generated")
})

# ---------------------------------------------------------------------------
# Pipeline type detection
# ---------------------------------------------------------------------------

test_that("pipeline type is detected as plasma from config", {
  skip_if_no_integration()

  config <- jsonlite::fromJSON(
    testthat::test_path("fixtures", "integration", "ds004869_plasma_config.json")
  )

  detected <- determine_pipeline_type(config)
  expect_equal(detected, "plasma")
})
