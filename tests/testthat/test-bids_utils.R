# attributes_to_title() is deprecated and its behaviour is deliberately not
# pinned here. It builds an identifier from whichever attributes vary across the
# data it is handed, which is the defect this work removes -- tests asserting
# that output stays the same would be protecting the bug. What is worth holding
# is that it still announces itself as deprecated, and that pet_key(), which
# replaces it, is correct.

test_that("the model entity is visible to the BIDS parser", {

  # This is the point of writing model-2TCM rather than model_2TCM. The
  # underscore form is not an entity at all: an underscore separates entities,
  # so the parser sees no `model` key and the artifact cannot be tied back to
  # the model that produced it.
  legacy <- kinfitr:::bids_filename_attributes(
    "sub-01_ses-test_model_2TCM_desc-model1_kinpar.tsv")
  expect_false("model" %in% colnames(legacy))

  current <- kinfitr:::bids_filename_attributes(
    "sub-01_ses-test_model-2TCM_desc-model1_kinpar.tsv")
  expect_true("model" %in% colnames(current))
  expect_equal(current$model, "2TCM")

  # The irreversible 2TCM is stored as "2TCM_irr" everywhere else in petfit,
  # which cannot be a label for the same reason. It is emitted as 2TCMirr.
  irr <- kinfitr:::bids_filename_attributes(
    "sub-01_model-2TCMirr_desc-model1_kinpar.tsv")
  expect_equal(irr$model, "2TCMirr")
})


test_that("attributes_to_title says it is deprecated", {

  bidsdata <- tibble::tibble(
    sub = c("01", "02"),
    ses = c("01", "02"),
    filedata = list(tibble::tibble(x = 1), tibble::tibble(x = 2))
  )

  expect_warning(attributes_to_title(bidsdata), "deprecated")
  expect_warning(attributes_to_title(bidsdata), "pet_key")
})

test_that("pet_key is built from a measurement's own path", {

  paths <- c("sub-01/ses-test/pet/sub-01_desc-combinedregions_tacs.tsv",
             "sub-02/pet/sub-02_desc-combinedregions_tacs.tsv")

  keys <- pet_key(paths)

  # The session lives in the directory, not the filename, and still counts
  expect_equal(keys[1], "sub-01_ses-test")
  # A subject stored without a session does not acquire one
  expect_equal(keys[2], "sub-02")
})

test_that("pet_key does not depend on the rest of the cohort", {

  # This is the whole point. The identifier it replaces was built from only the
  # attributes that varied across the cohort, so adding one retest scan renamed
  # every existing measurement and orphaned their files.
  two <- c("sub-01/ses-test/pet/sub-01_desc-combinedregions_tacs.tsv",
           "sub-02/ses-test/pet/sub-02_desc-combinedregions_tacs.tsv")
  three <- c(two, "sub-01/ses-retest/pet/sub-01_desc-combinedregions_tacs.tsv")

  expect_equal(pet_key(two), pet_key(three)[1:2])

  # Including when the cohort is a single measurement, which used to produce a
  # key matching no file at all and so an empty PET dropdown
  expect_equal(pet_key(two[1]), "sub-01_ses-test")
})

test_that("pet_key reads entities relative to the analysis folder", {

  root <- withr::local_tempdir()
  # A directory above the analysis folder that looks like a BIDS entity
  nested <- file.path(root, "trc-decoy", "analysis1")
  dir.create(file.path(nested, "sub-01", "pet"), recursive = TRUE)
  f <- file.path(nested, "sub-01", "pet", "sub-01_desc-combinedregions_tacs.tsv")
  file.create(f)

  expect_equal(pet_key(f, nested), "sub-01")
})

test_that("pet_key handles empty input and unkeyable paths", {

  expect_equal(pet_key(character(0)), character(0))
  expect_true(is.na(pet_key("reports/model1_report.html")))
})

test_that("pet_label shortens for display without becoming an identity", {

  keys <- c("sub-01_ses-test", "sub-02_ses-test")

  # The shared session is dropped for readability...
  expect_equal(pet_label(keys), c("sub-01", "sub-02"))

  # ...but the keys themselves are untouched, and it is those that get written
  expect_equal(keys, c("sub-01_ses-test", "sub-02_ses-test"))

  # A single measurement keeps its full key rather than collapsing to nothing
  expect_equal(pet_label("sub-01_ses-test"), "sub-01_ses-test")
  expect_equal(pet_label(character(0)), character(0))
})

test_that("pet_key strips the analysis folder literally, not as a pattern", {

  # The folder path is user-chosen text: regex metacharacters in it must not
  # change what gets stripped.
  root <- file.path(tempdir(), "analysis (copy) + extra")
  dir.create(file.path(root, "sub-01_ses-test"), recursive = TRUE,
             showWarnings = FALSE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  f <- file.path(root, "sub-01_ses-test",
                 "sub-01_ses-test_desc-combinedregions_tacs.tsv")
  file.create(f)

  expect_equal(pet_key(f, root), "sub-01_ses-test")
})
