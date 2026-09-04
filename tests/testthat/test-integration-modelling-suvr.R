# Integration tests: SUV / SUVR estimation with reference tissue
#
# Tests petfit_modelling_auto() with real ds004869 data through the reference
# tissue pipeline (datadef -> weights -> reference_tac -> model), with Model 1
# using a 20-60 minute window and Model 2 integrating all frames.
#
# Requires: PETFIT_INTEGRATION_TESTS=true

setup_suvr_workspace <- function() {
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

  setup_modelling_config(ws, "ds004869_suvr_config.json")

  ws
}

run_suvr_prerequisites <- function(ws) {
  for (step in c("datadef", "weights", "reference_tac")) {
    petfit_modelling_auto(
      bids_dir = ws$bids_dir,
      derivatives_dir = ws$derivatives_dir,
      step = step
    )
  }
}

test_that("SUVR pipeline runs end-to-end and writes both model reports", {
  skip_if_no_integration()

  ws <- setup_suvr_workspace()
  withr::defer(cleanup_workspace(ws))

  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  expect_true(result$success, info = paste(result$messages, collapse = "\n"))

  reports_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis", "reports")
  expect_true(file.exists(file.path(reports_dir, "model1_report.html")),
              info = "Windowed SUVR report should be generated")
  expect_true(file.exists(file.path(reports_dir, "model2_report.html")),
              info = "All-frames SUVR report should be generated")
})

test_that("SUVR outputs carry the outcomes and the resolved window", {
  skip_if_no_integration()

  ws <- setup_suvr_workspace()
  withr::defer(cleanup_workspace(ws))

  run_suvr_prerequisites(ws)

  result <- petfit_modelling_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir,
    step = "model1"
  )
  expect_true(result$success, info = paste(result$messages, collapse = "\n"))

  analysis_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  kinpar_path <- file.path(analysis_dir, "model-SUVR_desc-model1_kinpar.tsv")
  expect_true(file.exists(kinpar_path), info = "SUVR kinpar TSV should be written")

  kinpar <- readr::read_tsv(kinpar_path, show_col_types = FALSE)

  expect_true(all(c("SUVR", "SUV", "SUV_ref", "SUV_AUC", "SUV_ref_AUC",
                    "SUV_denominator", "window_start", "window_end",
                    "window_duration", "n_frames") %in% colnames(kinpar)))

  # The ratio is of the two integrals which were reported
  expect_equal(kinpar$SUVR, kinpar$SUV_AUC / kinpar$SUV_ref_AUC)
  # And the means are those integrals over the duration integrated
  expect_equal(kinpar$SUV, kinpar$SUV_AUC / kinpar$window_duration)

  # Only the target regions are estimated; the reference region is not one of them.
  expect_false("Cerebellum" %in% kinpar$region)
  expect_true(all(is.finite(kinpar$SUVR)))
  expect_true(all(kinpar$SUVR > 0))

  # The configured window was 20-60 minutes. Whole frames are selected by
  # midpoint, so the reported bounds are frame edges bracketing that request.
  expect_true(all(kinpar$window_start >= 15 & kinpar$window_start <= 25))
  expect_true(all(kinpar$window_end >= 55 & kinpar$window_end <= 70))
  expect_true(all(kinpar$n_frames > 0))
  expect_true(all(kinpar$window_duration > 0))
})

test_that("an all-frames SUVR integrates more than a windowed one", {
  skip_if_no_integration()

  ws <- setup_suvr_workspace()
  withr::defer(cleanup_workspace(ws))

  run_suvr_prerequisites(ws)

  petfit_modelling_auto(bids_dir = ws$bids_dir,
                        derivatives_dir = ws$derivatives_dir, step = "model1")
  petfit_modelling_auto(bids_dir = ws$bids_dir,
                        derivatives_dir = ws$derivatives_dir, step = "model2")

  analysis_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  windowed <- readr::read_tsv(file.path(analysis_dir, "model-SUVR_desc-model1_kinpar.tsv"),
                              show_col_types = FALSE)
  all_frames <- readr::read_tsv(file.path(analysis_dir, "model-SUVR_desc-model2_kinpar.tsv"),
                                show_col_types = FALSE)

  expect_true(all(all_frames$n_frames >= windowed$n_frames))
  expect_true(all(all_frames$window_duration > windowed$window_duration))
})

test_that("SUVR writes per-measurement outputs into the PET folders", {
  skip_if_no_integration()

  ws <- setup_suvr_workspace()
  withr::defer(cleanup_workspace(ws))

  run_suvr_prerequisites(ws)
  petfit_modelling_auto(bids_dir = ws$bids_dir,
                        derivatives_dir = ws$derivatives_dir, step = "model1")

  analysis_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")

  pet_kinpars <- list.files(analysis_dir, pattern = "model-SUVR.*_kinpar\\.tsv$",
                            recursive = TRUE)
  # One per PET measurement, plus the cohort-level file at the top.
  expect_true(length(pet_kinpars) > 1)

  pet_jsons <- list.files(analysis_dir, pattern = "model-SUVR.*_kinpar\\.json$",
                          recursive = TRUE)
  expect_true(length(pet_jsons) > 0)

  sidecar <- jsonlite::fromJSON(file.path(analysis_dir, pet_jsons[1]))
  expect_equal(sidecar$ModelName, "SUVR")
  expect_true(!is.null(sidecar$SUVCalculation))

  # The frames that went into the ratio are saved alongside the estimates.
  ratio_inputs <- list.files(analysis_dir, pattern = "model-SUVR.*ratioinput.*\\.tsv$",
                             recursive = TRUE)
  expect_true(length(ratio_inputs) > 0)

  inputs <- readr::read_tsv(file.path(analysis_dir, ratio_inputs[1]),
                            show_col_types = FALSE)
  expect_true(all(c("Target", "Reference", "Included") %in% colnames(inputs)))
  expect_true(any(inputs$Included))
})

test_that("the interactive sandbox estimates SUVR for a single measurement", {
  skip_if_no_integration()

  ws <- setup_suvr_workspace()
  withr::defer(cleanup_workspace(ws))

  run_suvr_prerequisites(ws)

  analysis_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  tac_files <- list.files(analysis_dir, pattern = "_desc-targetregions_tacs\\.tsv$",
                          recursive = TRUE, full.names = TRUE)
  skip_if(length(tac_files) == 0, "No target region TAC files produced")

  pet <- pet_key(tac_files, analysis_dir)[1]
  region <- readr::read_tsv(tac_files[1], show_col_types = FALSE)$region[1]

  res <- fit_single_measurement_ref(
    analysis_folder = analysis_dir,
    model_number = "model1",
    pet = pet,
    region = region
  )

  expect_equal(res$type, "SUVR")
  expect_s3_class(res$fit, "suvr")
  expect_true(is.finite(res$par$SUVR))
  expect_true(any(res$fit$tacs$Included))

  p <- plot(res$fit, roiname = res$region)
  expect_s3_class(p, "ggplot")
})
