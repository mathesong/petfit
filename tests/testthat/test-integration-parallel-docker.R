# Integration tests: Parallel Processing via Docker Container
#
# Tests that the --cores flag works correctly when passed through Docker.
# Verifies that parallel processing with cores=2 produces valid output
# from within a Docker container.
#
# Requires: PETFIT_INTEGRATION_TESTS=true AND PETFIT_DOCKER_TESTS=true
#   AND PETFIT_PARALLEL_TESTS=true

# ---------------------------------------------------------------------------
# Skip helper
# ---------------------------------------------------------------------------

skip_if_no_parallel_docker <- function() {
  skip_if_no_docker()
  if (!identical(Sys.getenv("PETFIT_PARALLEL_TESTS"), "true")) {
    testthat::skip("Parallel tests disabled (set PETFIT_PARALLEL_TESTS=true)")
  }
}

# ---------------------------------------------------------------------------
# Test: Docker regiondef with cores=2
# ---------------------------------------------------------------------------

test_that("Docker: regiondef with cores=2 produces combined TACs", {
  skip_if_no_parallel_docker()
  ensure_docker_image()

  ws <- setup_docker_workspace()
  withr::defer(cleanup_workspace(ws))
  setup_regiondef_config(ws)

  result <- run_petfit_docker(
    func = "regiondef",
    mode = "automatic",
    workspace_info = ws,
    cores = 2L
  )

  expect_equal(result$exit_code, 0L,
               info = paste("Docker parallel regiondef failed:",
                            paste(result$output, collapse = "\n")))

  # Verify output files were created
  petfit_dir <- file.path(ws$derivatives_dir, "petfit")
  combined_tacs <- file.path(petfit_dir, "desc-combinedregions_tacs.tsv")
  expect_true(file.exists(combined_tacs),
              info = "Combined TACs file should be created with cores=2")
})

# ---------------------------------------------------------------------------
# Test: Docker plasma pipeline with cores=2
# ---------------------------------------------------------------------------

test_that("Docker: plasma modelling with cores=2 succeeds", {
  skip_if_no_parallel_docker()
  ensure_docker_image()

  ws <- setup_docker_workspace()
  withr::defer(cleanup_workspace(ws))
  setup_regiondef_config(ws)

  # Run regiondef first (sequential is fine for setup)
  regiondef_result <- run_petfit_docker(
    func = "regiondef",
    mode = "automatic",
    workspace_info = ws
  )
  if (regiondef_result$exit_code != 0L) {
    testthat::skip("Docker regiondef prerequisite failed")
  }

  # Install plasma config
  setup_modelling_config(ws, "ds004869_plasma_config.json")

  # Run full plasma pipeline with 2 cores
  result <- run_petfit_docker(
    func = "modelling_plasma",
    mode = "automatic",
    workspace_info = ws,
    cores = 2L
  )

  expect_equal(result$exit_code, 0L,
               info = paste("Docker parallel plasma pipeline failed:",
                            paste(result$output, collapse = "\n")))

  # Verify reports were generated
  analysis_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  reports_dir <- file.path(analysis_dir, "reports")
  expect_true(dir.exists(reports_dir), info = "Reports directory should exist")

  report_files <- list.files(reports_dir, pattern = "\\.html$")
  expect_gt(length(report_files), 0,
            label = "At least one HTML report should be generated with cores=2")
})

# ---------------------------------------------------------------------------
# Test: Docker reference pipeline with cores=2
# ---------------------------------------------------------------------------

test_that("Docker: reference modelling with cores=2 succeeds", {
  skip_if_no_parallel_docker()
  ensure_docker_image()

  ws <- setup_docker_workspace()
  withr::defer(cleanup_workspace(ws))
  setup_regiondef_config(ws)

  # Run regiondef first
  regiondef_result <- run_petfit_docker(
    func = "regiondef",
    mode = "automatic",
    workspace_info = ws
  )
  if (regiondef_result$exit_code != 0L) {
    testthat::skip("Docker regiondef prerequisite failed")
  }

  # Install ref config
  setup_modelling_config(ws, "ds004869_ref_config.json")

  # Run full reference pipeline with 2 cores
  result <- run_petfit_docker(
    func = "modelling_ref",
    mode = "automatic",
    workspace_info = ws,
    cores = 2L
  )

  expect_equal(result$exit_code, 0L,
               info = paste("Docker parallel reference pipeline failed:",
                            paste(result$output, collapse = "\n")))

  # Verify reports were generated
  analysis_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  reports_dir <- file.path(analysis_dir, "reports")
  expect_true(dir.exists(reports_dir), info = "Reports directory should exist")

  report_files <- list.files(reports_dir, pattern = "\\.html$")
  expect_gt(length(report_files), 0,
            label = "At least one HTML report should be generated with cores=2")
})
