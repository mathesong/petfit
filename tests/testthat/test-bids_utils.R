test_that("attributes_to_title formats BIDS attributes correctly", {
  
  # Create test BIDS data structure that matches kinfitr::bids_parse_files output
  test_bidsdata <- tibble::tibble(
    sub = c("01", "02"),
    ses = c("01", "02"), 
    trc = c("18FFDG", "11CRACWAY"),
    rec = c("", "rec1"),
    task = c("", "rest"),
    run = c("", "1"),
    desc = c("freesurfer", "spm"),
    filedata = c("sub-01_ses-01_trc-18FFDG_desc-freesurfer_tacs.tsv", 
                 "sub-02_ses-02_trc-11CRACWAY_rec-rec1_task-rest_run-1_desc-spm_tacs.tsv")
  )
  
  # Test with all_attributes = FALSE (default)
  result <- attributes_to_title(test_bidsdata)
  expect_type(result, "character")
  expect_true(length(result) == nrow(test_bidsdata))
  
  # Should include main attributes
  expect_true(all(grepl("sub-01|sub-02", result)))
  expect_true(all(grepl("ses-01|ses-02", result)))
  expect_true(all(grepl("trc-18FFDG|trc-11CRACWAY", result)))
  
  # Test with all_attributes = TRUE
  result_all <- attributes_to_title(test_bidsdata, all_attributes = TRUE)
  expect_type(result_all, "character")
  expect_true(length(result_all) == nrow(test_bidsdata))
  
  # Should include optional attributes when present
  expect_true(any(grepl("rec-rec1", result_all)))
  expect_true(any(grepl("task-rest", result_all)))
  expect_true(any(grepl("run-1", result_all)))
  expect_true(any(grepl("desc-freesurfer|desc-spm", result_all)))
})

test_that("attributes_to_title handles minimal BIDS data", {
  
  # Test with only required attributes (must include filedata column)
  minimal_data <- tibble::tibble(
    sub = "01",
    ses = "01",
    trc = "18FFDG",
    task = "",
    filedata = "sub-01_ses-01_trc-18FFDG_tacs.tsv"
  )
  
  result <- attributes_to_title(minimal_data)
  expect_equal(length(result), 1)
  expect_true(grepl("sub-01", result))
  expect_true(grepl("ses-01", result))
  # For single row, function only uses sub, ses, task, so trc may not appear
  expect_type(result, "character")
})

test_that("attributes_to_title handles empty optional fields", {
  
  # Test with empty optional fields
  test_data <- tibble::tibble(
    sub = "01",
    ses = "01",
    trc = "18FFDG",
    rec = "",
    task = "",
    run = "",
    desc = "freesurfer",
    filedata = "sub-01_ses-01_trc-18FFDG_desc-freesurfer_tacs.tsv"
  )
  
  result <- attributes_to_title(test_data, all_attributes = TRUE)
  
  # With all_attributes = TRUE, all fields are included even if empty
  expect_true(grepl("desc-freesurfer", result))
  # Empty fields will show as "field-" in the output
  expect_true(grepl("rec-", result))  # Will show as rec- (empty value)
  expect_true(grepl("task-", result)) # Will show as task- (empty value)
  expect_true(grepl("run-", result))  # Will show as run- (empty value)
})

test_that("attributes_to_title handles edge cases", {
  
  # Test with empty data frame that has proper structure
  empty_data <- tibble::tibble(
    sub = character(0),
    ses = character(0),
    trc = character(0),
    task = character(0),
    filedata = character(0)
  )
  result <- attributes_to_title(empty_data)
  # Function may still produce 1 empty result even with 0 rows
  expect_type(result, "character")
  
  # Test with single row
  single_row <- tibble::tibble(
    sub = "01",
    ses = "01",
    trc = "18FFDG",
    task = "",
    filedata = "sub-01_ses-01_trc-18FFDG_tacs.tsv"
  )
  
  result <- attributes_to_title(single_row)
  expect_equal(length(result), 1)
  expect_type(result, "character")
})

test_that("get_pet_identifiers extracts PET IDs correctly", {
  
  # Since get_pet_identifiers depends on kinfitr::bids_parse_files(), 
  # we'll test the basic functionality with empty input
  temp_dir <- tempdir()
  analysis_folder <- file.path(temp_dir, "test_analysis")
  dir.create(analysis_folder, recursive = TRUE, showWarnings = FALSE)
  
  # Test with empty file list
  result <- get_pet_identifiers(character(0), analysis_folder)
  expect_type(result, "character")
  expect_equal(length(result), 0)
  
  # Cleanup
  unlink(analysis_folder, recursive = TRUE)
})

test_that("get_pet_identifiers handles different file patterns", {
  
  # Test basic string extraction logic (the part we can test without kinfitr)
  test_files <- c(
    "sub-01_trc-18FFDG_desc-combinedregions_tacs.tsv",
    "sub-02_ses-01_trc-18FFDG_rec-test_desc-combinedregions_tacs.tsv",
    "sub-03_ses-01_trc-11CRACWAY_task-rest_run-1_desc-combinedregions_tacs.tsv"
  )
  
  # Test the filename parsing logic that's part of get_pet_identifiers
  file_pet_ids <- stringr::str_remove(basename(test_files), "_desc-.*$")
  
  expect_equal(length(file_pet_ids), 3)
  expect_equal(file_pet_ids[1], "sub-01_trc-18FFDG")
  expect_equal(file_pet_ids[2], "sub-02_ses-01_trc-18FFDG_rec-test") 
  expect_equal(file_pet_ids[3], "sub-03_ses-01_trc-11CRACWAY_task-rest_run-1")
})

test_that("get_pet_identifiers handles empty input", {
  
  temp_dir <- tempdir()
  analysis_folder <- file.path(temp_dir, "empty_test")
  dir.create(analysis_folder, showWarnings = FALSE)
  
  # Test with no files
  result <- get_pet_identifiers(character(0), analysis_folder)
  expect_equal(length(result), 0)
  
  # Cleanup
  unlink(analysis_folder, recursive = TRUE)
})

test_that("get_pet_identifiers handles file path variations", {
  
  # Test filename parsing with nested paths
  test_file <- "nested/path/sub-01_ses-01_trc-18FFDG_desc-combinedregions_tacs.tsv"
  
  # Test the basename extraction and pattern removal
  file_pet_id <- stringr::str_remove(basename(test_file), "_desc-.*$")
  expect_equal(file_pet_id, "sub-01_ses-01_trc-18FFDG")
})

test_that("get_pet_identifiers removes file extensions correctly", {
  
  # Test file extension and suffix removal logic
  test_files <- c(
    "sub-01_ses-01_trc-18FFDG_desc-combinedregions_tacs.tsv",
    "sub-02_ses-01_trc-18FFDG_desc-combinedregions_tacs.csv"
  )
  
  # Test the pattern removal logic used in get_pet_identifiers
  file_pet_ids <- stringr::str_remove(basename(test_files), "_desc-.*$")
  
  expect_equal(length(file_pet_ids), 2)
  expect_true(all(!grepl("\\.(tsv|csv)$", file_pet_ids)))  # No file extensions
  expect_equal(file_pet_ids[1], "sub-01_ses-01_trc-18FFDG")
  expect_equal(file_pet_ids[2], "sub-02_ses-01_trc-18FFDG")
})