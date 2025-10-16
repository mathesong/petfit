test_that("combine_single_region_tac works with valid inputs", {
  
  # Load setup helpers
  source(here::here("tests/testthat/fixtures/setup.R"))
  
  # Create test data
  tacs_data <- tibble::tibble(
    frame_start = c(0, 1, 2, 5, 10),
    frame_end = c(1, 2, 5, 10, 15),
    `Left-Cerebral-Cortex` = c(10, 20, 15, 12, 8),
    `Right-Cerebral-Cortex` = c(12, 22, 17, 14, 10),
    `Left-Hippocampus` = c(5, 10, 8, 6, 4)
  )
  
  morph_data <- tibble::tibble(
    name = c("Left-Cerebral-Cortex", "Right-Cerebral-Cortex", "Left-Hippocampus"),
    `volume-mm3` = c(50000, 52000, 4000)
  )
  
  constituent_regions <- c("Left-Cerebral-Cortex", "Right-Cerebral-Cortex")
  
  result <- combine_single_region_tac(tacs_data, morph_data, constituent_regions, "Cortex")
  
  # Check structure
  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 5)
  expect_true("TAC" %in% colnames(result))
  expect_true("volume-mm3" %in% colnames(result))
  expect_true("frame_dur" %in% colnames(result))
  expect_true("frame_mid" %in% colnames(result))
  
  # Check volume calculation
  expected_volume <- 50000 + 52000
  expect_equal(result$`volume-mm3`[1], expected_volume)
  
  # Check volume-weighted averaging (first time point)
  expected_tac_1 <- (10 * 50000 + 12 * 52000) / (50000 + 52000)
  expect_equal(result$TAC[1], expected_tac_1)
})

test_that("combine_single_region_tac handles missing regions gracefully", {
  
  source(here::here("tests/testthat/fixtures/setup.R"))
  
  tacs_data <- tibble::tibble(
    frame_start = c(0, 1),
    frame_end = c(1, 2),
    `Left-Cerebral-Cortex` = c(10, 20)
  )
  
  morph_data <- tibble::tibble(
    name = c("Left-Cerebral-Cortex"),
    `volume-mm3` = c(50000)
  )
  
  # Test with non-existent regions
  expect_warning(
    result <- combine_single_region_tac(tacs_data, morph_data, c("NonExistent"), "Test"),
    "No constituent regions found"
  )
  expect_equal(nrow(result), 0)
})

test_that("combine_single_region_tac handles invalid inputs", {
  
  source(here::here("tests/testthat/fixtures/setup.R"))
  
  # Test with NULL inputs
  expect_warning(
    result <- combine_single_region_tac(NULL, NULL, c("test"), "Test"),
    "TACs data is empty or NULL"
  )
  expect_equal(nrow(result), 0)
  
  # Test with empty data
  empty_tacs <- tibble::tibble()
  empty_morph <- tibble::tibble()
  
  expect_warning(
    result <- combine_single_region_tac(empty_tacs, empty_morph, c("test"), "Test"),
    "TACs data is empty or NULL"
  )
  expect_equal(nrow(result), 0)
})

test_that("extract_bids_attributes_from_filename works correctly", {
  
  # Test standard BIDS filename
  filename <- "sub-01_ses-02_trc-18FFDG_rec-something_task-rest_run-1_desc-freesurfer_tacs.tsv"
  result <- extract_bids_attributes_from_filename(filename)
  
  expect_type(result, "list")
  expect_equal(result$sub, "01")
  expect_equal(result$ses, "02")
  expect_equal(result$trc, "18FFDG")
  expect_equal(result$rec, "something")
  expect_equal(result$task, "rest")
  expect_equal(result$run, "1")
  expect_equal(result$desc, "freesurfer")
  expect_equal(result$pet, "sub-01_ses-02_trc-18FFDG_rec-something_task-rest_run-1")
})

test_that("extract_bids_attributes_from_filename handles minimal filename", {
  
  filename <- "sub-01_trc-18FFDG_tacs.tsv"
  result <- extract_bids_attributes_from_filename(filename)
  
  expect_equal(result$sub, "01")
  expect_equal(result$trc, "18FFDG")
  expect_equal(result$ses, "")
  expect_equal(result$rec, "")
  expect_equal(result$task, "")
  expect_equal(result$run, "")
  expect_equal(result$desc, "")
})

test_that("load_participant_data works with valid BIDS structure", {
  
  source(here::here("tests/testthat/fixtures/setup.R"))
  
  # Create temporary BIDS structure
  temp_dir <- tempdir()
  bids_dir <- create_test_bids_structure(temp_dir, n_subjects = 2, n_sessions = 1)
  
  result <- load_participant_data(bids_dir)
  
  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 2)
  expect_true("sub" %in% colnames(result))
  expect_true("age" %in% colnames(result))
  expect_true("sex" %in% colnames(result))
  expect_true("bodyweight" %in% colnames(result))
  
  # Check participant ID format (sub-01 -> 01)
  expect_true(all(result$sub %in% c("01", "02")))
  
  # Cleanup
  cleanup_test_dirs(bids_dir)
})

test_that("load_participant_data handles missing files gracefully", {
  
  temp_dir <- tempdir()
  fake_bids_dir <- file.path(temp_dir, "nonexistent_bids")
  
  # Should return empty tibble for non-existent directory
  result <- load_participant_data(fake_bids_dir)
  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 0)
})

test_that("extract_pet_metadata works correctly", {
  
  source(here::here("tests/testthat/fixtures/setup.R"))
  
  # Create temporary BIDS structure
  temp_dir <- tempdir()
  bids_dir <- create_test_bids_structure(temp_dir, n_subjects = 1, n_sessions = 1)
  
  result <- extract_pet_metadata(bids_dir, "01", "01", "18FFDG")
  
  expect_type(result, "list")
  expect_true("InjectedRadioactivity" %in% names(result))
  expect_true(result$InjectedRadioactivity > 0)
  
  # Cleanup
  cleanup_test_dirs(bids_dir)
})

test_that("create_petfit_regions_files works with valid input", {
  
  source(here::here("tests/testthat/fixtures/setup.R"))
  
  # Create temporary structure
  temp_dir <- tempdir()
  bids_dir <- create_test_bids_structure(temp_dir, n_subjects = 2, n_sessions = 1)
  derivatives_folder <- file.path(bids_dir, "derivatives")
  
  petfit_regions_file <- file.path(bids_dir, "code", "petfit", "petfit_regions.tsv")
  
  result <- create_petfit_regions_files(petfit_regions_file, derivatives_folder)
  
  expect_type(result, "list")
  expect_true(length(result) > 0)
  
  # Check that files were created
  expect_true(any(sapply(result, file.exists)))
  
  # Cleanup
  cleanup_test_dirs(bids_dir)
})

test_that("combine_regions_from_files processes data correctly", {
  
  source(here::here("tests/testthat/fixtures/setup.R"))
  
  # Create temporary structure  
  temp_dir <- tempdir()
  bids_dir <- create_test_bids_structure(temp_dir, n_subjects = 1, n_sessions = 1)
  derivatives_folder <- file.path(bids_dir, "derivatives")
  
  # Get TACs file path
  tacs_files <- list.files(
    file.path(derivatives_folder, "petfit", "sub-01", "ses-01"),
    pattern = "*_tacs.tsv", 
    full.names = TRUE
  )
  
  expect_true(length(tacs_files) > 0)
  
  tacs_relative_path <- gsub(paste0(derivatives_folder, "/"), "", tacs_files[1])
  
  # Create regions file
  regions_data <- tibble::tibble(
    name = "TestRegion",
    constituent_regions = "Left-Cerebral-Cortex;Right-Cerebral-Cortex"
  )
  
  temp_regions_file <- file.path(tempdir(), "test_regions.tsv")
  readr::write_tsv(regions_data, temp_regions_file)
  
  # Test the function
  expect_no_error({
    result <- combine_regions_from_files(
      derivatives_folder, 
      tacs_relative_path,
      temp_regions_file
    )
  })
  
  # Cleanup
  cleanup_test_dirs(bids_dir)
  file.remove(temp_regions_file)
})

test_that("calculate_segmentation_mean_tac computes volume-weighted means", {
  
  source(here::here("tests/testthat/fixtures/setup.R"))
  
  # Create test structure
  temp_dir <- tempdir()
  bids_dir <- create_test_bids_structure(temp_dir, n_subjects = 1, n_sessions = 1)
  derivatives_folder <- file.path(bids_dir, "derivatives")
  
  tacs_files <- list.files(
    file.path(derivatives_folder, "petfit", "sub-01", "ses-01"),
    pattern = "*_tacs.tsv", 
    full.names = TRUE
  )
  
  tacs_relative_path <- gsub(paste0(derivatives_folder, "/"), "", tacs_files[1])
  
  result <- calculate_segmentation_mean_tac(
    derivatives_folder,
    tacs_relative_path, 
    "freesurfer"
  )
  
  expect_s3_class(result, "tbl_df")
  expect_true("seg_meanTAC" %in% colnames(result))
  expect_true(all(result$seg_meanTAC >= 0))
  
  # Cleanup
  cleanup_test_dirs(bids_dir)
})

test_that("create_petfit_combined_tacs integrates all components", {
  
  source(here::here("tests/testthat/fixtures/setup.R"))
  
  # Create comprehensive test structure
  temp_dir <- tempdir()
  bids_dir <- create_test_bids_structure(temp_dir, n_subjects = 2, n_sessions = 1)
  derivatives_folder <- file.path(bids_dir, "derivatives")
  output_dir <- file.path(derivatives_folder, "petfit")
  
  petfit_regions_file <- file.path(bids_dir, "code", "petfit", "petfit_regions.tsv")
  
  result <- create_petfit_combined_tacs(
    petfit_regions_file,
    derivatives_folder,
    output_dir,
    bids_dir
  )
  
  expect_type(result, "character")
  expect_true(file.exists(result))
  
  # Read the combined file and check structure
  combined_data <- readr::read_tsv(result, show_col_types = FALSE)
  
  expect_s3_class(combined_data, "tbl_df")
  expect_true(nrow(combined_data) > 0)
  
  # Check required columns
  required_cols <- c("sub", "ses", "trc", "pet", "InjectedRadioactivity", 
                     "bodyweight", "region", "volume_mm3", "frame_start", 
                     "frame_end", "frame_dur", "frame_mid", "TAC")
  expect_true(all(required_cols %in% colnames(combined_data)))
  
  # Check data integrity
  expect_true(all(!is.na(combined_data$TAC)))
  expect_true(all(combined_data$volume_mm3 > 0))
  expect_true(all(combined_data$InjectedRadioactivity > 0))
  
  # Cleanup
  cleanup_test_dirs(bids_dir)
})

test_that("find_tacs_folders identifies TACs directories correctly", {
  
  source(here::here("tests/testthat/fixtures/setup.R"))
  
  temp_dir <- tempdir()
  bids_dir <- create_test_bids_structure(temp_dir, n_subjects = 2, n_sessions = 1)
  derivatives_folder <- file.path(bids_dir, "derivatives")
  
  result <- find_tacs_folders(derivatives_folder)
  
  expect_type(result, "character")
  expect_true(length(result) >= 2) # At least 2 subject/session combinations
  expect_true(all(dir.exists(result)))
  
  # Cleanup
  cleanup_test_dirs(bids_dir)
})

test_that("summarise_tacs_descriptions extracts BIDS attributes", {

  source(here::here("tests/testthat/fixtures/setup.R"))

  temp_dir <- tempdir()
  bids_dir <- create_test_bids_structure(temp_dir, n_subjects = 1, n_sessions = 1)

  tacs_dir <- file.path(bids_dir, "derivatives", "petfit", "sub-01", "ses-01")

  result <- summarise_tacs_descriptions(tacs_dir)

  expect_s3_class(result, "tbl_df")
  expect_true(nrow(result) >= 1)
  expect_true("description" %in% colnames(result))
  expect_true("freesurfer" %in% result$description)

  # Cleanup
  cleanup_test_dirs(bids_dir)
})

test_that("process_all_petfit_regions handles full workflow", {
  
  source(here::here("tests/testthat/fixtures/setup.R"))
  
  # Create test structure
  temp_dir <- tempdir()
  bids_dir <- create_test_bids_structure(temp_dir, n_subjects = 2, n_sessions = 1)
  derivatives_folder <- file.path(bids_dir, "derivatives")
  output_folder <- file.path(derivatives_folder, "petfit")
  
  petfit_regions_file <- file.path(bids_dir, "code", "petfit", "petfit_regions.tsv")
  
  result <- process_all_petfit_regions(petfit_regions_file, derivatives_folder, output_folder)
  
  expect_type(result, "list")
  expect_true("combined_files" %in% names(result))
  expect_true("regions_files" %in% names(result))
  
  # Check that combined TACs file was created
  expect_true(length(result$combined_files) > 0)
  expect_true(all(file.exists(result$combined_files)))
  
  # Cleanup
  cleanup_test_dirs(bids_dir)
})