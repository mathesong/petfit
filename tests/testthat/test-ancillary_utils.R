# Tests for ancillary analysis folder utilities

test_that("parse_ancillary_k2prime_source parses valid strings", {
  result <- parse_ancillary_k2prime_source("ancillary_model1_median")
  expect_equal(result$model_num, 1L)
  expect_equal(result$aggregation, "median")

  result <- parse_ancillary_k2prime_source("ancillary_model2_mean")
  expect_equal(result$model_num, 2L)
  expect_equal(result$aggregation, "mean")

  result <- parse_ancillary_k2prime_source("ancillary_model3_median")
  expect_equal(result$model_num, 3L)
  expect_equal(result$aggregation, "median")
})

test_that("parse_ancillary_k2prime_source rejects invalid strings", {
  expect_error(parse_ancillary_k2prime_source("inherit_model1_mean"),
               "Invalid ancillary k2prime source string")

  expect_error(parse_ancillary_k2prime_source("set"),
               "Invalid ancillary k2prime source string")

  expect_error(parse_ancillary_k2prime_source(NULL),
               "Invalid ancillary k2prime source string")

  expect_error(parse_ancillary_k2prime_source("ancillary_model1_regional"),
               "Could not parse ancillary k2prime source string")
})

test_that("validate_ancillary_folder rejects full paths", {
  expect_error(validate_ancillary_folder("/tmp", "/full/path/to/folder"),
               "subfolder name")

  expect_error(validate_ancillary_folder("/tmp", "path/with/slashes"),
               "subfolder name")
})

test_that("validate_ancillary_folder rejects empty strings", {
  expect_error(validate_ancillary_folder("/tmp", ""),
               "must be provided")

  expect_error(validate_ancillary_folder("/tmp", NULL),
               "must be provided")
})

test_that("validate_ancillary_folder works with existing folder", {
  temp_dir <- tempdir()
  petfit_dir <- file.path(temp_dir, "test_petfit_validate")
  ancillary_dir <- file.path(petfit_dir, "Ancillary_Analysis")

  dir.create(ancillary_dir, recursive = TRUE, showWarnings = FALSE)
  withr::defer(unlink(petfit_dir, recursive = TRUE))

  result <- validate_ancillary_folder(petfit_dir, "Ancillary_Analysis")
  expect_equal(result, ancillary_dir)
})

test_that("validate_ancillary_folder rejects non-existent folder", {
  temp_dir <- tempdir()
  petfit_dir <- file.path(temp_dir, "test_petfit_validate2")
  dir.create(petfit_dir, recursive = TRUE, showWarnings = FALSE)
  withr::defer(unlink(petfit_dir, recursive = TRUE))

  expect_error(validate_ancillary_folder(petfit_dir, "NonExistent_Folder"),
               "does not exist")
})

test_that("scan_ancillary_contents returns empty for empty folder", {
  temp_dir <- tempdir()
  ancillary_dir <- file.path(temp_dir, "test_scan_empty")
  dir.create(ancillary_dir, recursive = TRUE, showWarnings = FALSE)
  withr::defer(unlink(ancillary_dir, recursive = TRUE))

  result <- scan_ancillary_contents(ancillary_dir)
  expect_equal(length(result$delay_files), 0)
  expect_equal(length(result$model1_kinpar), 0)
  expect_equal(length(result$model2_kinpar), 0)
  expect_equal(length(result$model3_kinpar), 0)
})

test_that("scan_ancillary_contents finds delay files", {
  temp_dir <- tempdir()
  ancillary_dir <- file.path(temp_dir, "test_scan_delay")
  pet_dir <- file.path(ancillary_dir, "sub-01")
  dir.create(pet_dir, recursive = TRUE, showWarnings = FALSE)
  withr::defer(unlink(ancillary_dir, recursive = TRUE))

  # Create a mock delay file
  writeLines("pet\tregion\tinpshift\nsub-01\tFrontal\t0.05",
             file.path(pet_dir, "sub-01_desc-delayfit_kinpar.tsv"))

  result <- scan_ancillary_contents(ancillary_dir)
  expect_equal(length(result$delay_files), 1)
})

test_that("scan_ancillary_contents finds model kinpar files", {
  temp_dir <- tempdir()
  ancillary_dir <- file.path(temp_dir, "test_scan_model")
  pet_dir <- file.path(ancillary_dir, "sub-01")
  dir.create(pet_dir, recursive = TRUE, showWarnings = FALSE)
  withr::defer(unlink(ancillary_dir, recursive = TRUE))

  # Create mock model kinpar files
  writeLines("region\tBPnd\tk2prime\nFrontal\t0.5\t0.1",
             file.path(pet_dir, "sub-01_model_MRTM1_desc-model1_kinpar.tsv"))
  writeLines("region\tBPnd\tk2prime\nFrontal\t0.5\t0.12",
             file.path(pet_dir, "sub-01_model_MRTM2_desc-model2_kinpar.tsv"))

  result <- scan_ancillary_contents(ancillary_dir)
  expect_equal(length(result$model1_kinpar), 1)
  expect_equal(length(result$model2_kinpar), 1)
  expect_equal(length(result$model3_kinpar), 0)
})

test_that("get_ancillary_delay_options returns option when files exist", {
  scan_result <- list(
    delay_files = c("/path/to/delay_kinpar.tsv"),
    model1_kinpar = character(0),
    model2_kinpar = character(0),
    model3_kinpar = character(0)
  )

  opts <- get_ancillary_delay_options(scan_result)
  expect_equal(opts, c("Inherit from ancillary analysis folder" = "ancillary_estimate"))
})

test_that("get_ancillary_delay_options returns NULL when no files", {
  scan_result <- list(
    delay_files = character(0),
    model1_kinpar = character(0),
    model2_kinpar = character(0),
    model3_kinpar = character(0)
  )

  expect_null(get_ancillary_delay_options(scan_result))
})

test_that("get_ancillary_k2prime_options returns options for available models", {
  scan_result <- list(
    delay_files = character(0),
    model1_kinpar = c("/path/kinpar1.tsv"),
    model1_type = "MRTM1",
    model2_kinpar = character(0),
    model2_type = NULL,
    model3_kinpar = c("/path/kinpar3.tsv"),
    model3_type = "SRTM2"
  )

  opts <- get_ancillary_k2prime_options(scan_result)
  expect_true(length(opts) == 4)  # 2 options per model (mean, median) x 2 models

  # Check values
  expect_true("ancillary_model1_mean" %in% opts)
  expect_true("ancillary_model1_median" %in% opts)
  expect_true("ancillary_model3_mean" %in% opts)
  expect_true("ancillary_model3_median" %in% opts)

  # Model 2 should not be present (no files)
  expect_false("ancillary_model2_mean" %in% opts)
})

test_that("get_ancillary_k2prime_options returns NULL when no models", {
  scan_result <- list(
    delay_files = character(0),
    model1_kinpar = character(0),
    model1_type = NULL,
    model2_kinpar = character(0),
    model2_type = NULL,
    model3_kinpar = character(0),
    model3_type = NULL
  )

  expect_null(get_ancillary_k2prime_options(scan_result))
})

test_that("read_ancillary_delay reads and aggregates delay data", {
  temp_dir <- tempdir()
  ancillary_dir <- file.path(temp_dir, "test_read_delay")
  pet_dir <- file.path(ancillary_dir, "sub-01")
  dir.create(pet_dir, recursive = TRUE, showWarnings = FALSE)
  withr::defer(unlink(ancillary_dir, recursive = TRUE))

  # Create a delay kinpar file (real delay reports use blood_timeshift column)
  delay_data <- tibble::tibble(
    blood_timeshift = 0.05
  )
  readr::write_tsv(delay_data,
                   file.path(pet_dir, "sub-01_desc-delayfit_kinpar.tsv"))

  result <- read_ancillary_delay(ancillary_dir)
  expect_equal(nrow(result), 1)
  expect_equal(result$pet, "sub-01")
  expect_equal(result$inpshift, 0.05)
})

test_that("read_ancillary_delay warns for missing PET IDs", {
  temp_dir <- tempdir()
  ancillary_dir <- file.path(temp_dir, "test_read_delay_missing")
  pet_dir <- file.path(ancillary_dir, "sub-01")
  dir.create(pet_dir, recursive = TRUE, showWarnings = FALSE)
  withr::defer(unlink(ancillary_dir, recursive = TRUE))

  delay_data <- tibble::tibble(
    blood_timeshift = 0.05
  )
  readr::write_tsv(delay_data,
                   file.path(pet_dir, "sub-01_desc-delayfit_kinpar.tsv"))

  expect_warning(
    result <- read_ancillary_delay(ancillary_dir, pet_ids = c("sub-01", "sub-02")),
    "not found"
  )
  expect_equal(nrow(result), 2)
  # Missing PET should get inpshift=0
  expect_equal(result$inpshift[result$pet == "sub-02"], 0)
})

test_that("read_ancillary_k2prime reads and aggregates k2prime", {
  temp_dir <- tempdir()
  ancillary_dir <- file.path(temp_dir, "test_read_k2prime")
  pet_dir <- file.path(ancillary_dir, "sub-01")
  dir.create(pet_dir, recursive = TRUE, showWarnings = FALSE)
  withr::defer(unlink(ancillary_dir, recursive = TRUE))

  # Create kinpar file with k2prime column
  kinpar_data <- tibble::tibble(
    region = c("Frontal", "Temporal", "Parietal"),
    BPnd = c(0.5, 0.3, 0.8),
    k2prime = c(0.10, 0.12, 0.08)
  )
  readr::write_tsv(kinpar_data,
                   file.path(pet_dir, "sub-01_model_MRTM1_desc-model1_kinpar.tsv"))

  # Test mean aggregation
  result_mean <- read_ancillary_k2prime(ancillary_dir, model_num = 1, aggregation = "mean")
  expect_equal(nrow(result_mean), 1)
  expect_equal(result_mean$pet, "sub-01")
  expect_equal(result_mean$k2prime, mean(c(0.10, 0.12, 0.08)))

  # Test median aggregation
  result_median <- read_ancillary_k2prime(ancillary_dir, model_num = 1, aggregation = "median")
  expect_equal(result_median$k2prime, 0.10)  # median of 0.08, 0.10, 0.12
})

test_that("copy_ancillary_delay_files copies files correctly", {
  temp_dir <- tempdir()
  ancillary_dir <- file.path(temp_dir, "test_copy_delay_src")
  output_dir <- file.path(temp_dir, "test_copy_delay_dst")
  pet_dir_src <- file.path(ancillary_dir, "sub-01")

  dir.create(pet_dir_src, recursive = TRUE, showWarnings = FALSE)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  withr::defer({
    unlink(ancillary_dir, recursive = TRUE)
    unlink(output_dir, recursive = TRUE)
  })

  # Create source delay files
  writeLines("region\tinpshift\nFrontal\t0.05",
             file.path(pet_dir_src, "sub-01_desc-delayfit_kinpar.tsv"))

  result <- copy_ancillary_delay_files(ancillary_dir, output_dir)
  expect_true(result$success)
  expect_equal(result$files_copied, 1)

  # Verify file was copied to correct location
  copied_file <- file.path(output_dir, "sub-01", "sub-01_desc-delayfit_kinpar.tsv")
  expect_true(file.exists(copied_file))
})

test_that("copy_ancillary_delay_files returns failure for empty folder", {
  temp_dir <- tempdir()
  ancillary_dir <- file.path(temp_dir, "test_copy_delay_empty")
  output_dir <- file.path(temp_dir, "test_copy_delay_empty_dst")

  dir.create(ancillary_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  withr::defer({
    unlink(ancillary_dir, recursive = TRUE)
    unlink(output_dir, recursive = TRUE)
  })

  result <- copy_ancillary_delay_files(ancillary_dir, output_dir)
  expect_false(result$success)
  expect_equal(result$files_copied, 0)
})

test_that("extract_pet_id_from_kinpar_filename works correctly", {
  expect_equal(
    extract_pet_id_from_kinpar_filename("sub-01_desc-delayfit_kinpar.tsv"),
    "sub-01"
  )
  expect_equal(
    extract_pet_id_from_kinpar_filename("sub-01_ses-02_trc-WAY_desc-model1_kinpar.tsv"),
    "sub-01_ses-02_trc-WAY"
  )
  expect_equal(
    extract_pet_id_from_kinpar_filename("sub-01_model_MRTM1_desc-model1_kinpar.tsv"),
    "sub-01"
  )
})

test_that("print_ancillary_summary produces messages", {
  temp_dir <- tempdir()
  ancillary_dir <- file.path(temp_dir, "test_print_summary")
  dir.create(ancillary_dir, recursive = TRUE, showWarnings = FALSE)
  withr::defer(unlink(ancillary_dir, recursive = TRUE))

  scan_result <- list(
    delay_files = c("file1.tsv", "file2.tsv"),
    model1_kinpar = c("kinpar1.tsv"),
    model1_type = "MRTM1",
    model2_kinpar = character(0),
    model2_type = NULL,
    model3_kinpar = character(0),
    model3_type = NULL
  )

  expect_message(
    print_ancillary_summary(ancillary_dir, scan_result),
    "Ancillary Analysis Folder"
  )
})
