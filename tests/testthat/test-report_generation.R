# Unit tests for report generation utilities
#
# Tests get_model_template() mapping and generate_reports_summary().
# These test pure functions that don't need real PET data.

# ---------------------------------------------------------------------------
# get_model_template: model type to template mapping
# ---------------------------------------------------------------------------

test_that("get_model_template maps invasive models correctly", {
  expect_equal(get_model_template("1TCM"), "1tcm_report.Rmd")
  expect_equal(get_model_template("2TCM"), "2tcm_report.Rmd")
  expect_equal(get_model_template("2TCM_irr"), "2tcmirr_report.Rmd")
  expect_equal(get_model_template("Logan"), "logan_report.Rmd")
  expect_equal(get_model_template("MA1"), "ma1_report.Rmd")
  expect_equal(get_model_template("Patlak"), "patlak_report.Rmd")
  expect_equal(get_model_template("Fit Delay"), "fit_delay_report.Rmd")
})

test_that("get_model_template maps non-invasive models correctly", {
  expect_equal(get_model_template("SRTM"), "srtm_report.Rmd")
  expect_equal(get_model_template("SRTM2"), "srtm2_report.Rmd")
  expect_equal(get_model_template("refLogan"), "reflogan_report.Rmd")
  expect_equal(get_model_template("MRTM1"), "mrtm1_report.Rmd")
  expect_equal(get_model_template("MRTM2"), "mrtm2_report.Rmd")
})

test_that("get_model_template errors on NULL input", {
  expect_error(get_model_template(NULL), "Model type must be provided")
})

test_that("get_model_template errors on unknown model type", {
  expect_error(get_model_template("UnknownModel"), "Unknown model type")
})

# ---------------------------------------------------------------------------
# generate_reports_summary: summary HTML creation
# ---------------------------------------------------------------------------

test_that("generate_reports_summary creates summary with existing reports", {
  temp_dir <- withr::local_tempdir()
  analysis_folder <- file.path(temp_dir, "analysis")
  reports_dir <- file.path(analysis_folder, "reports")
  dir.create(reports_dir, recursive = TRUE)

  # Create dummy report files
  file.create(file.path(reports_dir, "data_definition_report.html"))
  file.create(file.path(reports_dir, "weights_report.html"))
  file.create(file.path(reports_dir, "model1_report.html"))

  result <- generate_reports_summary(analysis_folder)

  expect_type(result, "character")
  expect_true(file.exists(result))
  expect_true(grepl("reports_summary\\.html$", result))

  # Check content references the reports
  html_content <- paste(readLines(result), collapse = "\n")
  expect_true(grepl("data_definition_report", html_content))
  expect_true(grepl("weights_report", html_content))
  expect_true(grepl("model1_report", html_content))
})

test_that("generate_reports_summary returns NULL for empty reports directory", {
  temp_dir <- withr::local_tempdir()
  analysis_folder <- file.path(temp_dir, "analysis")
  reports_dir <- file.path(analysis_folder, "reports")
  dir.create(reports_dir, recursive = TRUE)

  result <- generate_reports_summary(analysis_folder)
  expect_null(result)
})
