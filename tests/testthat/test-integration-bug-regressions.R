# Regression tests for bugs found during integration testing
#
# Each test targets a specific bug documented in:
#   tests/testthat/fixtures/integration/ISSUES.md
#
# Issues 1 and 2 are FIXED -- these tests are regression guards (should pass).
# Issue 3 is NOT YET FIXED -- its test is expected to fail until the fix is implemented.
#
# Run with:
#   PETFIT_INTEGRATION_TESTS=true Rscript -e "devtools::test(filter = 'integration-bug-regressions')"
#
# Requires: PETFIT_INTEGRATION_TESTS=true

# ---------------------------------------------------------------------------
# Issue 1: petfit_regiondef_auto() crashes — return value used as file path
# STATUS: FIXED — this test is a regression guard (should pass)
#
# Bug was: create_petfit_regions_files() returns a data frame, but the code
# stored it in petfit_regions_files_path and passed it to
# create_petfit_combined_tacs() which expects a file path string.
#
# Fix applied in: R/docker_functions.R:231
# See ISSUES.md "Issue 1" for full details.
# ---------------------------------------------------------------------------

test_that("BUG REGRESSION: petfit_regiondef_auto succeeds with real data", {
  skip_if_no_integration()

  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  withr::defer(cleanup_workspace(ws))
  setup_regiondef_config(ws)

  # This call crashes with "invalid 'file' argument" on unfixed code
  # because create_petfit_regions_files() returns a data frame, not a path
  result <- petfit_regiondef_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  expect_true(result$success,
              info = paste("petfit_regiondef_auto should succeed.",
                           "If this fails with 'invalid file argument', see ISSUES.md Issue 1.",
                           "Messages:", paste(result$messages, collapse = "\n")))

  # Verify the combined TACs file was actually created
  petfit_dir <- file.path(ws$derivatives_dir, "petfit")
  combined_tacs <- file.path(petfit_dir, "desc-combinedregions_tacs.tsv")
  expect_true(file.exists(combined_tacs),
              info = "Combined TACs file should exist after successful regiondef")
})

# ---------------------------------------------------------------------------
# Issue 2: execute_model_step() crashes on "No Model" model slots
# STATUS: FIXED — this test is a regression guard (should pass)
#
# Bug was: When Model2 or Model3 is "No Model", execute_model_step() tried to
# call generate_model_report() -> get_model_template("No Model") which failed
# because there's no template for "No Model".
#
# Fix applied in: R/pipeline_core.R:405 (added early return for "No Model")
# See ISSUES.md "Issue 2" for full details.
# ---------------------------------------------------------------------------

test_that("BUG REGRESSION: execute_model_step handles No Model gracefully", {
  skip_if_no_integration()

  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  withr::defer(cleanup_workspace(ws))
  setup_regiondef_config(ws)

  # Run regiondef
  regiondef_result <- petfit_regiondef_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )
  if (!regiondef_result$success) {
    testthat::skip("Regiondef prerequisite failed (see Issue 1)")
  }

  # Install plasma config (has Model2 and Model3 as "No Model")
  setup_modelling_config(ws, "ds004869_plasma_config.json")

  # Run full pipeline -- on unfixed code, this crashes at Model 2 with:
  #   "Error fitting Model 2: report generation failed"
  # because get_model_template("No Model") has no template mapping
  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  expect_true(result$success,
              info = paste("Full pipeline should succeed with 'No Model' slots.",
                           "If this fails at Model 2/3, see ISSUES.md Issue 2.",
                           "Messages:", paste(result$messages, collapse = "\n")))

  # Verify Model 2 was skipped, not failed
  if (!is.null(result$step_results$model2)) {
    expect_true(result$step_results$model2$success,
                info = "Model 2 ('No Model') should succeed (skip), not fail")
  }
  if (!is.null(result$step_results$model3)) {
    expect_true(result$step_results$model3$success,
                info = "Model 3 ('No Model') should succeed (skip), not fail")
  }
})

# ---------------------------------------------------------------------------
# Issue 3: Plasma model fitting when delay is "Set to zero"
# STATUS: NOT A BUG — the model reports' 3-path blood data fallback handles this
#
# When FitDelay.model is "Set to zero...", the delay step skips creating
# _inputfunction.tsv files. However, the model report templates have a
# 3-path blood loading fallback: (1) blood_dir, (2) analysis_folder,
# (3) raw BIDS data. Path 3 creates _inputfunction.tsv files on-the-fly
# from raw _blood.tsv files in bids_dir, so model fitting works without
# a prior delay step.
#
# See ISSUES.md "Issue 3" for full analysis.
# ---------------------------------------------------------------------------

test_that("BUG REGRESSION: plasma pipeline succeeds with delay set to zero", {
  skip_if_no_integration()

  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  withr::defer(cleanup_workspace(ws))
  setup_regiondef_config(ws)

  # Run regiondef
  regiondef_result <- petfit_regiondef_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )
  if (!regiondef_result$success) {
    testthat::skip("Regiondef prerequisite failed (see Issue 1)")
  }

  # Install plasma config, then modify it to use "Set to zero" delay
  config_path <- setup_modelling_config(ws, "ds004869_plasma_config.json")
  config <- jsonlite::fromJSON(config_path)
  config$FitDelay$model <- "Set to zero (i.e. no delay fitting to be performed)"
  jsonlite::write_json(config, config_path, pretty = TRUE, auto_unbox = TRUE)

  # Run full pipeline -- model reports handle missing _inputfunction.tsv files
  # by creating them on-the-fly from raw BIDS blood data (3-path fallback)
  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  expect_true(result$success,
              info = paste("Plasma pipeline should succeed even with delay 'Set to zero'.",
                           "If model fitting fails with 'No inputfunction.tsv files found',",
                           "see ISSUES.md Issue 3.",
                           "Messages:", paste(result$messages, collapse = "\n")))

  # Verify model report was generated
  report_path <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis",
                           "reports", "model1_report.html")
  expect_true(file.exists(report_path),
              info = "Model 1 report should be generated even with zero delay")
})
