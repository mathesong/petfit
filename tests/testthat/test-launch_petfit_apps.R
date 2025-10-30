test_that("launch_petfit_apps function exists and has expected signature", {
  expect_true(exists("launch_petfit_apps"))
  expect_true(is.function(launch_petfit_apps))
  formals_list <- formals(launch_petfit_apps)
  expected_params <- c("app", "bids_dir", "derivatives_dir", "blood_dir", "petfit_output_foldername", "subfolder", "config_file")
  expect_true(all(expected_params %in% names(formals_list)))
  expect_equal(formals_list$petfit_output_foldername, "petfit")
  expect_equal(formals_list$subfolder, "Primary_Analysis")
})

test_that("launch_petfit_apps validates app choice", {
  expect_error(launch_petfit_apps(app = "invalid"), "arg should be one of")
})

test_that("launch_petfit_apps validates directory inputs", {
  expect_error(
    launch_petfit_apps(app = "regiondef", bids_dir = "/nonexistent/path"),
    "BIDS directory does not exist"
  )
  expect_error(
    launch_petfit_apps(app = "modelling_ref", derivatives_dir = "/nonexistent/path"),
    "Derivatives directory does not exist"
  )
})
