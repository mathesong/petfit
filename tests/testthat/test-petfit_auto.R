# Unit tests for petfit_auto()
#
# Tests function signature and argument validation.

# ---------------------------------------------------------------------------
# Function signature
# ---------------------------------------------------------------------------

test_that("petfit_auto has expected parameters", {
  expect_true(is.function(petfit_auto))
  formals_list <- formals(petfit_auto)
  expected_params <- c("app", "bids_dir", "derivatives_dir", "blood_dir",
                       "petfit_output_foldername", "analysis_foldername", "step")
  expect_true(all(expected_params %in% names(formals_list)))
  expect_equal(formals_list$petfit_output_foldername, "petfit")
  expect_equal(formals_list$analysis_foldername, "Primary_Analysis")
})

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

test_that("petfit_auto rejects invalid app choice", {
  expect_error(petfit_auto(app = "invalid"))
})
