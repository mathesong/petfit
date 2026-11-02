# Integration tests: reference TAC weights, and weights with a missing TAC
#
# Requires: PETFIT_INTEGRATION_TESTS=true

setup_weights_workspace <- function(edit_config) {
  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  setup_regiondef_config(ws)

  regiondef_result <- petfit_regiondef_auto(bids_dir = ws$bids_dir,
                                            derivatives_dir = ws$derivatives_dir)
  if (!regiondef_result$success) {
    testthat::skip(paste("Regiondef failed:", paste(regiondef_result$messages, collapse = "\n")))
  }

  setup_modelling_config(ws, "ds004869_refspline_config.json")

  config_path <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis",
                           "desc-petfitoptions_config.json")
  config <- jsonlite::fromJSON(config_path)
  jsonlite::write_json(edit_config(config), config_path, pretty = TRUE, auto_unbox = TRUE)

  ws
}

run_steps <- function(ws, steps) {
  purrr::map(steps, ~petfit_modelling_auto(bids_dir = ws$bids_dir,
                                           derivatives_dir = ws$derivatives_dir, step = .x))
}

# Blanks the segmentation mean in one frame, as a segmentation lacking it would be
blank_seg_mean_frame <- function(ws) {
  combined_path <- file.path(ws$derivatives_dir, "petfit", "desc-combinedregions_tacs.tsv")
  combined <- readr::read_tsv(combined_path, show_col_types = FALSE)
  frame <- sort(unique(combined$frame_start))[5]
  combined$seg_meanTAC[combined$frame_start == frame] <- NA_real_
  readr::write_tsv(combined, combined_path)
  unique(combined$segmentation)[1]
}

external_weights <- function(config, segmentation, method, formula) {
  config$Weights$region_type <- "external"
  config$Weights$external_tacs <- segmentation
  config$Weights$method <- method
  config$Weights$formula <- formula
  config
}

read_ref_tacs <- function(ws, subject) {
  analysis_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  files <- list.files(analysis_dir, pattern = "_desc-ref_tacs\\.tsv$",
                      recursive = TRUE, full.names = TRUE)
  files <- files[stringr::str_detect(basename(files), paste0("^sub-", subject, "_"))]
  purrr::map_dfr(sort(files), ~readr::read_tsv(.x, show_col_types = FALSE))
}

test_that("separate reference weights do not depend on the other measurements", {
  skip_if_no_integration()

  own_weights <- function(config) {
    config$ReferenceTAC$weights_method <- "custom"
    config$ReferenceTAC$weights_formula <- "frame_dur * tac_uncor"
    config$ReferenceTAC$weights_minweight <- 0.25
    config
  }

  cohort <- setup_weights_workspace(own_weights)
  withr::defer(cleanup_workspace(cohort))
  alone <- setup_weights_workspace(function(config) {
    config <- own_weights(config)
    config$Subsetting$sub <- "01"
    config
  })
  withr::defer(cleanup_workspace(alone))

  steps <- c("datadef", "weights", "reference_tac")
  run_steps(cohort, steps)
  run_steps(alone, steps)

  in_cohort <- read_ref_tacs(cohort, "01")
  by_itself <- read_ref_tacs(alone, "01")

  expect_gt(nrow(by_itself), 0)
  expect_equal(in_cohort$RefTAC, by_itself$RefTAC)
})

test_that("numbered methods can calculate separate reference weights", {
  skip_if_no_integration()

  ws <- setup_weights_workspace(function(config) {
    config$ReferenceTAC$weights_method <- "10"
    config$ReferenceTAC$weights_formula <- "frame_dur * tac_uncor"
    config
  })
  withr::defer(cleanup_workspace(ws))

  results <- run_steps(ws, c("datadef", "weights", "reference_tac"))

  expect_true(results[[3]]$success, info = paste(results[[3]]$messages, collapse = "\n"))
})

test_that("a custom formula calculates target weights", {
  skip_if_no_integration()

  ws <- setup_weights_workspace(function(config) {
    config$Weights$method <- "custom"
    config$Weights$formula <- "frame_dur * tac_uncor"
    config
  })
  withr::defer(cleanup_workspace(ws))

  results <- run_steps(ws, c("datadef", "weights"))
  expect_true(results[[2]]$success, info = paste(results[[2]]$messages, collapse = "\n"))

  analysis_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  weight_files <- list.files(analysis_dir, pattern = "_desc-weights_weights\\.tsv$",
                             recursive = TRUE, full.names = TRUE)
  weights <- readr::read_tsv(weight_files[1], show_col_types = FALSE)
  expect_equal(mean(weights$weights), 1)
  expect_gt(stats::sd(weights$weights), 0)
})

test_that("a missing segmentation mean stops only the weights which use it", {
  skip_if_no_integration()

  no_tac <- setup_weights_workspace(identity)
  withr::defer(cleanup_workspace(no_tac))
  segmentation <- blank_seg_mean_frame(no_tac)

  config_path <- file.path(no_tac$derivatives_dir, "petfit", "Primary_Analysis",
                           "desc-petfitoptions_config.json")
  config <- jsonlite::fromJSON(config_path)
  jsonlite::write_json(external_weights(config, segmentation, "custom", "frame_dur"),
                       config_path, pretty = TRUE, auto_unbox = TRUE)

  results <- run_steps(no_tac, c("datadef", "weights"))
  expect_true(results[[2]]$success, info = paste(results[[2]]$messages, collapse = "\n"))

  analysis_dir <- file.path(no_tac$derivatives_dir, "petfit", "Primary_Analysis")
  weight_files <- list.files(analysis_dir, pattern = "_desc-weights_weights\\.tsv$",
                             recursive = TRUE, full.names = TRUE)
  expect_gt(length(weight_files), 0)
  weights <- readr::read_tsv(weight_files[1], show_col_types = FALSE)
  expect_true(all(is.finite(weights$weights)))

  jsonlite::write_json(external_weights(config, segmentation, "2", "sqrt(frame_dur * tac_uncor)"),
                       config_path, pretty = TRUE, auto_unbox = TRUE)
  stopped <- run_steps(no_tac, "weights")[[1]]
  expect_false(stopped$success)
})
