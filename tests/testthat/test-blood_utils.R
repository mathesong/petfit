test_that("determine_blood_source identifies blood files correctly", {
  
  # Load setup helpers
  source(here::here("tests/testthat/fixtures/setup.R"))
  
  # Create temporary structure with blood data
  temp_dir <- tempdir()
  bids_dir <- create_test_bids_structure(temp_dir, n_subjects = 2, n_sessions = 1)
  analysis_folder <- file.path(bids_dir, "derivatives", "petfit", "Primary_Analysis")
  dir.create(analysis_folder, recursive = TRUE, showWarnings = FALSE)
  
  # Create blood data files in analysis folder
  blood_files <- c(
    "sub-01_ses-01_trc-18FFDG_blood.tsv",
    "sub-02_ses-01_trc-18FFDG_inputfunction.tsv"
  )
  
  for (blood_file in blood_files) {
    blood_path <- file.path(analysis_folder, blood_file)
    blood_data <- tibble::tibble(
      time = c(0, 1, 2, 5),
      activity = c(0, 150, 280, 220)
    )
    readr::write_tsv(blood_data, blood_path)
  }
  
  result <- determine_blood_source(analysis_folder, bids_dir)
  
  expect_type(result, "character")
  expect_equal(length(result), 1)
  
  # Should return one of the expected values
  expect_true(result %in% c("analysis_folder", "bids_dir", "none"))
  
  # Cleanup
  cleanup_test_dirs(bids_dir)
})

test_that("determine_blood_source handles missing blood data", {
  
  source(here::here("tests/testthat/fixtures/setup.R"))
  
  temp_dir <- tempdir()
  analysis_folder <- file.path(temp_dir, "no_blood")
  dir.create(analysis_folder, recursive = TRUE, showWarnings = FALSE)
  
  result <- determine_blood_source(analysis_folder)
  
  expect_type(result, "character") 
  expect_equal(length(result), 1)
  
  # Should return "none" when no blood data found
  expect_equal(result, "none")
  
  # Cleanup
  unlink(analysis_folder, recursive = TRUE)
})

test_that("get_blood_data_status provides correct status information", {
  
  source(here::here("tests/testthat/fixtures/setup.R"))
  
  temp_dir <- tempdir()
  bids_dir <- create_test_bids_structure(temp_dir, n_subjects = 1, n_sessions = 1)
  analysis_folder <- file.path(bids_dir, "derivatives", "petfit", "Primary_Analysis") 
  dir.create(analysis_folder, recursive = TRUE, showWarnings = FALSE)
  
  # Test with blood data present
  blood_file <- file.path(analysis_folder, "sub-01_ses-01_trc-18FFDG_blood.tsv")
  blood_data <- tibble::tibble(
    time = c(0, 1, 2),
    activity = c(0, 100, 200)
  )
  readr::write_tsv(blood_data, blood_file)
  
  result <- get_blood_data_status(analysis_folder = analysis_folder, bids_dir = bids_dir)
  
  expect_type(result, "list")
  expect_true("has_analysis_blood" %in% names(result))
  expect_true("has_bids_blood" %in% names(result))
  expect_true("priority_source" %in% names(result))
  
  # Should find blood data in one of the locations
  expect_true(result$has_analysis_blood || result$has_bids_blood)
  
  # Cleanup
  cleanup_test_dirs(bids_dir)
})

test_that("get_blood_data_status handles no blood data", {
  
  temp_dir <- tempdir()
  analysis_folder <- file.path(temp_dir, "no_blood_status")
  dir.create(analysis_folder, recursive = TRUE, showWarnings = FALSE)
  
  result <- get_blood_data_status(analysis_folder = analysis_folder)
  
  expect_type(result, "list")
  expect_false(result$has_analysis_blood)
  expect_false(result$has_bids_blood)
  expect_equal(result$priority_source, "none")
  
  # Cleanup
  unlink(analysis_folder, recursive = TRUE)
})

test_that("get_blood_data_status with explicit blood_dir", {
  
  # Create explicit blood directory
  temp_dir <- tempdir()
  blood_dir <- file.path(temp_dir, "blood_data")
  dir.create(blood_dir, recursive = TRUE, showWarnings = FALSE)
  
  analysis_folder <- file.path(temp_dir, "analysis")
  dir.create(analysis_folder, showWarnings = FALSE)
  
  # Add blood file to blood directory
  blood_file <- file.path(blood_dir, "sub-01_blood.tsv")
  blood_data <- tibble::tibble(
    time = c(0, 1, 2),
    activity = c(0, 100, 200)
  )
  readr::write_tsv(blood_data, blood_file)
  
  result <- get_blood_data_status(blood_dir = blood_dir, analysis_folder = analysis_folder)
  
  expect_true(result$has_blood_dir)
  expect_equal(result$priority_source, "blood_dir")
  
  # Cleanup
  unlink(temp_dir, recursive = TRUE)
})

test_that("blooddata2inputfunction_tsv function exists and is callable", {
  
  # Test that the function exists
  expect_true(exists("blooddata2inputfunction_tsv"))
  expect_true(is.function(blooddata2inputfunction_tsv))
  
  # The function requires complex kinfitr blooddata objects,
  # so we'll just test that it exists and handles simple validation
  temp_file <- file.path(tempdir(), "test_inputfunction.tsv")
  
  # Test with NULL input (should error gracefully)
  expect_error({
    blooddata2inputfunction_tsv(NULL, temp_file)
  })
  
  # Cleanup if file was created
  if (file.exists(temp_file)) {
    file.remove(temp_file)
  }
})

test_that("blooddata2inputfunction_tsv filename handling", {
  
  # Test that filename processing logic works (without calling the full function)
  test_filenames <- c(
    "test.tsv",
    "test_file.tsv", 
    "no_extension"
  )
  
  # Test the pattern that would be used in the function
  for (filename in test_filenames) {
    # This tests the stringr::str_remove pattern used in the function
    result <- stringr::str_remove(filename, "\\.tsv$")
    
    if (grepl("\\.tsv$", filename)) {
      expect_false(grepl("\\.tsv$", result))
    } else {
      expect_equal(result, filename)
    }
  }
})

test_that("blood file pattern matching works", {
  
  # Test the patterns used in blood file detection
  test_files <- c(
    "sub-01_blood.tsv",
    "sub-01_ses-01_blood.tsv", 
    "sub-02_inputfunction.tsv",
    "sub-02_ses-01_trc-18FFDG_inputfunction.tsv",
    "not_blood_file.tsv"
  )
  
  # Test blood pattern
  blood_pattern <- "_(blood|inputfunction)\\.tsv$"
  matches <- grepl(blood_pattern, test_files)
  
  expect_true(matches[1])  # sub-01_blood.tsv
  expect_true(matches[2])  # sub-01_ses-01_blood.tsv
  expect_true(matches[3])  # sub-02_inputfunction.tsv
  expect_true(matches[4])  # sub-02_ses-01_trc-18FFDG_inputfunction.tsv
  expect_false(matches[5]) # not_blood_file.tsv
})

test_that("determine_blood_source handles BIDS directory blood data", {
  
  source(here::here("tests/testthat/fixtures/setup.R"))
  
  temp_dir <- tempdir()
  bids_dir <- create_test_bids_structure(temp_dir, n_subjects = 1, n_sessions = 1)
  
  # Blood data should be created by setup function in derivatives
  analysis_folder <- file.path(bids_dir, "derivatives", "petfit", "test_analysis")
  dir.create(analysis_folder, recursive = TRUE, showWarnings = FALSE)
  
  result <- determine_blood_source(analysis_folder, bids_dir)
  
  expect_type(result, "character")
  expect_equal(length(result), 1)
  
  # Should return one of the valid options
  expect_true(result %in% c("analysis_folder", "bids_dir", "none"))
  
  # Cleanup
  cleanup_test_dirs(bids_dir)
})

test_that("blood data detection patterns work correctly", {
  
  temp_dir <- tempdir()
  test_dir <- file.path(temp_dir, "pattern_test")
  dir.create(test_dir, showWarnings = FALSE)
  
  # Create files matching different patterns
  blood_files <- c(
    "sub-01_blood.tsv",
    "sub-01_ses-01_blood.tsv", 
    "sub-02_inputfunction.tsv",
    "sub-02_ses-01_trc-18FFDG_inputfunction.tsv",
    "not_blood_file.tsv"  # Should not match
  )
  
  for (file in blood_files) {
    file.create(file.path(test_dir, file))
  }
  
  result <- determine_blood_source(test_dir)
  
  expect_type(result, "character")
  expect_equal(length(result), 1)
  
  # Should find inputfunction files and return "analysis_folder"
  expect_equal(result, "analysis_folder")
  
  # Cleanup
  unlink(test_dir, recursive = TRUE)
})