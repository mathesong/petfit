# Integration tests: Docker container
#
# Tests petfit Docker container in automatic and interactive modes using
# real ds004869 data. Tests both region definition and modelling pipelines.
#
# Default: tests against mathesong/petfit:latest
# Optional: PETFIT_DOCKER_BUILD=true rebuilds from docker/Dockerfile first
#
# Requires: PETFIT_INTEGRATION_TESTS=true, PETFIT_DOCKER_TESTS=true, Docker

# ---------------------------------------------------------------------------
# Helper: ensure Docker image is available
# ---------------------------------------------------------------------------

DOCKER_IMAGE <- "mathesong/petfit:latest"

ensure_docker_image <- function() {
  # Optionally rebuild the image from source
  if (Sys.getenv("PETFIT_DOCKER_BUILD") == "true") {
    pkg_root <- testthat::test_path("..", "..")
    build_result <- system2(
      "docker",
      c("build", "-t", DOCKER_IMAGE, "-f", "docker/Dockerfile", "."),
      stdout = TRUE, stderr = TRUE,
      env = paste0("DOCKER_BUILDKIT=1")
    )
    exit_code <- attr(build_result, "status") %||% 0L
    if (exit_code != 0L) {
      testthat::skip(paste("Docker build failed:", paste(build_result, collapse = "\n")))
    }
  }

  # Verify image exists
  check <- system2("docker", c("image", "inspect", DOCKER_IMAGE),
                    stdout = FALSE, stderr = FALSE)
  if (check != 0L) {
    testthat::skip(paste("Docker image not available:", DOCKER_IMAGE,
                         "\nPull with: docker pull", DOCKER_IMAGE,
                         "\nOr set PETFIT_DOCKER_BUILD=true to build from source"))
  }
}

# ---------------------------------------------------------------------------
# Helper: set up workspace for Docker tests (resolves symlinks)
# ---------------------------------------------------------------------------

setup_docker_workspace <- function() {
  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)

  # Docker needs real paths, not symlinks -- resolve the petprep symlink
  petprep_link <- file.path(ws$derivatives_dir, "petprep")
  if (file.exists(petprep_link) && Sys.readlink(petprep_link) != "") {
    real_path <- normalizePath(petprep_link)
    unlink(petprep_link)
    # Copy petprep into workspace so Docker can access it via bind mount
    # Use system cp for speed with -a to preserve structure
    system2("cp", c("-a", real_path, petprep_link))
  }

  ws
}

# ---------------------------------------------------------------------------
# Regiondef: automatic mode
# ---------------------------------------------------------------------------

test_that("Docker: regiondef automatic mode produces combined TACs", {
  skip_if_no_docker()
  ensure_docker_image()

  ws <- setup_docker_workspace()
  withr::defer(cleanup_workspace(ws))
  setup_regiondef_config(ws)

  result <- run_petfit_docker(
    func = "regiondef",
    mode = "automatic",
    workspace_info = ws
  )

  expect_equal(result$exit_code, 0L,
               info = paste("Docker regiondef failed:", paste(result$output, collapse = "\n")))

  # Verify output files were created
  petfit_dir <- file.path(ws$derivatives_dir, "petfit")
  combined_tacs <- file.path(petfit_dir, "desc-combinedregions_tacs.tsv")
  expect_true(file.exists(combined_tacs),
              info = "Combined TACs file should be created by Docker container")

  # Verify mapping file was created
  mapping_file <- file.path(petfit_dir, "petfit_regions_files.tsv")
  expect_true(file.exists(mapping_file),
              info = "Mapping file should be created by Docker container")
})

# ---------------------------------------------------------------------------
# Modelling plasma: automatic mode (full pipeline)
# ---------------------------------------------------------------------------

test_that("Docker: plasma modelling full pipeline succeeds", {
  skip_if_no_docker()
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

  # Install plasma config
  setup_modelling_config(ws, "ds004869_plasma_config.json")

  # Run full plasma pipeline
  result <- run_petfit_docker(
    func = "modelling_plasma",
    mode = "automatic",
    workspace_info = ws
  )

  expect_equal(result$exit_code, 0L,
               info = paste("Docker plasma pipeline failed:",
                            paste(result$output, collapse = "\n")))

  # Verify reports were generated
  analysis_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  reports_dir <- file.path(analysis_dir, "reports")
  expect_true(dir.exists(reports_dir), info = "Reports directory should exist")

  report_files <- list.files(reports_dir, pattern = "\\.html$")
  expect_gt(length(report_files), 0, label = "At least one HTML report should be generated")
})

# ---------------------------------------------------------------------------
# Modelling plasma: step-by-step
# ---------------------------------------------------------------------------

test_that("Docker: plasma modelling runs individual steps", {
  skip_if_no_docker()
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

  # Install plasma config
  setup_modelling_config(ws, "ds004869_plasma_config.json")

  # Run datadef step
  datadef_result <- run_petfit_docker(
    func = "modelling_plasma",
    mode = "automatic",
    workspace_info = ws,
    step = "datadef"
  )
  expect_equal(datadef_result$exit_code, 0L,
               info = paste("Docker datadef failed:",
                            paste(datadef_result$output, collapse = "\n")))

  # Verify individual TACs files created
  analysis_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  tacs_files <- list.files(analysis_dir, pattern = "_desc-combinedregions_tacs\\.tsv$",
                           recursive = TRUE)
  expect_gt(length(tacs_files), 0,
            label = "Individual TACs files should be created by datadef step")

  # Run weights step
  weights_result <- run_petfit_docker(
    func = "modelling_plasma",
    mode = "automatic",
    workspace_info = ws,
    step = "weights"
  )
  expect_equal(weights_result$exit_code, 0L,
               info = paste("Docker weights failed:",
                            paste(weights_result$output, collapse = "\n")))
})

# ---------------------------------------------------------------------------
# Modelling reference tissue: automatic mode (full pipeline)
# ---------------------------------------------------------------------------

test_that("Docker: reference tissue modelling full pipeline succeeds", {
  skip_if_no_docker()
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

  # Install reference tissue config
  setup_modelling_config(ws, "ds004869_ref_config.json")

  # Run full reference tissue pipeline
  result <- run_petfit_docker(
    func = "modelling_ref",
    mode = "automatic",
    workspace_info = ws
  )

  expect_equal(result$exit_code, 0L,
               info = paste("Docker reference pipeline failed:",
                            paste(result$output, collapse = "\n")))

  # Verify reports were generated
  analysis_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  reports_dir <- file.path(analysis_dir, "reports")
  expect_true(dir.exists(reports_dir), info = "Reports directory should exist")

  report_files <- list.files(reports_dir, pattern = "\\.html$")
  expect_gt(length(report_files), 0, label = "At least one HTML report should be generated")
})

# ---------------------------------------------------------------------------
# Error handling: missing config
# ---------------------------------------------------------------------------

test_that("Docker: modelling fails gracefully with missing config", {
  skip_if_no_docker()
  ensure_docker_image()

  ws <- setup_docker_workspace()
  withr::defer(cleanup_workspace(ws))

  # Create analysis dir without config file
  analysis_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  dir.create(analysis_dir, recursive = TRUE)

  result <- run_petfit_docker(
    func = "modelling_plasma",
    mode = "automatic",
    workspace_info = ws
  )

  # Should fail with non-zero exit code
  expect_true(result$exit_code != 0L,
              info = "Docker should exit non-zero when config is missing")
})

# ---------------------------------------------------------------------------
# Error handling: invalid function
# ---------------------------------------------------------------------------

test_that("Docker: invalid --func argument fails gracefully", {
  skip_if_no_docker()
  ensure_docker_image()

  ws <- setup_docker_workspace()
  withr::defer(cleanup_workspace(ws))

  # Call docker directly with invalid func
  docker_args <- c(
    "run", "--rm",
    "-v", paste0(ws$bids_dir, ":/data/bids_dir:ro"),
    "-v", paste0(ws$derivatives_dir, ":/data/derivatives_dir"),
    DOCKER_IMAGE,
    "--func", "invalid_function",
    "--mode", "automatic"
  )

  output <- system2("docker", docker_args, stdout = TRUE, stderr = TRUE)
  exit_code <- attr(output, "status") %||% 0L

  expect_true(exit_code != 0L,
              info = "Docker should reject invalid --func argument")
})

# ---------------------------------------------------------------------------
# Docker: container stdout markers
# ---------------------------------------------------------------------------

test_that("Docker: automatic mode output contains expected markers", {
  skip_if_no_docker()
  ensure_docker_image()

  ws <- setup_docker_workspace()
  withr::defer(cleanup_workspace(ws))
  setup_regiondef_config(ws)

  result <- run_petfit_docker(
    func = "regiondef",
    mode = "automatic",
    workspace_info = ws
  )

  combined_output <- paste(result$output, collapse = "\n")

  # Check for expected output markers from run_petfit.R
  expect_true(grepl("petfit Docker Container", combined_output),
              info = "Output should contain Docker container banner")
  expect_true(grepl("Function: regiondef", combined_output),
              info = "Output should identify the function being run")
  expect_true(grepl("Automatic Mode", combined_output),
              info = "Output should identify automatic mode")
})
