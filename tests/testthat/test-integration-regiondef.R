# Integration tests: Region Definition (automatic mode)
#
# Tests petfit_regiondef_auto() with real ds004869 data.
# These tests verify the complete region definition pipeline:
# - Region config loading and tacs-morph mapping
# - Combined TACs generation with correct structure
# - BIDS metadata integration (participants, PET JSON)
# - Segmentation mean TAC calculation
#
# Requires: PETFIT_INTEGRATION_TESTS=true

# ---------------------------------------------------------------------------
# Region definition: automatic pipeline
# ---------------------------------------------------------------------------

test_that("petfit_regiondef_auto() succeeds with full dataset", {
  skip_if_no_integration()

  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  withr::defer(cleanup_workspace(ws))

  # Install region definition config
  setup_regiondef_config(ws)

  # Run automatic region definition
  result <- petfit_regiondef_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  expect_true(result$success, info = paste(result$messages, collapse = "\n"))
  expect_true(!is.null(result$output_file))
  expect_true(file.exists(result$output_file))
})

test_that("combined TACs file has correct structure", {
  skip_if_no_integration()

  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  withr::defer(cleanup_workspace(ws))

  setup_regiondef_config(ws)
  result <- petfit_regiondef_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  combined_tacs <- readr::read_tsv(result$output_file, show_col_types = FALSE)

  # Expected BIDS identifier columns
  bids_cols <- c("sub", "ses", "segmentation", "pet")
  for (col in bids_cols) {
    expect_true(col %in% names(combined_tacs), info = paste("Missing column:", col))
  }

  # Expected metadata columns
  expect_true("InjectedRadioactivity" %in% names(combined_tacs))
  expect_true("bodyweight" %in% names(combined_tacs))

  # Expected region and time columns
  expect_true("region" %in% names(combined_tacs))
  expect_true("volume_mm3" %in% names(combined_tacs))
  expect_true("frame_start" %in% names(combined_tacs))
  expect_true("frame_end" %in% names(combined_tacs))
  expect_true("frame_dur" %in% names(combined_tacs))
  expect_true("frame_mid" %in% names(combined_tacs))
  expect_true("TAC" %in% names(combined_tacs))
  expect_true("seg_meanTAC" %in% names(combined_tacs))
})

test_that("combined TACs contains all 4 defined regions", {
  skip_if_no_integration()

  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  withr::defer(cleanup_workspace(ws))

  setup_regiondef_config(ws)
  result <- petfit_regiondef_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  combined_tacs <- readr::read_tsv(result$output_file, show_col_types = FALSE)

  expected_regions <- c("Frontal", "Temporal", "Cerebellum", "WhiteMatter")
  actual_regions <- sort(unique(combined_tacs$region))
  expect_equal(actual_regions, sort(expected_regions))
})

test_that("combined TACs covers all 27 subjects and 54 PET measurements", {
  skip_if_no_integration()

  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  withr::defer(cleanup_workspace(ws))

  setup_regiondef_config(ws)
  result <- petfit_regiondef_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  combined_tacs <- readr::read_tsv(result$output_file, show_col_types = FALSE)

  # 27 subjects, each with 2 sessions = 54 PET measurements
  expect_equal(length(unique(combined_tacs$sub)), 27)
  expect_equal(length(unique(combined_tacs$pet)), 54)
})

test_that("BIDS identifiers are preserved as character types", {
  skip_if_no_integration()

  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  withr::defer(cleanup_workspace(ws))

  setup_regiondef_config(ws)
  result <- petfit_regiondef_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  combined_tacs <- readr::read_tsv(result$output_file, show_col_types = FALSE)

  # Subject IDs should be character (e.g., "01" not 1)
  expect_type(combined_tacs$sub, "character")
  expect_true(all(nchar(combined_tacs$sub) == 2),
              info = "Subject IDs should be zero-padded strings like '01'")
})

test_that("participant metadata is integrated correctly", {
  skip_if_no_integration()

  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  withr::defer(cleanup_workspace(ws))

  setup_regiondef_config(ws)
  result <- petfit_regiondef_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  combined_tacs <- readr::read_tsv(result$output_file, show_col_types = FALSE)

  # InjectedRadioactivity should be present and numeric (converted to kBq)
  expect_true(all(!is.na(combined_tacs$InjectedRadioactivity)))
  expect_true(is.numeric(combined_tacs$InjectedRadioactivity))
  expect_true(all(combined_tacs$InjectedRadioactivity > 0))

  # Bodyweight from participants.tsv (allow some NA since not all may have weight)
  expect_true(is.numeric(combined_tacs$bodyweight))
  # Sub-01 has weight 75.8 in participants.tsv
  sub01_weight <- unique(combined_tacs$bodyweight[combined_tacs$sub == "01"])
  expect_equal(sub01_weight, 75.8, tolerance = 0.1)
})

test_that("volume data is reasonable for combined regions", {
  skip_if_no_integration()

  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  withr::defer(cleanup_workspace(ws))

  setup_regiondef_config(ws)
  result <- petfit_regiondef_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  combined_tacs <- readr::read_tsv(result$output_file, show_col_types = FALSE)

  # Volumes should be positive (combined from constituent regions)
  expect_true(all(combined_tacs$volume_mm3 > 0))

  # Combined regions should have larger volumes than individual FreeSurfer regions
  # Frontal cortex (6 bilateral regions) should be substantial
  frontal_vols <- unique(combined_tacs$volume_mm3[combined_tacs$region == "Frontal"])
  expect_true(all(frontal_vols > 10000),
              info = "Frontal region volume should be > 10,000 mm3")
})

test_that("time frames are consistent across regions within a PET measurement", {
  skip_if_no_integration()

  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  withr::defer(cleanup_workspace(ws))

  setup_regiondef_config(ws)
  result <- petfit_regiondef_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  combined_tacs <- readr::read_tsv(result$output_file, show_col_types = FALSE)

  # Pick a specific PET measurement
  first_pet <- combined_tacs$pet[1]
  pet_data <- combined_tacs[combined_tacs$pet == first_pet, ]

  # All regions should have same number of time frames
  frames_per_region <- pet_data %>%
    dplyr::group_by(region) %>%
    dplyr::summarise(n_frames = dplyr::n(), .groups = "drop")

  expect_true(length(unique(frames_per_region$n_frames)) == 1,
              info = "All regions should have the same number of time frames")

  # Frame timing should be monotonically increasing
  region_data <- pet_data[pet_data$region == "Frontal", ]
  expect_true(all(diff(region_data$frame_start) > 0))
  expect_true(all(diff(region_data$frame_end) > 0))

  # frame_dur should equal frame_end - frame_start
  expect_equal(region_data$frame_dur, region_data$frame_end - region_data$frame_start,
               tolerance = 0.01)
})

test_that("seg_meanTAC is consistent within segmentation and PET measurement", {
  skip_if_no_integration()

  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  withr::defer(cleanup_workspace(ws))

  setup_regiondef_config(ws)
  result <- petfit_regiondef_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  combined_tacs <- readr::read_tsv(result$output_file, show_col_types = FALSE)

  # seg_meanTAC should be the same across all regions for a given
  # PET measurement and time frame (it's the segmentation-wide mean)
  first_pet <- combined_tacs$pet[1]
  pet_data <- combined_tacs[combined_tacs$pet == first_pet, ]

  # For each frame_start, seg_meanTAC should be identical across regions
  frame_check <- pet_data %>%
    dplyr::group_by(frame_start) %>%
    dplyr::summarise(
      n_unique_seg_mean = dplyr::n_distinct(seg_meanTAC),
      .groups = "drop"
    )
  expect_true(all(frame_check$n_unique_seg_mean == 1),
              info = "seg_meanTAC should be identical across regions for same frame")

  # seg_meanTAC should be positive (it's a volume-weighted mean of radioactivity)
  expect_true(all(combined_tacs$seg_meanTAC > 0, na.rm = TRUE))
})

test_that("TAC values differ between regions", {
  skip_if_no_integration()

  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  withr::defer(cleanup_workspace(ws))

  setup_regiondef_config(ws)
  result <- petfit_regiondef_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  combined_tacs <- readr::read_tsv(result$output_file, show_col_types = FALSE)

  # Different regions should have different TAC values
  # (they represent different brain areas with different kinetics)
  first_pet <- combined_tacs$pet[1]
  pet_data <- combined_tacs[combined_tacs$pet == first_pet, ]

  # Get mean TAC per region
  region_means <- pet_data %>%
    dplyr::group_by(region) %>%
    dplyr::summarise(mean_tac = mean(TAC), .groups = "drop")

  # Not all regions should have the same mean TAC
  expect_true(length(unique(round(region_means$mean_tac, 2))) > 1,
              info = "Different regions should have different mean TAC values")
})

test_that("JSON sidecar is created alongside combined TACs", {
  skip_if_no_integration()

  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  withr::defer(cleanup_workspace(ws))

  setup_regiondef_config(ws)
  result <- petfit_regiondef_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  # Check JSON sidecar exists
  json_file <- gsub("\\.tsv$", ".json", result$output_file)
  expect_true(file.exists(json_file),
              info = "JSON sidecar should be created alongside combined TACs TSV")

  # Should be valid JSON
  json_content <- jsonlite::read_json(json_file)
  expect_true(is.list(json_content))
})

test_that("mapping file (petfit_regions_files.tsv) is created", {
  skip_if_no_integration()

  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  withr::defer(cleanup_workspace(ws))

  setup_regiondef_config(ws)
  result <- petfit_regiondef_auto(
    bids_dir = ws$bids_dir,
    derivatives_dir = ws$derivatives_dir
  )

  # The mapping file should be in the petfit directory
  mapping_file <- file.path(ws$derivatives_dir, "petfit", "petfit_regions_files.tsv")
  expect_true(file.exists(mapping_file),
              info = "petfit_regions_files.tsv mapping should be created")

  mapping <- readr::read_tsv(mapping_file, show_col_types = FALSE)

  # Should have tacs_filename and morph_filename columns

  expect_true("tacs_filename" %in% names(mapping))
  expect_true("morph_filename" %in% names(mapping))

  # Should have entries for our 4 regions across all TACs files
  expect_true(nrow(mapping) > 0)
})

test_that("regiondef works with derivatives_dir only (no bids_dir)", {
  skip_if_no_integration()

  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)
  withr::defer(cleanup_workspace(ws))

  setup_regiondef_config(ws)

  # Run with only derivatives_dir (no participant data integration)
  result <- petfit_regiondef_auto(
    bids_dir = NULL,
    derivatives_dir = ws$derivatives_dir
  )

  expect_true(result$success, info = paste(result$messages, collapse = "\n"))

  combined_tacs <- readr::read_tsv(result$output_file, show_col_types = FALSE)

  # Should still have 4 regions and correct structure
  expect_equal(length(unique(combined_tacs$region)), 4)
  expect_true("TAC" %in% names(combined_tacs))
  expect_true("frame_start" %in% names(combined_tacs))
})
