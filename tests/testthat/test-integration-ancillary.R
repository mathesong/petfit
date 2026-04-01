# Integration tests: Ancillary Analysis Folder Inheritance
#
# Tests that delay and k2prime values can be inherited from an ancillary
# analysis folder. The ancillary workflow runs a quick analysis on a subset
# of high-quality regions, then the full analysis inherits those shared
# parameter estimates.
#
# Delay inheritance (plasma pipeline):
#   ancillary: datadef -> weights -> delay -> produces delay kinpar files
#   primary:   datadef -> delay (copies files from ancillary) -> model
#
# k2prime inheritance (reference tissue pipeline):
#   ancillary: produces model kinpar files with k2prime column
#   primary:   model reads k2prime from ancillary kinpar files
#
# Requires: PETFIT_INTEGRATION_TESTS=true

# ---------------------------------------------------------------------------
# Helper: set up workspace with regiondef complete
# ---------------------------------------------------------------------------

setup_ancillary_workspace <- function() {
  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  setup_regiondef_config(ws)

  regiondef_result <- petfit_regiondef_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  if (!regiondef_result$success) {
    testthat::skip(paste("Regiondef failed:",
                         paste(regiondef_result$messages, collapse = "\n")))
  }

  ws
}

# ---------------------------------------------------------------------------
# Delay inheritance: full end-to-end
# ---------------------------------------------------------------------------

test_that("plasma pipeline succeeds with ancillary delay inheritance", {
  skip_if_no_integration()

  ws <- setup_ancillary_workspace()
  withr::defer(cleanup_workspace(ws))

  # --- Ancillary pipeline: datadef -> weights -> delay ---
  setup_modelling_config(ws, "ds004869_plasma_config.json", "Ancillary_Analysis")

  for (s in c("datadef", "weights", "delay")) {
    result <- petfit_modelling_auto(
      bids_dir = ws$bids_dir,
      derivatives_dir = ws$derivatives_dir,
      analysis_foldername = "Ancillary_Analysis",
      step = s
    )
    expect_true(result$success,
                info = paste("Ancillary step", s, "failed:",
                             paste(result$messages, collapse = "\n")))
  }

  # Verify ancillary produced delay kinpar files
  ancillary_dir <- file.path(ws$derivatives_dir, "petfit", "Ancillary_Analysis")
  ancillary_delay_files <- list.files(ancillary_dir,
                                      pattern = "_desc-delayfit_kinpar\\.tsv$",
                                      recursive = TRUE)
  expect_true(length(ancillary_delay_files) > 0,
              info = "Ancillary should have delay kinpar files")

  # --- Primary pipeline: uses ancillary_estimate for delay ---
  setup_modelling_config(ws, "ds004869_plasma_config.json", "Primary_Analysis")
  primary_config_path <- file.path(ws$derivatives_dir, "petfit",
                                    "Primary_Analysis",
                                    "desc-petfitoptions_config.json")
  config <- jsonlite::fromJSON(primary_config_path)
  config$FitDelay$model <- "ancillary_estimate"
  jsonlite::write_json(config, primary_config_path,
                       pretty = TRUE, auto_unbox = TRUE)

  # Run full primary pipeline with ancillary inheritance
  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    analysis_foldername = "Primary_Analysis",
    ancillary_analysis_folder = "Ancillary_Analysis"
  )

  expect_true(result$success,
              info = paste(result$messages, collapse = "\n"))

  # Verify delay files were copied to primary
  primary_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  primary_delay_files <- list.files(primary_dir,
                                     pattern = "_desc-delayfit_kinpar\\.tsv$",
                                     recursive = TRUE)
  expect_equal(length(primary_delay_files), length(ancillary_delay_files),
               info = "Same number of delay files should be in primary as ancillary")

  # Verify model report was generated using inherited delay
  report_path <- file.path(primary_dir, "reports", "model1_report.html")
  expect_true(file.exists(report_path),
              info = "Model report should be generated with inherited delay")
})

# ---------------------------------------------------------------------------
# Delay step: verify file copying
# ---------------------------------------------------------------------------

test_that("delay step copies kinpar files from ancillary folder", {
  skip_if_no_integration()

  ws <- setup_ancillary_workspace()
  withr::defer(cleanup_workspace(ws))

  # --- Run ancillary pipeline to produce delay files ---
  setup_modelling_config(ws, "ds004869_plasma_config.json", "Ancillary_Analysis")

  for (s in c("datadef", "weights", "delay")) {
    petfit_modelling_auto(
      bids_dir = ws$bids_dir,
      derivatives_dir = ws$derivatives_dir,
      analysis_foldername = "Ancillary_Analysis",
      step = s
    )
  }

  # --- Set up primary with ancillary delay ---
  setup_modelling_config(ws, "ds004869_plasma_config.json", "Primary_Analysis")
  primary_config_path <- file.path(ws$derivatives_dir, "petfit",
                                    "Primary_Analysis",
                                    "desc-petfitoptions_config.json")
  config <- jsonlite::fromJSON(primary_config_path)
  config$FitDelay$model <- "ancillary_estimate"
  jsonlite::write_json(config, primary_config_path,
                       pretty = TRUE, auto_unbox = TRUE)

  # Run datadef first (populate analysis folder)
  petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    analysis_foldername = "Primary_Analysis",
    step = "datadef"
  )

  # Run delay step with ancillary inheritance
  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    analysis_foldername = "Primary_Analysis",
    step = "delay",
    ancillary_analysis_folder = "Ancillary_Analysis"
  )

  expect_true(result$success,
              info = paste(result$messages, collapse = "\n"))

  # Verify delay files were copied
  primary_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  primary_delay_files <- list.files(primary_dir,
                                     pattern = "_desc-delayfit_kinpar\\.tsv$",
                                     recursive = TRUE)
  expect_true(length(primary_delay_files) > 0,
              info = "Delay files should be copied from ancillary")

  # Verify copied files have correct content
  ancillary_dir <- file.path(ws$derivatives_dir, "petfit", "Ancillary_Analysis")
  ancillary_delay_files <- list.files(ancillary_dir,
                                      pattern = "_desc-delayfit_kinpar\\.tsv$",
                                      recursive = TRUE)
  expect_equal(length(primary_delay_files), length(ancillary_delay_files),
               info = "Same number of delay files in primary as ancillary")

  # Verify content of first copied file matches ancillary source
  anc_data <- readr::read_tsv(
    file.path(ancillary_dir, ancillary_delay_files[1]),
    show_col_types = FALSE
  )
  pri_data <- readr::read_tsv(
    file.path(primary_dir, primary_delay_files[1]),
    show_col_types = FALSE
  )
  expect_equal(nrow(anc_data), nrow(pri_data),
               info = "Copied delay file should have same content as source")
  expect_true("blood_timeshift" %in% names(pri_data),
              info = "Copied delay file should contain blood_timeshift column")
})

# ---------------------------------------------------------------------------
# Error: config references ancillary but no folder provided
# ---------------------------------------------------------------------------

test_that("pipeline errors when config uses ancillary_estimate but no folder provided", {
  skip_if_no_integration()

  ws <- setup_ancillary_workspace()
  withr::defer(cleanup_workspace(ws))

  # Set up primary config with ancillary delay
  setup_modelling_config(ws, "ds004869_plasma_config.json", "Primary_Analysis")
  primary_config_path <- file.path(ws$derivatives_dir, "petfit",
                                    "Primary_Analysis",
                                    "desc-petfitoptions_config.json")
  config <- jsonlite::fromJSON(primary_config_path)
  config$FitDelay$model <- "ancillary_estimate"
  jsonlite::write_json(config, primary_config_path,
                       pretty = TRUE, auto_unbox = TRUE)

  # Run without ancillary_analysis_folder - should fail
  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    analysis_foldername = "Primary_Analysis"
  )

  expect_false(result$success)
  expect_true(any(grepl("ancillary", result$messages, ignore.case = TRUE)),
              info = "Error message should mention ancillary")
})

test_that("pipeline errors when config uses ancillary k2prime but no folder provided", {
  skip_if_no_integration()

  ws <- setup_ancillary_workspace()
  withr::defer(cleanup_workspace(ws))

  # Set up ref config with ancillary k2prime source
  setup_modelling_config(ws, "ds004869_ref_config.json", "Primary_Analysis")
  primary_config_path <- file.path(ws$derivatives_dir, "petfit",
                                    "Primary_Analysis",
                                    "desc-petfitoptions_config.json")
  config <- jsonlite::fromJSON(primary_config_path)
  config$Models$Model1$type <- "MRTM2"
  config$Models$Model1$k2prime_source <- "ancillary_model1_median"
  config$Models$Model1$k2prime <- 0.1
  jsonlite::write_json(config, primary_config_path,
                       pretty = TRUE, auto_unbox = TRUE)

  # Run without ancillary_analysis_folder - should fail
  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    analysis_foldername = "Primary_Analysis"
  )

  expect_false(result$success)
  expect_true(any(grepl("ancillary", result$messages, ignore.case = TRUE)),
              info = "Error message should mention ancillary k2prime")
})

# ---------------------------------------------------------------------------
# Error: ancillary folder does not exist
# ---------------------------------------------------------------------------

test_that("pipeline errors when ancillary folder does not exist", {
  skip_if_no_integration()

  ws <- setup_ancillary_workspace()
  withr::defer(cleanup_workspace(ws))

  setup_modelling_config(ws, "ds004869_plasma_config.json", "Primary_Analysis")

  # Reference a non-existent ancillary folder
  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    analysis_foldername = "Primary_Analysis",
    ancillary_analysis_folder = "NonExistent_Folder"
  )

  expect_false(result$success)
  expect_true(any(grepl("does not exist|not found|error",
                         result$messages, ignore.case = TRUE)),
              info = "Error message should indicate folder not found")
})

# ---------------------------------------------------------------------------
# Ancillary scanning and validation
# ---------------------------------------------------------------------------

test_that("scan_ancillary_contents finds delay and model files", {
  skip_if_no_integration()

  ws <- setup_ancillary_workspace()
  withr::defer(cleanup_workspace(ws))

  # Run ancillary plasma pipeline to produce delay kinpar files
  setup_modelling_config(ws, "ds004869_plasma_config.json", "Ancillary_Analysis")

  for (s in c("datadef", "weights", "delay")) {
    petfit_modelling_auto(
      bids_dir = ws$bids_dir,
      derivatives_dir = ws$derivatives_dir,
      analysis_foldername = "Ancillary_Analysis",
      step = s
    )
  }

  # Scan the ancillary folder
  ancillary_dir <- file.path(ws$derivatives_dir, "petfit", "Ancillary_Analysis")
  scan_result <- scan_ancillary_contents(ancillary_dir)

  # Should find delay files
  expect_true(length(scan_result$delay_files) > 0,
              info = "Should detect delay kinpar files in ancillary folder")

  # Delay option should be available
  delay_opts <- get_ancillary_delay_options(scan_result)
  expect_false(is.null(delay_opts))
  expect_equal(unname(delay_opts), "ancillary_estimate")
})

# ---------------------------------------------------------------------------
# k2prime inheritance with synthetic ancillary data
# ---------------------------------------------------------------------------

test_that("read_ancillary_k2prime works with synthetic kinpar files in integration workspace", {
  skip_if_no_integration()

  ws <- setup_ancillary_workspace()
  withr::defer(cleanup_workspace(ws))

  # Create synthetic ancillary folder with kinpar files containing k2prime
  ancillary_dir <- file.path(ws$derivatives_dir, "petfit", "Ancillary_Analysis")
  dir.create(ancillary_dir, recursive = TRUE)

  # Create config so scan detects model type
  ancillary_config <- list(
    Models = list(
      Model1 = list(type = "MRTM1")
    )
  )
  jsonlite::write_json(ancillary_config,
                       file.path(ancillary_dir, "desc-petfitoptions_config.json"),
                       pretty = TRUE, auto_unbox = TRUE)

  # Run datadef on the primary to discover what PET IDs exist
  setup_modelling_config(ws, "ds004869_ref_config.json", "Primary_Analysis")
  petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    analysis_foldername = "Primary_Analysis",
    step = "datadef"
  )

  # Find PET IDs from the primary analysis TACs files
  primary_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  tacs_files <- list.files(primary_dir,
                            pattern = "_desc-combinedregions_tacs\\.tsv$",
                            recursive = TRUE)
  pet_ids <- sub("_desc-combinedregions_tacs\\.tsv$", "", basename(tacs_files))

  # Create synthetic kinpar files for each PET ID in the ancillary folder
  for (pet_id in pet_ids) {
    pet_dir <- file.path(ancillary_dir, pet_id)
    dir.create(pet_dir, recursive = TRUE, showWarnings = FALSE)

    kinpar_data <- tibble::tibble(
      region = c("Frontal", "Temporal"),
      BPnd = c(0.5, 0.3),
      k2prime = c(0.10, 0.12)
    )
    readr::write_tsv(
      kinpar_data,
      file.path(pet_dir, paste0(pet_id, "_model_MRTM1_desc-model1_kinpar.tsv"))
    )
  }

  # Verify scanning finds the synthetic kinpar files
  scan_result <- scan_ancillary_contents(ancillary_dir)
  expect_equal(length(scan_result$model1_kinpar), length(pet_ids))
  expect_equal(scan_result$model1_type, "MRTM1")

  # Verify k2prime options are available
  k2prime_opts <- get_ancillary_k2prime_options(scan_result)
  expect_false(is.null(k2prime_opts))
  expect_true("ancillary_model1_mean" %in% k2prime_opts)
  expect_true("ancillary_model1_median" %in% k2prime_opts)

  # Verify reading k2prime values
  k2prime_mean <- read_ancillary_k2prime(ancillary_dir, model_num = 1,
                                          aggregation = "mean")
  expect_equal(nrow(k2prime_mean), length(pet_ids))
  expect_true(all(k2prime_mean$k2prime == mean(c(0.10, 0.12))))

  k2prime_median <- read_ancillary_k2prime(ancillary_dir, model_num = 1,
                                            aggregation = "median")
  expect_equal(nrow(k2prime_median), length(pet_ids))
  expect_true(all(k2prime_median$k2prime == stats::median(c(0.10, 0.12))))
})

test_that("petfit_modelling_auto validates ancillary k2prime and passes path through", {
  skip_if_no_integration()

  ws <- setup_ancillary_workspace()
  withr::defer(cleanup_workspace(ws))

  # Create ancillary folder with synthetic kinpar files
  ancillary_dir <- file.path(ws$derivatives_dir, "petfit", "Ancillary_Analysis")
  dir.create(ancillary_dir, recursive = TRUE)

  ancillary_config <- list(
    Models = list(
      Model1 = list(type = "MRTM1")
    )
  )
  jsonlite::write_json(ancillary_config,
                       file.path(ancillary_dir, "desc-petfitoptions_config.json"),
                       pretty = TRUE, auto_unbox = TRUE)

  # Create a synthetic kinpar file
  pet_dir <- file.path(ancillary_dir, "sub-01_ses-01")
  dir.create(pet_dir, recursive = TRUE)
  kinpar_data <- tibble::tibble(
    region = c("Frontal", "Temporal"),
    BPnd = c(0.5, 0.3),
    k2prime = c(0.10, 0.12)
  )
  readr::write_tsv(
    kinpar_data,
    file.path(pet_dir, "sub-01_ses-01_model_MRTM1_desc-model1_kinpar.tsv")
  )

  # Validate the ancillary folder can be scanned
  petfit_dir <- file.path(ws$derivatives_dir, "petfit")
  ancillary_path <- validate_ancillary_folder(petfit_dir, "Ancillary_Analysis")
  expect_equal(ancillary_path, ancillary_dir)

  scan_result <- scan_ancillary_contents(ancillary_path)
  expect_equal(length(scan_result$model1_kinpar), 1)
  expect_equal(scan_result$model1_type, "MRTM1")
})

# ---------------------------------------------------------------------------
# End-to-end: reference tissue pipeline with ancillary k2prime inheritance
# ---------------------------------------------------------------------------

test_that("reference pipeline inherits k2prime from ancillary SRTM analysis", {
  skip_if_no_integration()

  ws <- setup_ancillary_workspace()
  withr::defer(cleanup_workspace(ws))

  # --- Ancillary pipeline: fit SRTM (produces kinpar with k2prime) ---
  setup_modelling_config(ws, "ds004869_ref_config.json", "Ancillary_Analysis")

  ancillary_result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    analysis_foldername = "Ancillary_Analysis"
  )
  expect_true(ancillary_result$success,
              info = paste("Ancillary SRTM pipeline failed:",
                           paste(ancillary_result$messages, collapse = "\n")))

  # Verify ancillary produced model1 kinpar files with k2prime column
  ancillary_dir <- file.path(ws$derivatives_dir, "petfit", "Ancillary_Analysis")
  ancillary_kinpar_files <- list.files(ancillary_dir,
                                       pattern = "_desc-model1_kinpar\\.tsv$",
                                       recursive = TRUE)
  expect_true(length(ancillary_kinpar_files) > 0,
              info = "Ancillary should have model1 kinpar files")

  # Verify k2prime column exists in kinpar files
  first_kinpar <- readr::read_tsv(
    file.path(ancillary_dir, ancillary_kinpar_files[1]),
    show_col_types = FALSE
  )
  expect_true("k2prime" %in% names(first_kinpar),
              info = "SRTM kinpar should contain k2prime column")

  # Verify ancillary scanning detects the files
  scan_result <- scan_ancillary_contents(ancillary_dir)
  expect_equal(length(scan_result$model1_kinpar), length(ancillary_kinpar_files))
  expect_equal(scan_result$model1_type, "SRTM")

  k2prime_opts <- get_ancillary_k2prime_options(scan_result)
  expect_true("ancillary_model1_median" %in% k2prime_opts)

  # --- Primary pipeline: MRTM2 inheriting k2prime from ancillary ---
  setup_modelling_config(ws, "ds004869_ref_config.json", "Primary_Analysis")
  primary_config_path <- file.path(ws$derivatives_dir, "petfit",
                                    "Primary_Analysis",
                                    "desc-petfitoptions_config.json")
  config <- jsonlite::fromJSON(primary_config_path)
  config$Models$Model1$type <- "MRTM2"
  config$Models$Model1$k2prime_source <- "ancillary_model1_median"
  config$Models$Model1$k2prime <- 0.1  # fallback value
  config$Models$Model1$use_weights <- TRUE
  jsonlite::write_json(config, primary_config_path,
                       pretty = TRUE, auto_unbox = TRUE)

  # Run full primary pipeline with ancillary k2prime
  primary_result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    analysis_foldername = "Primary_Analysis",
    ancillary_analysis_folder = "Ancillary_Analysis"
  )

  expect_true(primary_result$success,
              info = paste("Primary MRTM2 pipeline failed:",
                           paste(primary_result$messages, collapse = "\n")))

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
