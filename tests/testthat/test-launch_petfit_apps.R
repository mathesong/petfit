# Unit tests for launch_petfit_apps()
#
# Tests function signature, argument validation, and directory validation.
# Does NOT test actual app launching (that requires a Shiny server).

# ---------------------------------------------------------------------------
# Function signature
# ---------------------------------------------------------------------------

test_that("launch_petfit_apps has expected parameters", {
  expect_true(is.function(launch_petfit_apps))
  formals_list <- formals(launch_petfit_apps)
  expected_params <- c("app", "bids_dir", "derivatives_dir", "blood_dir",
                       "petfit_output_foldername", "subfolder", "config_file")
  expect_true(all(expected_params %in% names(formals_list)))
  expect_equal(formals_list$petfit_output_foldername, "petfit")
  expect_equal(formals_list$subfolder, "Primary_Analysis")
})

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

test_that("launch_petfit_apps rejects invalid app choice", {
  expect_error(launch_petfit_apps(app = "invalid"))
})

test_that("launch_petfit_apps rejects non-existent BIDS directory", {
  expect_error(
    launch_petfit_apps(app = "regiondef", bids_dir = "/nonexistent/path"),
    "BIDS directory does not exist"
  )
})

test_that("launch_petfit_apps rejects non-existent derivatives directory", {
  expect_error(
    launch_petfit_apps(app = "modelling_ref", derivatives_dir = "/nonexistent/path"),
    "Derivatives directory does not exist"
  )
})

test_that("launch_petfit_apps rejects non-existent blood directory", {
  expect_error(
    launch_petfit_apps(app = "modelling_plasma", blood_dir = "/nonexistent/path"),
    "Blood directory does not exist"
  )
})
