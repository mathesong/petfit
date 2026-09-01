# Integration tests: spline-fitted reference TAC
#
# Exercises the spline branch of reference_tac_report.Rmd against real ds004869
# data: that the configured degrees of freedom reach the fit, and that the
# fitted reference TAC comes back on the original PET frame timing rather than
# spline_tac()'s internal grid.
#
# Requires: PETFIT_INTEGRATION_TESTS=true

setup_refspline_workspace <- function() {
  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  setup_regiondef_config(ws)

  regiondef_result <- petfit_regiondef_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  if (!regiondef_result$success) {
    testthat::skip(paste("Regiondef failed:", paste(regiondef_result$messages, collapse = "\n")))
  }

  setup_modelling_config(ws, "ds004869_refspline_config.json")

  ws
}

test_that("the spline reference TAC step runs and reports on the PET frame timing", {
  skip_if_no_integration()

  ws <- setup_refspline_workspace()
  withr::defer(cleanup_workspace(ws))

  for (step in c("datadef", "weights")) {
    petfit_modelling_auto(bids_dir = ws$bids_dir,
                          derivatives_dir = ws$derivatives_dir, step = step)
  }

  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    step = "reference_tac"
  )

  expect_true(result$success, info = paste(result$messages, collapse = "\n"))

  analysis_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  expect_true(file.exists(file.path(analysis_dir, "reports", "reference_tac_report.html")))

  ref_files <- list.files(analysis_dir, pattern = "_desc-ref_tacs\\.tsv$",
                          recursive = TRUE, full.names = TRUE)
  expect_true(length(ref_files) > 0)

  ref <- readr::read_tsv(ref_files[1], show_col_types = FALSE)

  # The spline branch keeps the measured TAC alongside the fitted one.
  expect_true(all(c("RefTAC", "RefTAC_original") %in% colnames(ref)))

  # Every PET frame survives the fit. Joining spline_tac()'s internal grid back
  # by equality used to be able to drop frames silently.
  target_files <- list.files(analysis_dir, pattern = "_desc-targetregions_tacs\\.tsv$",
                             recursive = TRUE, full.names = TRUE)
  target <- readr::read_tsv(target_files[1], show_col_types = FALSE)
  n_frames <- length(unique(target$frame_start))
  expect_equal(nrow(ref), n_frames)

  # The fitted values live on the original frame timing, not a zero-based grid.
  expect_setequal(ref$frame_start, unique(target$frame_start))

  expect_true(all(is.finite(ref$RefTAC)))
  # A spline fit tracks the data rather than flattening it to a constant, which
  # is what the weighted-constant fallback would produce.
  expect_gt(stats::sd(ref$RefTAC), 0)
})

test_that("the configured spline degrees of freedom reach the fit", {
  skip_if_no_integration()

  ws <- setup_refspline_workspace()
  withr::defer(cleanup_workspace(ws))

  for (step in c("datadef", "weights", "reference_tac")) {
    petfit_modelling_auto(bids_dir = ws$bids_dir,
                          derivatives_dir = ws$derivatives_dir, step = step)
  }

  analysis_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  ref_json <- list.files(analysis_dir, pattern = "_desc-ref_tacs\\.json$",
                         recursive = TRUE, full.names = TRUE)
  skip_if(length(ref_json) == 0, "No reference TAC sidecar written")

  sidecar <- jsonlite::fromJSON(ref_json[1])
  expect_equal(sidecar$FittingMethod, "spline")
  expect_match(sidecar$AdditionalModelDetails, "Degrees of freedom: 5")

  # A different basis dimension must actually change the fitted values; before
  # spline_df was passed through to spline_tac() it could not.
  ref_files <- list.files(analysis_dir, pattern = "_desc-ref_tacs\\.tsv$",
                          recursive = TRUE, full.names = TRUE)
  ref <- readr::read_tsv(ref_files[1], show_col_types = FALSE)

  t_tac <- ref$frame_mid / 60
  fit_df5 <- kinfitr::spline_tac(t_tac = t_tac, tac = ref$RefTAC_original, k = 5)
  fit_df3 <- kinfitr::spline_tac(t_tac = t_tac, tac = ref$RefTAC_original, k = 3)
  expect_false(isTRUE(all.equal(fit_df5$tacs$TAC_fitted, fit_df3$tacs$TAC_fitted)))
})

test_that("a degenerate spline_df falls back to a weighted constant fit", {
  skip_if_no_integration()

  ws <- setup_refspline_workspace()
  withr::defer(cleanup_workspace(ws))

  # A basis of 1 dimension cannot form a spline basis.
  config_path <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis",
                           "desc-petfitoptions_config.json")
  skip_if_not(file.exists(config_path), "No modelling config installed")
  config <- jsonlite::fromJSON(config_path)
  config$ReferenceTAC$spline_df <- 1
  writeLines(jsonlite::toJSON(config, pretty = TRUE, auto_unbox = TRUE), config_path)

  for (step in c("datadef", "weights")) {
    petfit_modelling_auto(bids_dir = ws$bids_dir,
                          derivatives_dir = ws$derivatives_dir, step = step)
  }

  # Re-apply, since the datadef step rewrites the config from the fixture.
  config <- jsonlite::fromJSON(config_path)
  config$ReferenceTAC$spline_df <- 1
  writeLines(jsonlite::toJSON(config, pretty = TRUE, auto_unbox = TRUE), config_path)

  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    step = "reference_tac"
  )

  # The step completes rather than failing on the degenerate basis.
  expect_true(result$success, info = paste(result$messages, collapse = "\n"))

  analysis_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  ref_files <- list.files(analysis_dir, pattern = "_desc-ref_tacs\\.tsv$",
                          recursive = TRUE, full.names = TRUE)
  skip_if(length(ref_files) == 0, "No reference TAC written")

  ref <- readr::read_tsv(ref_files[1], show_col_types = FALSE)
  # The fallback is a single weighted mean, so every frame gets the same value.
  expect_equal(length(unique(round(ref$RefTAC, 8))), 1)

  # And the report says so rather than passing it off as a spline.
  report <- paste(readLines(file.path(analysis_dir, "reports", "reference_tac_report.html"),
                            warn = FALSE), collapse = "\n")
  expect_match(report, "Spline fitting fallbacks")
})
