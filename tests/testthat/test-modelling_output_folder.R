# The apps end in shiny::runApp(), so stubbing it lets their startup run for real
launch_without_serving <- function(app_function, derivatives_dir, ...) {
  testthat::local_mocked_bindings(runApp = function(...) invisible(NULL), .package = "shiny")
  utils::capture.output(app_function(derivatives_dir = derivatives_dir, ...))
}

test_that("the modelling apps use the petfit output folder they are given", {
  apps <- list(modelling_plasma_app, modelling_ref_app)

  for (app_function in apps) {
    derivatives_dir <- withr::local_tempdir()

    launch_without_serving(app_function, derivatives_dir,
                           analysis_foldername = "RefPVC",
                           petfit_output_foldername = "petfit_PVC")

    expect_true(dir.exists(file.path(derivatives_dir, "petfit_PVC", "RefPVC")))
    expect_false(dir.exists(file.path(derivatives_dir, "petfit")))
  }
})

test_that("the modelling apps default to the petfit folder", {
  for (app_function in list(modelling_plasma_app, modelling_ref_app)) {
    derivatives_dir <- withr::local_tempdir()

    launch_without_serving(app_function, derivatives_dir, analysis_foldername = "Analysis")

    expect_true(dir.exists(file.path(derivatives_dir, "petfit", "Analysis")))
  }
})

test_that("the new argument comes after the existing ones", {
  for (app_function in list(modelling_plasma_app, modelling_ref_app)) {
    expect_equal(
      names(formals(app_function)),
      c("bids_dir", "derivatives_dir", "blood_dir", "analysis_foldername", "config_file",
        "cores", "save_logs", "ancillary_analysis_folder", "petfit_output_foldername")
    )
  }
})

test_that("petfit_interactive passes the output folder to the modelling apps", {
  received <- NULL
  capture_folder <- function(...) received <<- list(...)$petfit_output_foldername

  testthat::local_mocked_bindings(modelling_plasma_app = capture_folder,
                                  modelling_ref_app = capture_folder)

  for (app in c("modelling_plasma", "modelling_ref")) {
    received <- NULL
    output <- utils::capture.output(
      petfit_interactive(app = app, derivatives_dir = withr::local_tempdir(),
                         petfit_output_foldername = "petfit_PVC")
    )

    expect_equal(received, "petfit_PVC")
    expect_true(any(stringr::str_detect(output, "petfit output folder: petfit_PVC")))
  }
})
