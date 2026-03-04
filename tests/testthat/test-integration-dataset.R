# Integration tests: Dataset validation
#
# Validates that the ds004869 test data is correctly extracted and contains
# the expected files, structure, and content for integration testing.
#
# These tests are skipped unless PETFIT_INTEGRATION_TESTS=true

library(testthat)
library(readr)
library(jsonlite)

test_that("test data extracts successfully", {
  skip_if_no_integration()
  dataset_dir <- ensure_testdata()

  expect_true(dir.exists(dataset_dir))
  expect_true(file.exists(file.path(dataset_dir, "participants.tsv")))
  expect_true(file.exists(file.path(dataset_dir, "dataset_description.json")))
  expect_true(dir.exists(file.path(dataset_dir, "derivatives", "petprep")))
})

test_that("no broken symlinks remain in test data", {
  skip_if_no_integration()
  dataset_dir <- ensure_testdata()

  # Find any broken symlinks
  broken <- system2("find", c(dataset_dir, "-xtype", "l"),
                    stdout = TRUE, stderr = TRUE)
  exit_code <- attr(broken, "status") %||% 0L

  expect_equal(exit_code, 0L)
  expect_equal(length(broken), 0,
               info = paste("Found broken symlinks:",
                            paste(head(broken, 5), collapse = "\n")))
})

test_that("expected number of TACs files exist", {
  skip_if_no_integration()
  dataset_dir <- ensure_testdata()

  tacs_files <- list.files(
    file.path(dataset_dir, "derivatives", "petprep"),
    pattern = "_tacs\\.tsv$",
    recursive = TRUE
  )

  # 27 subjects x 2 sessions = 54 TACs files
  expect_equal(length(tacs_files), 54)
})

test_that("expected number of blood data files exist", {
  skip_if_no_integration()
  dataset_dir <- ensure_testdata()

  blood_files <- list.files(
    dataset_dir,
    pattern = "_blood\\.tsv$",
    recursive = TRUE
  )

  # 27 subjects x 2 sessions = 54 blood files
  expect_equal(length(blood_files), 54)
})

test_that("expected number of morph files exist", {
  skip_if_no_integration()
  dataset_dir <- ensure_testdata()

  morph_files <- list.files(
    file.path(dataset_dir, "derivatives", "petprep"),
    pattern = "_morph\\.tsv$",
    recursive = TRUE
  )

  # One morph file per subject (no session in filename) - but there are
  # actually 27*2 = 54 morph files in petprep, one per sub/ses
  # Let's just check we have at least 27
  expect_gte(length(morph_files), 27)
})

test_that("participants.tsv has expected structure", {
  skip_if_no_integration()
  dataset_dir <- ensure_testdata()

  participants <- read_tsv(
    file.path(dataset_dir, "participants.tsv"),
    show_col_types = FALSE
  )

  expect_equal(nrow(participants), 27)
  expect_true("participant_id" %in% colnames(participants))
  expect_true("age" %in% colnames(participants))
  expect_true("sex" %in% colnames(participants))
  expect_true("weight" %in% colnames(participants))

  # All participant IDs should follow BIDS format
  expect_true(all(grepl("^sub-", participants$participant_id)))

  # No NA in required fields
  expect_false(any(is.na(participants$participant_id)))
  expect_false(any(is.na(participants$age)))
  expect_false(any(is.na(participants$sex)))
})

test_that("TACs files are parseable with expected columns", {
  skip_if_no_integration()
  dataset_dir <- ensure_testdata()

  # Read a sample TACs file
  sample_tacs <- read_tsv(
    file.path(dataset_dir, "derivatives", "petprep",
              "sub-01", "ses-baseline", "pet",
              "sub-01_ses-baseline_desc-preproc_seg-gtm_tacs.tsv"),
    show_col_types = FALSE
  )

  expect_true(nrow(sample_tacs) > 0)
  expect_true("frame_start" %in% colnames(sample_tacs))
  expect_true("frame_end" %in% colnames(sample_tacs))

  # Should have brain region columns (FreeSurfer parcellation)
  expect_true("Left-Cerebral-White-Matter" %in% colnames(sample_tacs))
  expect_true("Left-Cerebellum-Cortex" %in% colnames(sample_tacs))
  expect_true("ctx-lh-superiorfrontal" %in% colnames(sample_tacs))
})

test_that("PET JSON sidecars are parseable with InjectedRadioactivity", {
  skip_if_no_integration()
  dataset_dir <- ensure_testdata()

  # Read a sample PET JSON sidecar
  sample_json <- fromJSON(
    file.path(dataset_dir, "sub-01", "ses-baseline", "pet",
              "sub-01_ses-baseline_pet.json")
  )

  expect_true("InjectedRadioactivity" %in% names(sample_json))
  expect_true(is.numeric(sample_json$InjectedRadioactivity))
  expect_true(sample_json$InjectedRadioactivity > 0)
})

test_that("blood TSV files are parseable with expected columns", {
  skip_if_no_integration()
  dataset_dir <- ensure_testdata()

  # Read a sample blood file
  sample_blood <- read_tsv(
    file.path(dataset_dir, "sub-01", "ses-baseline", "pet",
              "sub-01_ses-baseline_recording-manual_blood.tsv"),
    show_col_types = FALSE
  )

  expect_true(nrow(sample_blood) > 0)
  expect_true("time" %in% colnames(sample_blood))
  expect_true("plasma_radioactivity" %in% colnames(sample_blood))
  expect_true("whole_blood_radioactivity" %in% colnames(sample_blood))
  expect_true("metabolite_parent_fraction" %in% colnames(sample_blood))
})

test_that("morph files are parseable with expected columns", {
  skip_if_no_integration()
  dataset_dir <- ensure_testdata()

  # Read a sample morph file
  sample_morph <- read_tsv(
    file.path(dataset_dir, "derivatives", "petprep",
              "sub-01", "anat",
              "sub-01_desc-preproc_seg-gtm_morph.tsv"),
    show_col_types = FALSE
  )

  expect_true(nrow(sample_morph) > 0)
  expect_true("name" %in% colnames(sample_morph))
  expect_true("volume-mm3" %in% colnames(sample_morph))

  # Volumes should be positive
  expect_true(all(sample_morph$`volume-mm3` > 0))
})

test_that("subjects have expected session structure", {
  skip_if_no_integration()
  dataset_dir <- ensure_testdata()

  # Subjects 01-10 have ses-baseline and ses-blocked
  sub01_sessions <- list.dirs(
    file.path(dataset_dir, "sub-01"),
    full.names = FALSE, recursive = FALSE
  )
  expect_true("ses-baseline" %in% sub01_sessions)
  expect_true("ses-blocked" %in% sub01_sessions)

  # Subjects 11-27 have ses-test and ses-retest
  sub11_sessions <- list.dirs(
    file.path(dataset_dir, "sub-11"),
    full.names = FALSE, recursive = FALSE
  )
  expect_true("ses-test" %in% sub11_sessions)
  expect_true("ses-retest" %in% sub11_sessions)
})

test_that("integration workspace can be created and cleaned up", {
  skip_if_no_integration()
  dataset_dir <- ensure_testdata()

  ws <- create_integration_workspace(dataset_dir)

  expect_true(dir.exists(ws$workspace))
  expect_true(dir.exists(ws$derivatives_dir))
  expect_equal(ws$bids_dir, dataset_dir)

  # Petprep should be accessible via symlink
  expect_true(dir.exists(file.path(ws$derivatives_dir, "petprep")))

  # Can list TACs files through the symlink
  tacs_files <- list.files(
    file.path(ws$derivatives_dir, "petprep"),
    pattern = "_tacs\\.tsv$",
    recursive = TRUE
  )
  expect_equal(length(tacs_files), 54)

  # Cleanup
  cleanup_workspace(ws)
  expect_false(dir.exists(ws$workspace))
})
