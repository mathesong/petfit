# Integration tests: t* finder (run_tstar_finder)
#
# Builds a real analysis folder from ds004869 and checks that run_tstar_finder
# writes PNG diagnostic plots for both the plasma and reference pipelines.
#
# Requires: PETFIT_INTEGRATION_TESTS=true

# ---------------------------------------------------------------------------
# Plasma t*
# ---------------------------------------------------------------------------

test_that("run_tstar_finder writes plots for the plasma pipeline", {
  skip_if_no_integration()

  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  withr::defer(cleanup_workspace(ws))
  setup_regiondef_config(ws)

  rd <- petfit_regiondef_auto(bids_dir = ws$bids_dir, derivatives_dir = ws$derivatives_dir)
  if (!rd$success) skip(paste("Regiondef failed:", paste(rd$messages, collapse = "\n")))
  setup_modelling_config(ws, "ds004869_plasma_config.json")

  # Build TACs + weights + delay (delay creates input functions in the analysis folder)
  for (step in c("datadef", "weights", "delay")) {
    petfit_modelling_auto(bids_dir = ws$bids_dir, derivatives_dir = ws$derivatives_dir, step = step)
  }

  analysis_folder <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  tac_file <- list.files(analysis_folder, "_desc-combinedregions_tacs.tsv",
                         recursive = TRUE, full.names = TRUE)[1]
  regions <- sort(unique(readr::read_tsv(tac_file, show_col_types = FALSE)$region))
  skip_if(length(regions) < 3, "Need at least 3 regions for the t* finder")

  written <- run_tstar_finder(
    analysis_folder = analysis_folder,
    config_type = "plasma input",
    model = "Logan",
    high_region = regions[1], med_region = regions[2], low_region = regions[length(regions)],
    selection = "all",
    bids_dir = ws$bids_dir
  )

  expect_true(length(written) >= 1)
  expect_true(all(file.exists(written)))
  expect_true(all(file.info(written)$size > 0))
  expect_true(all(grepl(file.path("reports", "tstar_finder", "Logan"), written)))
})

# ---------------------------------------------------------------------------
# Reference t*
# ---------------------------------------------------------------------------

test_that("run_tstar_finder writes plots for the reference pipeline", {
  skip_if_no_integration()

  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  withr::defer(cleanup_workspace(ws))
  setup_regiondef_config(ws)

  rd <- petfit_regiondef_auto(bids_dir = ws$bids_dir, derivatives_dir = ws$derivatives_dir)
  if (!rd$success) skip(paste("Regiondef failed:", paste(rd$messages, collapse = "\n")))
  setup_modelling_config(ws, "ds004869_ref_config.json")

  for (step in c("datadef", "weights", "reference_tac")) {
    petfit_modelling_auto(bids_dir = ws$bids_dir, derivatives_dir = ws$derivatives_dir, step = step)
  }

  analysis_folder <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  tac_file <- list.files(analysis_folder, "_desc-targetregions_tacs.tsv",
                         recursive = TRUE, full.names = TRUE)[1]
  regions <- sort(unique(readr::read_tsv(tac_file, show_col_types = FALSE)$region))
  skip_if(length(regions) < 3, "Need at least 3 target regions for the t* finder")

  written <- run_tstar_finder(
    analysis_folder = analysis_folder,
    config_type = "reference tissue",
    model = "MRTM1",
    high_region = regions[1], med_region = regions[2], low_region = regions[length(regions)],
    selection = "all"
  )

  expect_true(length(written) >= 1)
  expect_true(all(file.exists(written)))
  expect_true(all(file.info(written)$size > 0))
  expect_true(all(grepl(file.path("reports", "tstar_finder", "MRTM1"), written)))
})

# ---------------------------------------------------------------------------
# k2prime is required for refLogan/MRTM2 t* (default value works)
# ---------------------------------------------------------------------------

test_that("run_tstar_finder accepts a user k2prime for refLogan", {
  skip_if_no_integration()

  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  withr::defer(cleanup_workspace(ws))
  setup_regiondef_config(ws)

  rd <- petfit_regiondef_auto(bids_dir = ws$bids_dir, derivatives_dir = ws$derivatives_dir)
  if (!rd$success) skip(paste("Regiondef failed:", paste(rd$messages, collapse = "\n")))
  setup_modelling_config(ws, "ds004869_ref_config.json")

  for (step in c("datadef", "weights", "reference_tac")) {
    petfit_modelling_auto(bids_dir = ws$bids_dir, derivatives_dir = ws$derivatives_dir, step = step)
  }

  analysis_folder <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  tac_file <- list.files(analysis_folder, "_desc-targetregions_tacs.tsv",
                         recursive = TRUE, full.names = TRUE)[1]
  regions <- sort(unique(readr::read_tsv(tac_file, show_col_types = FALSE)$region))
  skip_if(length(regions) < 3, "Need at least 3 target regions for the t* finder")

  written <- run_tstar_finder(
    analysis_folder = analysis_folder,
    config_type = "reference tissue",
    model = "refLogan",
    high_region = regions[1], med_region = regions[2], low_region = regions[length(regions)],
    selection = "random", n_random = 1, k2prime = 0.1
  )

  expect_true(length(written) >= 1)
  expect_true(all(file.exists(written)))
})
