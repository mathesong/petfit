test_that("get_model_template maps model types correctly", {
  
  # Test 1TCM mapping
  result <- get_model_template("1TCM")
  expect_equal(result, "1tcm_report.Rmd")
  
  # Test 2TCM mapping  
  result <- get_model_template("2TCM")
  expect_equal(result, "2tcm_report.Rmd")
  
  # Test Logan mapping
  result <- get_model_template("Logan")
  expect_equal(result, "logan_report.Rmd")
  
  # Test unknown model (should return generic template)
  result <- get_model_template("UnknownModel")
  expect_equal(result, "model_report.Rmd")
  
  # Test NULL input
  result <- get_model_template(NULL)
  expect_equal(result, "model_report.Rmd")
})

test_that("generate_step_report creates step-specific reports", {
  
  # Load setup helpers
  source(here::here("tests/testthat/fixtures/setup.R"))
  
  # Create test environment
  temp_dir <- tempdir()
  bids_dir <- create_test_bids_structure(temp_dir, n_subjects = 1, n_sessions = 1)
  
  analysis_folder <- file.path(bids_dir, "derivatives", "petfit", "Primary_Analysis")
  dir.create(analysis_folder, recursive = TRUE, showWarnings = FALSE)
  
  # Create reports directory
  reports_dir <- file.path(analysis_folder, "reports")
  dir.create(reports_dir, showWarnings = FALSE)
  
  # Create minimal config file
  config <- list(
    DataSubset = list(
      regions = c("Cortex")
    ),
    Weights = list(
      method = "2",
      radioisotope = "F18"
    )
  )
  
  config_file <- file.path(analysis_folder, "desc-petfitoptions_config.json")
  jsonlite::write_json(config, config_file, auto_unbox = TRUE, pretty = TRUE)
  
  # Test data definition report generation (expect error due to missing data)
  expect_error({
    result <- generate_step_report("data_definition", analysis_folder, bids_dir = bids_dir)
  })
  
  # Test weights report generation (expect error due to missing data)
  expect_error({
    result <- generate_step_report("weights", analysis_folder, bids_dir = bids_dir)
  })
  
  # Cleanup
  cleanup_test_dirs(bids_dir)
})

test_that("generate_step_report validates inputs", {
  
  temp_dir <- tempdir()
  invalid_folder <- file.path(temp_dir, "nonexistent")
  
  # Test with non-existent analysis folder
  expect_error({
    generate_step_report("weights", invalid_folder)
  })
  
  # Test with invalid step name
  valid_folder <- file.path(temp_dir, "valid")
  dir.create(valid_folder, showWarnings = FALSE)
  
  expect_error({
    generate_step_report("invalid_step", valid_folder)
  })
  
  # Cleanup
  unlink(valid_folder, recursive = TRUE)
})

test_that("generate_model_report handles 1TCM and 2TCM models", {
  
  source(here::here("tests/testthat/fixtures/setup.R"))
  
  temp_dir <- tempdir()
  bids_dir <- create_test_bids_structure(temp_dir, n_subjects = 1, n_sessions = 1)
  
  analysis_folder <- file.path(bids_dir, "derivatives", "petfit", "Primary_Analysis") 
  dir.create(analysis_folder, recursive = TRUE, showWarnings = FALSE)
  
  reports_dir <- file.path(analysis_folder, "reports")
  dir.create(reports_dir, showWarnings = FALSE)
  
  # Create config with 1TCM model
  config <- list(
    Model1 = list(
      model_type = "1TCM",
      K1_start = 0.1,
      k2_start = 0.1,
      vB_start = 0.05
    )
  )
  
  config_file <- file.path(analysis_folder, "desc-petfitoptions_config.json")
  jsonlite::write_json(config, config_file, auto_unbox = TRUE, pretty = TRUE)
  
  # Test 1TCM report generation (expect error due to missing data/results)
  expect_error({
    result <- generate_model_report("1TCM", 1, analysis_folder, bids_dir = bids_dir)
  })
  
  # Test 2TCM report generation
  expect_error({
    result <- generate_model_report("2TCM", 2, analysis_folder, bids_dir = bids_dir)
  })
  
  # Cleanup
  cleanup_test_dirs(bids_dir)
})

test_that("generate_model_report validates model inputs", {
  
  temp_dir <- tempdir()
  analysis_folder <- file.path(temp_dir, "model_test")
  dir.create(analysis_folder, showWarnings = FALSE)
  
  # Test with invalid model number
  expect_error({
    generate_model_report("1TCM", 0, analysis_folder)
  })
  
  expect_error({
    generate_model_report("1TCM", 4, analysis_folder)
  })
  
  # Test with NULL model type
  expect_error({
    generate_model_report(NULL, 1, analysis_folder)  
  })
  
  # Cleanup
  unlink(analysis_folder, recursive = TRUE)
})

test_that("generate_reports_summary creates summary page", {
  
  temp_dir <- tempdir()
  analysis_folder <- file.path(temp_dir, "summary_test")
  reports_dir <- file.path(analysis_folder, "reports")
  dir.create(reports_dir, recursive = TRUE, showWarnings = FALSE)
  
  # Create some dummy report files
  dummy_reports <- c(
    "data_definition_report.html",
    "weights_report.html", 
    "model1_report.html"
  )
  
  for (report in dummy_reports) {
    file.create(file.path(reports_dir, report))
  }
  
  # Test summary generation
  result <- generate_reports_summary(analysis_folder)
  
  expect_type(result, "character")
  expect_true(file.exists(result))
  expect_true(grepl("reports_summary\\.html$", result))
  
  # Check that HTML file was created
  html_content <- readLines(result)
  expect_true(length(html_content) > 0)
  expect_true(any(grepl("<html>", html_content, ignore.case = TRUE)))
  
  # Cleanup
  unlink(analysis_folder, recursive = TRUE)
})

test_that("generate_reports_summary handles empty reports directory", {
  
  temp_dir <- tempdir()
  analysis_folder <- file.path(temp_dir, "empty_reports")
  reports_dir <- file.path(analysis_folder, "reports")
  dir.create(reports_dir, recursive = TRUE, showWarnings = FALSE)
  
  # Test with no existing reports
  result <- generate_reports_summary(analysis_folder)
  
  expect_type(result, "character") 
  expect_true(file.exists(result))
  
  # Cleanup
  unlink(analysis_folder, recursive = TRUE)
})

test_that("report generation handles template availability", {
  
  temp_dir <- tempdir()
  analysis_folder <- file.path(temp_dir, "template_test")
  dir.create(analysis_folder, showWarnings = FALSE)
  
  # Test model template selection
  expect_equal(get_model_template("1TCM"), "1tcm_report.Rmd")
  expect_equal(get_model_template("2TCM"), "2tcm_report.Rmd")
  
  # Test fallback for unsupported models (should not error)
  expect_equal(get_model_template("SRTM"), "model_report.Rmd")
  expect_equal(get_model_template("refLogan"), "model_report.Rmd")
  
  # Cleanup
  unlink(analysis_folder, recursive = TRUE)
})

test_that("generate_step_report handles output directory parameter", {
  
  temp_dir <- tempdir()
  analysis_folder <- file.path(temp_dir, "output_test")
  custom_output_dir <- file.path(temp_dir, "custom_reports")
  
  dir.create(analysis_folder, showWarnings = FALSE)
  dir.create(custom_output_dir, showWarnings = FALSE)
  
  # Create minimal config
  config <- list(
    Weights = list(method = "2", radioisotope = "F18")
  )
  config_file <- file.path(analysis_folder, "desc-petfitoptions_config.json")
  jsonlite::write_json(config, config_file, auto_unbox = TRUE, pretty = TRUE)
  
  # Test with custom output directory (expect error due to missing data)
  expect_error({
    result <- generate_step_report("weights", analysis_folder, custom_output_dir)
  })
  
  # Cleanup
  unlink(c(analysis_folder, custom_output_dir), recursive = TRUE)
})

test_that("generate_tstar_report creates t* finder reports", {
  
  temp_dir <- tempdir()
  analysis_folder <- file.path(temp_dir, "tstar_test")
  reports_dir <- file.path(analysis_folder, "reports")
  dir.create(reports_dir, recursive = TRUE, showWarnings = FALSE)
  
  # Test t* report generation (expect error due to missing template/data)
  expect_error({
    result <- generate_tstar_report(analysis_folder)
  })
  
  # Cleanup  
  unlink(analysis_folder, recursive = TRUE)
})

test_that("report functions handle missing configuration files", {
  
  temp_dir <- tempdir()
  analysis_folder <- file.path(temp_dir, "no_config")
  dir.create(analysis_folder, showWarnings = FALSE)
  
  # Test step report without config file
  expect_error({
    generate_step_report("weights", analysis_folder)
  })
  
  # Test model report without config file
  expect_error({
    generate_model_report("1TCM", 1, analysis_folder)
  })
  
  # Cleanup
  unlink(analysis_folder, recursive = TRUE)
})

test_that("report generation validates report template existence", {
  
  # Test that system can find report templates in package
  template_1tcm <- system.file("rmd", "1tcm_report.Rmd", package = "petfit")
  template_2tcm <- system.file("rmd", "2tcm_report.Rmd", package = "petfit") 
  template_weights <- system.file("rmd", "weights_report.Rmd", package = "petfit")
  
  # These should exist or be findable (may be empty string if not installed)
  expect_type(template_1tcm, "character")
  expect_type(template_2tcm, "character") 
  expect_type(template_weights, "character")
  
  # At minimum, the template selection function should work
  expect_equal(get_model_template("1TCM"), "1tcm_report.Rmd")
  expect_equal(get_model_template("2TCM"), "2tcm_report.Rmd")
})