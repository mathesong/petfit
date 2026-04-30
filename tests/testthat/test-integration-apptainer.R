# Integration tests: Apptainer container
#
# Tests petfit Apptainer container in automatic mode using real ds004869 data.
# Also validates the container definition file without requiring a built container.
#
# Container tests require: PETFIT_INTEGRATION_TESTS=true, PETFIT_APPTAINER_TESTS=true,
#   and either apptainer or singularity CLI available.
#
# Definition validation tests run with just PETFIT_INTEGRATION_TESTS=true (no container needed).

# ---------------------------------------------------------------------------
# Definition file validation (no container needed)
# ---------------------------------------------------------------------------

test_that("Apptainer definition file has required sections", {
  skip_if_no_integration()

  pkg_root <- testthat::test_path("..", "..")
  def_file <- file.path(pkg_root, "apptainer", "petfit.def")

  expect_true(file.exists(def_file), info = "petfit.def should exist")

  def_content <- readLines(def_file)
  def_text <- paste(def_content, collapse = "\n")

  expect_true(grepl("Bootstrap:\\s*docker", def_text),
              info = "Definition should have Docker bootstrap")
  expect_true(grepl("From:\\s*rocker/shiny-verse", def_text),
              info = "Definition should use rocker/shiny-verse base")
  expect_true(grepl("%runscript", def_text),
              info = "Definition should have a runscript section")
  expect_true(grepl("%post", def_text),
              info = "Definition should have a post section")
  expect_true(grepl("kinfitr", def_text),
              info = "Definition should install kinfitr")
})

# ---------------------------------------------------------------------------
# Container tests: regiondef automatic mode
# ---------------------------------------------------------------------------

test_that("Apptainer: regiondef automatic mode produces combined TACs", {
  skip_if_no_apptainer()

  container <- find_apptainer_container()
  if (is.null(container)) {
    testthat::skip(paste(
      "No Apptainer container found. Provide via one of:",
      "  1. PETFIT_APPTAINER_SIF=/path/to/petfit.sif",
      "  2. Place .sif file in apptainer/ directory",
      "  3. Have Docker image mathesong/petfit:latest available",
      sep = "\n"
    ))
  }

  ws <- setup_apptainer_workspace()
  withr::defer(cleanup_workspace(ws))
  setup_regiondef_config(ws)

  result <- run_petfit_apptainer(
    func = "regiondef",
    mode = "automatic",
    workspace_info = ws,
    container = container
  )

  expect_equal(result$exit_code, 0L,
               info = paste("Apptainer regiondef failed:",
                            paste(result$output, collapse = "\n")))

  # Verify output files were created
  petfit_dir <- file.path(ws$derivatives_dir, "petfit")
  combined_tacs <- file.path(petfit_dir, "desc-combinedregions_tacs.tsv")
  expect_true(file.exists(combined_tacs),
              info = "Combined TACs file should be created")
})

# ---------------------------------------------------------------------------
# Container tests: modelling pipelines
# ---------------------------------------------------------------------------

test_that("Apptainer: plasma modelling full pipeline succeeds", {
  skip_if_no_apptainer()

  container <- find_apptainer_container()
  if (is.null(container)) {
    testthat::skip("No Apptainer container available")
  }

  ws <- setup_apptainer_workspace()
  withr::defer(cleanup_workspace(ws))
  setup_regiondef_config(ws)

  # Run regiondef first
  regiondef_result <- run_petfit_apptainer(
    func = "regiondef",
    mode = "automatic",
    workspace_info = ws,
    container = container
  )
  if (regiondef_result$exit_code != 0L) {
    testthat::skip("Apptainer regiondef prerequisite failed")
  }

  # Install plasma config
  setup_modelling_config(ws, "ds004869_plasma_config.json")

  # Run full plasma pipeline
  result <- run_petfit_apptainer(
    func = "modelling_plasma",
    mode = "automatic",
    workspace_info = ws,
    container = container
  )

  expect_equal(result$exit_code, 0L,
               info = paste("Apptainer plasma pipeline failed:",
                            paste(result$output, collapse = "\n")))

  # Verify reports
  analysis_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  reports_dir <- file.path(analysis_dir, "reports")
  expect_true(dir.exists(reports_dir), info = "Reports directory should exist")
})

test_that("Apptainer: reference tissue modelling full pipeline succeeds", {
  skip_if_no_apptainer()

  container <- find_apptainer_container()
  if (is.null(container)) {
    testthat::skip("No Apptainer container available")
  }

  ws <- setup_apptainer_workspace()
  withr::defer(cleanup_workspace(ws))
  setup_regiondef_config(ws)

  # Run regiondef first
  regiondef_result <- run_petfit_apptainer(
    func = "regiondef",
    mode = "automatic",
    workspace_info = ws,
    container = container
  )
  if (regiondef_result$exit_code != 0L) {
    testthat::skip("Apptainer regiondef prerequisite failed")
  }

  # Install ref config
  setup_modelling_config(ws, "ds004869_ref_config.json")

  # Run full reference tissue pipeline
  result <- run_petfit_apptainer(
    func = "modelling_ref",
    mode = "automatic",
    workspace_info = ws,
    container = container
  )

  expect_equal(result$exit_code, 0L,
               info = paste("Apptainer reference pipeline failed:",
                            paste(result$output, collapse = "\n")))

  # Verify reports
  analysis_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  reports_dir <- file.path(analysis_dir, "reports")
  expect_true(dir.exists(reports_dir), info = "Reports directory should exist")
})

# ---------------------------------------------------------------------------
# Container tests: ancillary delay inheritance
# ---------------------------------------------------------------------------

test_that("Apptainer: plasma pipeline with ancillary delay inheritance", {
  skip_if_no_apptainer()

  container <- find_apptainer_container()
  if (is.null(container)) {
    testthat::skip("No Apptainer container available")
  }

  ws <- setup_apptainer_workspace()
  withr::defer(cleanup_workspace(ws))
  setup_regiondef_config(ws)

  # Run regiondef first
  regiondef_result <- run_petfit_apptainer(
    func = "regiondef",
    mode = "automatic",
    workspace_info = ws,
    container = container
  )
  if (regiondef_result$exit_code != 0L) {
    testthat::skip("Apptainer regiondef prerequisite failed")
  }

  # --- Ancillary pipeline: datadef -> weights -> delay ---
  setup_modelling_config(ws, "ds004869_plasma_config.json", "Ancillary_Analysis")

  for (s in c("datadef", "weights", "delay")) {
    step_result <- run_petfit_apptainer(
      func = "modelling_plasma",
      mode = "automatic",
      workspace_info = ws,
      container = container,
      step = s,
      analysis_foldername = "Ancillary_Analysis"
    )
    expect_equal(step_result$exit_code, 0L,
                 info = paste("Apptainer ancillary step", s, "failed:",
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
  result <- run_petfit_apptainer(
    func = "modelling_plasma",
    mode = "automatic",
    workspace_info = ws,
    container = container,
    ancillary_analysis_folder = "Ancillary_Analysis"
  )

  expect_equal(result$exit_code, 0L,
               info = paste("Apptainer primary with ancillary delay failed:",
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
# Container tests: ancillary k2prime inheritance
# ---------------------------------------------------------------------------

test_that("Apptainer: reference pipeline with ancillary k2prime inheritance", {
  skip_if_no_apptainer()

  container <- find_apptainer_container()
  if (is.null(container)) {
    testthat::skip("No Apptainer container available")
  }

  ws <- setup_apptainer_workspace()
  withr::defer(cleanup_workspace(ws))
  setup_regiondef_config(ws)

  # Run regiondef first
  regiondef_result <- run_petfit_apptainer(
    func = "regiondef",
    mode = "automatic",
    workspace_info = ws,
    container = container
  )
  if (regiondef_result$exit_code != 0L) {
    testthat::skip("Apptainer regiondef prerequisite failed")
  }

  # --- Ancillary pipeline: fit SRTM (produces kinpar with k2prime) ---
  setup_modelling_config(ws, "ds004869_ref_config.json", "Ancillary_Analysis")

  ancillary_result <- run_petfit_apptainer(
    func = "modelling_ref",
    mode = "automatic",
    workspace_info = ws,
    container = container,
    analysis_foldername = "Ancillary_Analysis"
  )

  expect_equal(ancillary_result$exit_code, 0L,
               info = paste("Apptainer ancillary SRTM pipeline failed:",
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
  result <- run_petfit_apptainer(
    func = "modelling_ref",
    mode = "automatic",
    workspace_info = ws,
    container = container,
    ancillary_analysis_folder = "Ancillary_Analysis"
  )

  expect_equal(result$exit_code, 0L,
               info = paste("Apptainer primary MRTM2 with ancillary k2prime failed:",
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
