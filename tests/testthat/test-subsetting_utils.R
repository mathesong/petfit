test_that("parse_semicolon_values handles normal input", {
  
  # Test basic semicolon separation
  result <- parse_semicolon_values("value1;value2;value3")
  expect_equal(result, c("value1", "value2", "value3"))
  
  # Test with spaces
  result <- parse_semicolon_values("value1 ; value2 ; value3")
  expect_equal(result, c("value1", "value2", "value3"))
  
  # Test single value
  result <- parse_semicolon_values("single_value")
  expect_equal(result, "single_value")
})

test_that("parse_semicolon_values handles edge cases", {
  
  # Test NULL input
  result <- parse_semicolon_values(NULL)
  expect_null(result)
  
  # Test empty string
  result <- parse_semicolon_values("")
  expect_null(result)
  
  # Test string with only semicolons
  result <- parse_semicolon_values(";;")
  expect_null(result)
  
  # Test mixed empty and valid values
  result <- parse_semicolon_values("value1;;value2;")
  expect_equal(result, c("value1", "value2"))
  
  # Test whitespace only
  result <- parse_semicolon_values("   ;   ;   ")
  expect_null(result)
})

test_that("parse_semicolon_values handles special characters", {
  
  # Test values with special characters
  result <- parse_semicolon_values("sub-01;ses-02;task_rest")
  expect_equal(result, c("sub-01", "ses-02", "task_rest"))
  
  # Test values with numbers
  result <- parse_semicolon_values("18FFDG;11CRACWAY;15OH2O")
  expect_equal(result, c("18FFDG", "11CRACWAY", "15OH2O"))
})

test_that("subset_combined_tacs filters data correctly", {
  
  # Create test data
  test_data <- tibble::tibble(
    sub = c("01", "02", "01", "02"),
    ses = c("01", "01", "02", "02"),
    trc = c("18FFDG", "18FFDG", "11CRACWAY", "11CRACWAY"),
    rec = c("", "", "rec1", "rec1"),
    task = c("", "rest", "", "rest"),
    run = c("", "", "1", "1"),
    desc = c("freesurfer", "freesurfer", "freesurfer", "spm"),
    region = c("cortex", "cortex", "cortex", "cortex"),
    TAC = c(100, 110, 90, 95),
    frame_start = c(0, 0, 0, 0)
  )
  
  # Test subject filtering
  subset_params <- list(sub = c("01"))
  result <- subset_combined_tacs(test_data, subset_params)
  expect_equal(unique(result$sub), "01")
  expect_equal(nrow(result), 2)
  
  # Test session filtering
  subset_params <- list(ses = c("01"))
  result <- subset_combined_tacs(test_data, subset_params)
  expect_equal(unique(result$ses), "01")
  expect_equal(nrow(result), 2)
  
  # Test tracer filtering
  subset_params <- list(trc = c("18FFDG"))
  result <- subset_combined_tacs(test_data, subset_params)
  expect_equal(unique(result$trc), "18FFDG")
  expect_equal(nrow(result), 2)
})

test_that("subset_combined_tacs handles multiple filters", {
  
  test_data <- tibble::tibble(
    sub = c("01", "02", "01", "02"),
    ses = c("01", "01", "02", "02"),
    trc = c("18FFDG", "18FFDG", "11CRACWAY", "11CRACWAY"),
    rec = c("", "", "rec1", "rec1"),
    task = c("", "rest", "", "rest"),
    run = c("", "", "1", "1"),
    desc = c("freesurfer", "freesurfer", "freesurfer", "spm"),
    region = c("cortex", "cortex", "cortex", "cortex"),
    TAC = c(100, 110, 90, 95),
    frame_start = c(0, 0, 0, 0)
  )
  
  # Test combined filtering
  subset_params <- list(
    sub = c("01"), 
    trc = c("18FFDG")
  )
  result <- subset_combined_tacs(test_data, subset_params)
  expect_equal(nrow(result), 1)
  expect_equal(result$sub, "01")
  expect_equal(result$trc, "18FFDG")
  expect_equal(result$ses, "01")
  
  # Test filtering with no matches
  subset_params <- list(
    sub = c("99"), 
    trc = c("18FFDG")
  )
  result <- subset_combined_tacs(test_data, subset_params)
  expect_equal(nrow(result), 0)
})

test_that("subset_combined_tacs handles optional BIDS entities", {
  
  test_data <- tibble::tibble(
    sub = c("01", "02"),
    ses = c("01", "01"),
    trc = c("18FFDG", "18FFDG"),
    rec = c("", "rec1"),
    task = c("", "rest"),
    run = c("", "1"),
    desc = c("freesurfer", "spm"),
    region = c("cortex", "cortex"),
    TAC = c(100, 110),
    frame_start = c(0, 0)
  )
  
  # Test rec filtering (including empty values)
  subset_params <- list(rec = c(""))
  result <- subset_combined_tacs(test_data, subset_params)
  expect_equal(nrow(result), 1)
  expect_equal(result$rec, "")
  
  # Test task filtering
  subset_params <- list(task = c("rest"))
  result <- subset_combined_tacs(test_data, subset_params)
  expect_equal(nrow(result), 1)
  expect_equal(result$task, "rest")
  
  # Test run filtering
  subset_params <- list(run = c("1"))
  result <- subset_combined_tacs(test_data, subset_params)
  expect_equal(nrow(result), 1)
  expect_equal(result$run, "1")
  
  # Note: desc filtering not implemented in subset_combined_tacs function
  # Test that desc column exists in result but isn't filtered
  subset_params <- list()  # No filtering
  result <- subset_combined_tacs(test_data, subset_params)
  expect_equal(nrow(result), 2)  # Should return all rows
  expect_true("desc" %in% colnames(result))
})

test_that("subset_combined_tacs handles region filtering", {
  
  test_data <- tibble::tibble(
    sub = c("01", "01", "01"),
    ses = c("01", "01", "01"),
    trc = c("18FFDG", "18FFDG", "18FFDG"),
    rec = c("", "", ""),
    task = c("", "", ""),
    run = c("", "", ""),
    desc = c("freesurfer", "freesurfer", "freesurfer"),
    region = c("cortex", "hippocampus", "striatum"),
    TAC = c(100, 110, 90),
    frame_start = c(0, 0, 0)
  )
  
  # Test region filtering
  subset_params <- list(regions = c("cortex", "hippocampus"))
  result <- subset_combined_tacs(test_data, subset_params)
  expect_equal(nrow(result), 2)
  expect_true(all(result$region %in% c("cortex", "hippocampus")))
})

test_that("subset_combined_tacs handles invalid inputs", {
  
  # Test NULL input
  result <- subset_combined_tacs(NULL, list())
  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 0)
  
  # Test empty data
  empty_data <- tibble::tibble()
  result <- subset_combined_tacs(empty_data, list())
  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 0)
  
  # Test with NULL subset_params (should return original data)
  test_data <- tibble::tibble(
    sub = "01",
    ses = "01", 
    trc = "18FFDG",
    TAC = 100
  )
  result <- subset_combined_tacs(test_data, list())
  expect_equal(result, test_data)
})

test_that("create_individual_tacs_files creates correct file structure", {
  
  # Load setup helpers
  source(here::here("tests/testthat/fixtures/setup.R"))
  
  # Create test data with required columns (sub, ses, pet)
  test_data <- tibble::tibble(
    sub = c("01", "01", "02"),
    ses = c("01", "01", "01"),
    pet = c("sub-01_ses-01_trc-18FFDG", "sub-01_ses-01_trc-18FFDG", "sub-02_ses-01_trc-18FFDG"),
    region = c("cortex", "hippocampus", "cortex"),
    volume_mm3 = c(50000, 4000, 52000),
    InjectedRadioactivity = c(400000, 400000, 450000),
    bodyweight = c(70, 70, 65),
    frame_start = c(0, 0, 0),
    frame_end = c(1, 1, 1),
    frame_dur = c(1, 1, 1),
    frame_mid = c(0.5, 0.5, 0.5),
    TAC = c(100, 80, 105)
  )
  
  # Create temporary output directory
  temp_dir <- file.path(tempdir(), "test_output")
  dir.create(temp_dir, showWarnings = FALSE)
  
  result <- create_individual_tacs_files(test_data, temp_dir)
  
  expect_type(result, "list")
  expect_true("file_paths" %in% names(result))
  expect_true(length(result$file_paths) >= 2) # At least 2 unique PET files
  
  # Check that files were created
  expect_true(all(file.exists(result$file_paths)))
  
  # Check file naming convention
  expect_true(all(grepl("_desc-combinedregions_tacs\\.tsv$", basename(result$file_paths))))
  
  # Read one file and check structure
  test_file_data <- readr::read_tsv(result$file_paths[1], show_col_types = FALSE)
  expect_s3_class(test_file_data, "tbl_df")
  
  required_cols <- c("pet", "region", "volume_mm3", "InjectedRadioactivity", 
                     "bodyweight", "frame_start", "frame_end", "frame_dur", 
                     "frame_mid", "TAC")
  expect_true(all(required_cols %in% colnames(test_file_data)))
  
  # Check column order (pet should be first)
  expect_equal(colnames(test_file_data)[1], "pet")
  
  # Cleanup
  unlink(temp_dir, recursive = TRUE)
})

test_that("create_individual_tacs_files handles edge cases", {
  
  # Test with empty data
  empty_data <- tibble::tibble()
  temp_dir <- file.path(tempdir(), "test_empty")
  dir.create(temp_dir, showWarnings = FALSE)
  
  result <- create_individual_tacs_files(empty_data, temp_dir)
  expect_type(result, "list")
  expect_true("files_created" %in% names(result))
  expect_equal(result$files_created, 0)
  
  # Cleanup
  unlink(temp_dir, recursive = TRUE)
})

test_that("create_individual_tacs_files creates proper directory structure", {
  
  source(here::here("tests/testthat/fixtures/setup.R"))
  
  # Test data with nested directory structure
  test_data <- tibble::tibble(
    sub = "01",
    ses = "02", 
    pet = "sub-01_ses-02_trc-11CRACWAY_rec-test",
    region = "cortex",
    volume_mm3 = 50000,
    InjectedRadioactivity = 400000,
    bodyweight = 70,
    frame_start = 0,
    frame_end = 1,
    frame_dur = 1,
    frame_mid = 0.5,
    TAC = 100
  )
  
  temp_dir <- file.path(tempdir(), "test_structure")
  dir.create(temp_dir, showWarnings = FALSE)
  
  result <- create_individual_tacs_files(test_data, temp_dir)
  
  expect_true(length(result$file_paths) == 1)
  expect_true(file.exists(result$file_paths[1]))
  
  # Check that the file is in the correct subdirectory structure
  expected_path <- file.path(temp_dir, "sub-01", "ses-02", "pet", "sub-01_ses-02_trc-11CRACWAY_rec-test_desc-combinedregions_tacs.tsv")
  expect_equal(normalizePath(result$file_paths[1]), normalizePath(expected_path))
  
  # Cleanup
  unlink(temp_dir, recursive = TRUE)
})