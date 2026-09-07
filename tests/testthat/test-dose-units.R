# An InjectedRadioactivity with no InjectedRadioactivityUnits beside it is now
# read as MBq, which BIDS recommends. The extractors report the assumption
# rather than warning about it where they stand, because they run in furrr
# workers; create_petfit_combined_tacs() warns once per measurement in the
# parent.

write_tacs_pair <- function(dir, stem, metadata) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  readr::write_tsv(
    tibble::tibble(frame_start = c(0, 60), frame_end = c(60, 120), TAC = c(1, 2)),
    file.path(dir, paste0(stem, ".tsv"))
  )
  jsonlite::write_json(metadata, file.path(dir, paste0(stem, ".json")),
                       auto_unbox = TRUE)
}

test_that("an unlabelled dose is read as MBq, and says which measurement", {
  root <- withr::local_tempdir()

  write_tacs_pair(file.path(root, "sub-01", "ses-01", "pet"),
                  "sub-01_ses-01_desc-preproc_tacs",
                  list(InjectedRadioactivity = 300))

  expect_no_warning(
    result <- extract_pet_metadata_from_tacs_json(
      root, "sub-01/ses-01/pet/sub-01_ses-01_desc-preproc_tacs.tsv")
  )

  # 300 MBq, converted to the kBq everything downstream works in.
  expect_equal(result$InjectedRadioactivity, 3e5)
  expect_equal(result$InjectedRadioactivityUnits, "kBq")
  # The measurement, not the region definition file: the same dose is read once
  # per segmentation.
  expect_equal(result$AssumedDoseUnitsFor, "sub-01_ses-01")
})

test_that("units that are present are honoured, without a warning", {
  root <- withr::local_tempdir()
  reset_dose_unit_warnings()

  write_tacs_pair(file.path(root, "sub-01", "ses-01", "pet"),
                  "sub-01_ses-01_desc-preproc_tacs",
                  list(InjectedRadioactivity = 300,
                       InjectedRadioactivityUnits = "MBq"))

  expect_no_warning(
    result <- extract_pet_metadata_from_tacs_json(
      root, "sub-01/ses-01/pet/sub-01_ses-01_desc-preproc_tacs.tsv")
  )
  expect_equal(result$InjectedRadioactivity, 3e5)
  expect_true(is.na(result$AssumedDoseUnitsFor))

  # And a dose already in kBq is left alone.
  write_tacs_pair(file.path(root, "sub-02", "ses-01", "pet"),
                  "sub-02_ses-01_desc-preproc_tacs",
                  list(InjectedRadioactivity = 3e5,
                       InjectedRadioactivityUnits = "kBq"))
  in_kbq <- extract_pet_metadata_from_tacs_json(
    root, "sub-02/ses-01/pet/sub-02_ses-01_desc-preproc_tacs.tsv")
  expect_equal(in_kbq$InjectedRadioactivity, 3e5)
})

test_that("no dose at all is left as NA, so the BIDS metadata can be tried", {
  root <- withr::local_tempdir()
  reset_dose_unit_warnings()

  write_tacs_pair(file.path(root, "sub-01", "ses-01", "pet"),
                  "sub-01_ses-01_desc-preproc_tacs",
                  list(Units = "Bq/mL"))

  expect_no_warning(
    result <- extract_pet_metadata_from_tacs_json(
      root, "sub-01/ses-01/pet/sub-01_ses-01_desc-preproc_tacs.tsv")
  )
  # NA is what makes the caller fall back to the raw BIDS metadata.
  expect_true(is.na(result$InjectedRadioactivity))
})

test_that("every segmentation of a measurement names the same measurement", {
  root <- withr::local_tempdir()

  pet_dir <- file.path(root, "sub-01", "ses-01", "pet")
  # One measurement, several region definitions, as a real segmentation set has.
  stems <- c("sub-01_ses-01_seg-gtm_desc-preproc_tacs",
             "sub-01_ses-01_seg-HOcortical_desc-preproc_tacs",
             "sub-01_ses-01_label-cerebellum_desc-preproc_tacs")
  for (stem in stems) {
    write_tacs_pair(pet_dir, stem, list(InjectedRadioactivity = 300))
  }

  assumed_for <- vapply(stems, function(stem) {
    extract_pet_metadata_from_tacs_json(
      root, file.path("sub-01/ses-01/pet", paste0(stem, ".tsv")))$AssumedDoseUnitsFor
  }, character(1))

  # The caller collects these and warns once per distinct measurement, so all
  # three must reduce to one.
  expect_equal(unique(unname(assumed_for)), "sub-01_ses-01")
})

test_that("the warning is raised once per measurement, and again after a reset", {
  reset_dose_unit_warnings()

  expect_warning(warn_assumed_dose_units("sub-01_ses-01"),
                 "No InjectedRadioactivityUnits found")
  # The same measurement again: already said.
  expect_no_warning(warn_assumed_dose_units("sub-01_ses-01"))

  # A different measurement warns on its own account.
  expect_warning(warn_assumed_dose_units("sub-02_ses-01"), "sub-02")

  # And a second run of the region definition step says it all again.
  reset_dose_unit_warnings()
  expect_warning(warn_assumed_dose_units("sub-01_ses-01"))
})
