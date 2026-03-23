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

  output <- suppressWarnings(
    system2("docker", docker_args, stdout = TRUE, stderr = TRUE)
  )
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

# ---------------------------------------------------------------------------
# Docker: ancillary delay inheritance
# ---------------------------------------------------------------------------

test_that("Docker: plasma pipeline with ancillary delay inheritance", {
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

  # --- Ancillary pipeline: datadef -> weights -> delay ---
  setup_modelling_config(ws, "ds004869_plasma_config.json", "Ancillary_Analysis")

  for (s in c("datadef", "weights", "delay")) {
    step_result <- run_petfit_docker(
      func = "modelling_plasma",
      mode = "automatic",
      workspace_info = ws,
      step = s,
      analysis_foldername = "Ancillary_Analysis"
    )
    expect_equal(step_result$exit_code, 0L,
                 info = paste("Docker ancillary step", s, "failed:",
                              paste(step_result$output, collapse = "\n")))
  }

  # Verify ancillary produced delay kinpar files
  ancillary_dir <- file.path(ws$derivatives_dir, "petfit", "Ancillary_Analysis")
  ancillary_delay_files <- list.files(ancillary_dir,
                                      pattern = "_desc-delayfit_kinpar\\.tsv$",
                                      recursive = TRUE)
  expect_true(length(ancillary_delay_files) > 0,
              info = "Ancillary should have delay kinpar files")

  # --- Primary pipeline: inherits delay from ancillary ---
  setup_modelling_config(ws, "ds004869_plasma_config.json", "Primary_Analysis")
  primary_config_path <- file.path(ws$derivatives_dir, "petfit",
                                    "Primary_Analysis",
                                    "desc-petfitoptions_config.json")
  config <- jsonlite::fromJSON(primary_config_path)
  config$FitDelay$model <- "ancillary_estimate"
  jsonlite::write_json(config, primary_config_path,
                       pretty = TRUE, auto_unbox = TRUE)

  # Run full primary pipeline with ancillary_analysis_folder
  result <- run_petfit_docker(
    func = "modelling_plasma",
    mode = "automatic",
    workspace_info = ws,
    ancillary_analysis_folder = "Ancillary_Analysis"
  )

  expect_equal(result$exit_code, 0L,
               info = paste("Docker primary with ancillary delay failed:",
                            paste(result$output, collapse = "\n")))

  # Verify delay files were copied to primary
  primary_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  primary_delay_files <- list.files(primary_dir,
                                     pattern = "_desc-delayfit_kinpar\\.tsv$",
                                     recursive = TRUE)
  expect_equal(length(primary_delay_files), length(ancillary_delay_files),
               info = "Delay files should be copied from ancillary to primary")

  # Verify model report was generated
  report_path <- file.path(primary_dir, "reports", "model1_report.html")
  expect_true(file.exists(report_path),
              info = "Model report should be generated with inherited delay")
})

# ---------------------------------------------------------------------------
# Docker: ancillary k2prime inheritance
# ---------------------------------------------------------------------------

test_that("Docker: reference pipeline with ancillary k2prime inheritance", {
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

  # --- Ancillary pipeline: fit SRTM (produces kinpar with k2prime) ---
  setup_modelling_config(ws, "ds004869_ref_config.json", "Ancillary_Analysis")

  ancillary_result <- run_petfit_docker(
    func = "modelling_ref",
    mode = "automatic",
    workspace_info = ws,
    analysis_foldername = "Ancillary_Analysis"
  )

  expect_equal(ancillary_result$exit_code, 0L,
               info = paste("Docker ancillary SRTM pipeline failed:",
                            paste(ancillary_result$output, collapse = "\n")))

  # Verify ancillary produced model1 kinpar files with k2prime column
  ancillary_dir <- file.path(ws$derivatives_dir, "petfit", "Ancillary_Analysis")
  ancillary_kinpar_files <- list.files(ancillary_dir,
                                       pattern = "_desc-model1_kinpar\\.tsv$",
                                       recursive = TRUE)
  expect_true(length(ancillary_kinpar_files) > 0,
              info = "Ancillary should have model1 kinpar files")

  first_kinpar <- readr::read_tsv(
    file.path(ancillary_dir, ancillary_kinpar_files[1]),
    show_col_types = FALSE
  )
  expect_true("k2prime" %in% names(first_kinpar),
              info = "SRTM kinpar should contain k2prime column")

  # --- Primary pipeline: MRTM2 inheriting k2prime from ancillary ---
  setup_modelling_config(ws, "ds004869_ref_config.json", "Primary_Analysis")
  primary_config_path <- file.path(ws$derivatives_dir, "petfit",
                                    "Primary_Analysis",
                                    "desc-petfitoptions_config.json")
  config <- jsonlite::fromJSON(primary_config_path)
  config$Models$Model1$type <- "MRTM2"
  config$Models$Model1$k2prime_source <- "ancillary_model1_median"
  config$Models$Model1$k2prime <- 0.1
  config$Models$Model1$use_weights <- TRUE
  jsonlite::write_json(config, primary_config_path,
                       pretty = TRUE, auto_unbox = TRUE)

  # Run full primary pipeline with ancillary k2prime
  result <- run_petfit_docker(
    func = "modelling_ref",
    mode = "automatic",
    workspace_info = ws,
    ancillary_analysis_folder = "Ancillary_Analysis"
  )

  expect_equal(result$exit_code, 0L,
               info = paste("Docker primary MRTM2 with ancillary k2prime failed:",
                            paste(result$output, collapse = "\n")))

  # Verify MRTM2 model report was generated
  primary_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  report_path <- file.path(primary_dir, "reports", "model1_report.html")
  expect_true(file.exists(report_path),
              info = "MRTM2 model report should be generated with inherited k2prime")

  # Verify the report mentions ancillary k2prime source
  report_content <- readLines(report_path)
  expect_true(
    any(grepl("ancillary", report_content, ignore.case = TRUE)),
    info = "MRTM2 report should mention ancillary k2prime source"
  )
})
