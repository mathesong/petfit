test_that("create_tacs_morph_mapping reuses a single session morph across PET sessions", {
  pipeline_dir <- file.path(tempdir(), "petfit_mapping_single_session_morph")
  unlink(pipeline_dir, recursive = TRUE)

  pet_dirs <- file.path(pipeline_dir, "sub-01", c("ses-01", "ses-02", "ses-03"), "pet")
  anat_dir <- file.path(pipeline_dir, "sub-01", "ses-01", "anat")
  purrr::walk(c(pet_dirs, anat_dir), dir.create, recursive = TRUE, showWarnings = FALSE)

  tacs_files <- file.path(
    pet_dirs,
    c(
      "sub-01_ses-01_trc-FDG_desc-preproc_seg-gtm_tacs.tsv",
      "sub-01_ses-02_trc-MK6240_desc-preproc_seg-gtm_tacs.tsv",
      "sub-01_ses-03_trc-FBB_desc-preproc_seg-gtm_tacs.tsv"
    )
  )
  morph_file <- file.path(anat_dir, "sub-01_ses-01_desc-preproc_seg-gtm_morph.tsv")

  file.create(c(tacs_files, morph_file))

  mapping <- create_tacs_morph_mapping(pipeline_dir)

  expect_equal(nrow(mapping), 3)
  expect_setequal(mapping$tacs_path, tacs_files)
  expect_true(all(mapping$morph_path == morph_file))
})

test_that("create_tacs_morph_mapping does not choose an ambiguous cross-session morph", {
  pipeline_dir <- file.path(tempdir(), "petfit_mapping_ambiguous_session_morph")
  unlink(pipeline_dir, recursive = TRUE)

  pet_dir <- file.path(pipeline_dir, "sub-01", "ses-03", "pet")
  anat_dirs <- file.path(pipeline_dir, "sub-01", c("ses-01", "ses-02"), "anat")
  purrr::walk(c(pet_dir, anat_dirs), dir.create, recursive = TRUE, showWarnings = FALSE)

  tacs_file <- file.path(pet_dir, "sub-01_ses-03_trc-FBB_desc-preproc_seg-gtm_tacs.tsv")
  morph_files <- file.path(
    anat_dirs,
    c(
      "sub-01_ses-01_desc-preproc_seg-gtm_morph.tsv",
      "sub-01_ses-02_desc-preproc_seg-gtm_morph.tsv"
    )
  )

  file.create(c(tacs_file, morph_files))

  mapping <- create_tacs_morph_mapping(pipeline_dir)

  expect_equal(nrow(mapping), 0)
})

test_that("summarise_tacs_descriptions handles seg-only TACs without label entity", {
  pipeline_dir <- file.path(tempdir(), "petfit_seg_only_tacs")
  unlink(pipeline_dir, recursive = TRUE)

  pet_dir <- file.path(pipeline_dir, "sub-01", "ses-test", "pet")
  dir.create(pet_dir, recursive = TRUE, showWarnings = FALSE)
  file.create(file.path(
    pet_dir,
    "sub-01_ses-test_trc-11CMC1_desc-preproc_seg-hammers_tacs.tsv"
  ))

  descriptions <- summarise_tacs_descriptions(pipeline_dir)

  expect_equal(nrow(descriptions), 1)
  expect_equal(descriptions$description, "seg-hammers_desc-preproc")
})

test_that("summarise_tacs_descriptions handles label-only TACs without seg entity", {
  pipeline_dir <- file.path(tempdir(), "petfit_label_only_tacs")
  unlink(pipeline_dir, recursive = TRUE)

  pet_dir <- file.path(pipeline_dir, "sub-01", "ses-test", "pet")
  dir.create(pet_dir, recursive = TRUE, showWarnings = FALSE)
  file.create(file.path(
    pet_dir,
    "sub-01_ses-test_trc-11CMC1_desc-preproc_label-cerebellum_tacs.tsv"
  ))

  descriptions <- summarise_tacs_descriptions(pipeline_dir)

  expect_equal(nrow(descriptions), 1)
  expect_equal(descriptions$description, "label-cerebellum_desc-preproc")
})

test_that("create_tacs_list discovers seg-only TACs with matching morph files", {
  derivatives_dir <- file.path(tempdir(), "petfit_seg_only_derivatives")
  unlink(derivatives_dir, recursive = TRUE)

  pipeline_dir <- file.path(derivatives_dir, "pmod")
  pet_dir <- file.path(pipeline_dir, "sub-11", "ses-test", "pet")
  anat_dir <- file.path(pipeline_dir, "sub-11", "ses-test", "anat")
  purrr::walk(c(pet_dir, anat_dir), dir.create, recursive = TRUE, showWarnings = FALSE)

  tacs_file <- file.path(pet_dir, "sub-11_ses-test_trc-11CMC1_desc-preproc_seg-hammers_tacs.tsv")
  morph_file <- file.path(anat_dir, "sub-11_ses-test_desc-preproc_seg-hammers_morph.tsv")
  file.create(c(tacs_file, morph_file))

  tacs_list <- create_tacs_list(derivatives_dir)

  expect_equal(nrow(tacs_list), 1L)
  expect_equal(tacs_list$tacs_path, tacs_file)
  expect_equal(tacs_list$morph_path, morph_file)
  expect_equal(tacs_list$description, "seg-hammers_desc-preproc")
})

test_that("extract_bids_attributes_from_filename fills absent entities with NA", {

  # The combined TACs file is built from this function's output, so whatever it
  # writes for an absent entity is what subsetting later has to validate
  # against. It emits every selector column unconditionally, using NA — not ""
  # — where the filename is silent.

  full <- extract_bids_attributes_from_filename(
    "sub-01_ses-test_trc-pf974_rec-acdyn_task-rest_run-1_desc-preproc_tacs.tsv")

  expect_equal(full$sub, "01")
  expect_equal(full$ses, "test")
  expect_equal(full$trc, "pf974")
  expect_equal(full$rec, "acdyn")
  expect_equal(full$task, "rest")
  expect_equal(full$run, "1")

  sparse <- extract_bids_attributes_from_filename("sub-01_desc-preproc_tacs.tsv")

  # Every selector column is still present...
  expect_true(all(c("sub", "ses", "trc", "rec", "task", "run") %in% names(sparse)))
  # ...and the ones the filename omits are NA, not empty strings
  expect_equal(sparse$sub, "01")
  expect_true(is.na(sparse$ses))
  expect_true(is.na(sparse$trc))
  expect_true(is.na(sparse$rec))
  expect_true(is.na(sparse$task))
  expect_true(is.na(sparse$run))
  expect_false(any(c(sparse$ses, sparse$trc, sparse$rec) %in% ""))
})

test_that("a measurement's pet identifier does not depend on the cohort", {

  # The adversarial case: two ses-test subjects, then the study gains its
  # first ses-retest scan. Identity built from cohort-varying attributes
  # renamed the original measurements and orphaned their files.
  entity_attrs <- function(data) {
    intersect(c("sub", "ses", "task", "trc", "rec", "run"), colnames(data))
  }

  before <- tibble::tibble(sub = c("01", "02"), ses = c("test", "test"))
  after <- tibble::tibble(sub = c("01", "02", "01"),
                          ses = c("test", "test", "retest"))

  pets_before <- reconstruct_pet_column(before, entity_attrs(before))$pet
  pets_after <- reconstruct_pet_column(after, entity_attrs(after))$pet

  expect_equal(pets_before, c("sub-01_ses-test", "sub-02_ses-test"))
  expect_equal(pets_after[1:2], pets_before)
})

test_that("pet identifiers skip absent entities and match pet_key", {

  # A sessionless measurement in a mixed study carries NA in the ses column;
  # its identifier must not contain ses-NA. And the stem written to disk must
  # read back through pet_key() unchanged.
  data <- tibble::tibble(sub = c("01", "02"), ses = c("test", NA))
  attrs <- intersect(c("sub", "ses", "task", "trc", "rec", "run"),
                     colnames(data))
  pets <- reconstruct_pet_column(data, attrs)$pet

  expect_equal(pets, c("sub-01_ses-test", "sub-02"))
  expect_equal(pet_key(paste0(pets, "_desc-combinedregions_tacs.tsv")), pets)
})

test_that("directories supply sub and ses to file attributes", {

  # petfit's derivatives put ses in the path but not the filename. Reducing
  # the path to its basename merged distinct sessions into one measurement.
  test_ses <- extract_bids_attributes_from_filename(
    "sub-01/ses-test/pet/sub-01_desc-preproc_tacs.tsv")
  retest <- extract_bids_attributes_from_filename(
    "sub-01/ses-retest/pet/sub-01_desc-preproc_tacs.tsv")

  expect_equal(test_ses$ses, "test")
  expect_equal(retest$ses, "retest")
  expect_equal(test_ses$sub, "01")

  # Only whole sub-/ses- segments count: unrelated path components with
  # hyphens must not inject entities
  plain <- extract_bids_attributes_from_filename(
    "some-folder/sub-01_ses-a_desc-x_tacs.tsv")
  expect_equal(plain$ses, "a")
  expect_false("some" %in% colnames(plain))
})

test_that("a directory contradicting the filename is an error", {

  expect_error(
    extract_bids_attributes_from_filename(
      "sub-01/ses-test/pet/sub-01_ses-retest_desc-x_tacs.tsv"),
    "disagree on ses")
})
