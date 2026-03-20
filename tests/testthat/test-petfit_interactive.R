# Unit tests for petfit_interactive()
#
# Tests function signature, argument validation, and directory validation.
# Does NOT test actual app launching (that requires a Shiny server).

# ---------------------------------------------------------------------------
# Function signature
# ---------------------------------------------------------------------------

test_that("petfit_interactive has expected parameters", {
  expect_true(is.function(petfit_interactive))
  formals_list <- formals(petfit_interactive)
  expected_params <- c("app", "bids_dir", "derivatives_dir", "blood_dir",
                       "petfit_output_foldername", "analysis_foldername", "config_file")
  expect_true(all(expected_params %in% names(formals_list)))
  expect_equal(formals_list$petfit_output_foldername, "petfit")
  expect_equal(formals_list$analysis_foldername, "Primary_Analysis")
})

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

test_that("petfit_interactive rejects invalid app choice", {
  expect_error(petfit_interactive(app = "invalid"))
})

test_that("petfit_interactive rejects non-existent BIDS directory", {
  expect_error(
    petfit_interactive(app = "regiondef", bids_dir = "/nonexistent/path"),
    "BIDS directory does not exist"
  )
})

test_that("petfit_interactive rejects non-existent derivatives directory", {
  expect_error(
    petfit_interactive(app = "modelling_ref", derivatives_dir = "/nonexistent/path"),
    "Derivatives directory does not exist"
  )
})

test_that("petfit_interactive rejects non-existent blood directory", {
  expect_error(
    petfit_interactive(app = "modelling_plasma", blood_dir = "/nonexistent/path"),
    "Blood directory does not exist"
  )
})
