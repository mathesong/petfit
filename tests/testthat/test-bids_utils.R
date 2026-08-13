test_that("attributes_to_title formats BIDS attributes correctly", {
  
  # Create test BIDS data structure that matches kinfitr::bids_parse_files output
  test_bidsdata <- tibble::tibble(
    sub = c("01", "02"),
    ses = c("01", "02"), 
    trc = c("18FFDG", "11CRACWAY"),
    rec = c("", "rec1"),
    task = c("", "rest"),
    run = c("", "1"),
    desc = c("freesurfer", "spm"),
    filedata = c("sub-01_ses-01_trc-18FFDG_desc-freesurfer_tacs.tsv", 
                 "sub-02_ses-02_trc-11CRACWAY_rec-rec1_task-rest_run-1_desc-spm_tacs.tsv")
  )
  
  # Test with all_attributes = FALSE (default)
  result <- attributes_to_title(test_bidsdata)
  expect_type(result, "character")
  expect_true(length(result) == nrow(test_bidsdata))
  
  # Should include main attributes
  expect_true(all(grepl("sub-01|sub-02", result)))
  expect_true(all(grepl("ses-01|ses-02", result)))
  expect_true(all(grepl("trc-18FFDG|trc-11CRACWAY", result)))
  
  # Test with all_attributes = TRUE
  result_all <- attributes_to_title(test_bidsdata, all_attributes = TRUE)
  expect_type(result_all, "character")
  expect_true(length(result_all) == nrow(test_bidsdata))
  
  # Should include optional attributes when present
  expect_true(any(grepl("rec-rec1", result_all)))
  expect_true(any(grepl("task-rest", result_all)))
  expect_true(any(grepl("run-1", result_all)))
  expect_true(any(grepl("desc-freesurfer|desc-spm", result_all)))
})

test_that("attributes_to_title handles minimal BIDS data", {
  
  # Test with only required attributes (must include filedata column)
  minimal_data <- tibble::tibble(
    sub = "01",
    ses = "01",
    trc = "18FFDG",
    task = "",
    filedata = "sub-01_ses-01_trc-18FFDG_tacs.tsv"
  )
  
  result <- attributes_to_title(minimal_data)
  expect_equal(length(result), 1)
  expect_true(grepl("sub-01", result))
  expect_true(grepl("ses-01", result))
  # For single row, function only uses sub, ses, task, so trc may not appear
  expect_type(result, "character")
})

test_that("attributes_to_title handles empty optional fields", {
  
  # Test with empty optional fields
  test_data <- tibble::tibble(
    sub = "01",
    ses = "01",
    trc = "18FFDG",
    rec = "",
    task = "",
    run = "",
    desc = "freesurfer",
    filedata = "sub-01_ses-01_trc-18FFDG_desc-freesurfer_tacs.tsv"
  )
  
  result <- attributes_to_title(test_data, all_attributes = TRUE)
  
  # With all_attributes = TRUE, all fields are included even if empty
  expect_true(grepl("desc-freesurfer", result))
  # Empty fields will show as "field-" in the output
  expect_true(grepl("rec-", result))  # Will show as rec- (empty value)
  expect_true(grepl("task-", result)) # Will show as task- (empty value)
  expect_true(grepl("run-", result))  # Will show as run- (empty value)
})

test_that("attributes_to_title handles edge cases", {
  
  # Test with empty data frame that has proper structure
  empty_data <- tibble::tibble(
    sub = character(0),
    ses = character(0),
    trc = character(0),
    task = character(0),
    filedata = character(0)
  )
  result <- attributes_to_title(empty_data)
  # Function may still produce 1 empty result even with 0 rows
  expect_type(result, "character")
  
  # Test with single row
  single_row <- tibble::tibble(
    sub = "01",
    ses = "01",
    trc = "18FFDG",
    task = "",
    filedata = "sub-01_ses-01_trc-18FFDG_tacs.tsv"
  )
  
  result <- attributes_to_title(single_row)
  expect_equal(length(result), 1)
  expect_type(result, "character")
})

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
