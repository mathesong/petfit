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

# Regression: a derivatives tree containing only seg-* (or only label-*) TACs
# files must still be discovered. kinfitr::bids_parse_files() omits the column
# for any entity that never appears in the parsed filenames, so the filter
# inside summarise_tacs_descriptions() must tolerate a missing seg or label
# column rather than erroring with "object 'label' not found".
test_that("summarise_tacs_descriptions discovers seg-only TACs (no label entity)", {
  pipeline_dir <- file.path(tempdir(), "petfit_seg_only_summary")
  unlink(pipeline_dir, recursive = TRUE)

  pet_dir <- file.path(pipeline_dir, "sub-11", "ses-test", "pet")
  anat_dir <- file.path(pipeline_dir, "sub-11", "ses-test", "anat")
  purrr::walk(c(pet_dir, anat_dir), dir.create, recursive = TRUE, showWarnings = FALSE)

  tacs_file <- file.path(pet_dir, "sub-11_ses-test_trc-11CMC1_desc-preproc_seg-hammers_tacs.tsv")
  tacs_json <- file.path(pet_dir, "sub-11_ses-test_trc-11CMC1_desc-preproc_seg-hammers_tacs.json")
  morph_file <- file.path(anat_dir, "sub-11_ses-test_desc-preproc_seg-hammers_morph.tsv")
  morph_json <- file.path(anat_dir, "sub-11_ses-test_desc-preproc_seg-hammers_morph.json")
  file.create(c(tacs_file, tacs_json, morph_file, morph_json))

  result <- summarise_tacs_descriptions(pipeline_dir)

  expect_s3_class(result, "data.frame")
  expect_true("description" %in% colnames(result))
  expect_equal(nrow(result), 1L)
  expect_true(stringr::str_detect(result$description, "seg-hammers"))
  expect_false(stringr::str_detect(result$description, "label-"))
})

test_that("summarise_tacs_descriptions discovers label-only TACs (no seg entity)", {
  pipeline_dir <- file.path(tempdir(), "petfit_label_only_summary")
  unlink(pipeline_dir, recursive = TRUE)

  pet_dir <- file.path(pipeline_dir, "sub-11", "ses-test", "pet")
  anat_dir <- file.path(pipeline_dir, "sub-11", "ses-test", "anat")
  purrr::walk(c(pet_dir, anat_dir), dir.create, recursive = TRUE, showWarnings = FALSE)

  tacs_file <- file.path(pet_dir, "sub-11_ses-test_trc-11CMC1_desc-preproc_label-cerebellum_tacs.tsv")
  tacs_json <- file.path(pet_dir, "sub-11_ses-test_trc-11CMC1_desc-preproc_label-cerebellum_tacs.json")
  morph_file <- file.path(anat_dir, "sub-11_ses-test_desc-preproc_label-cerebellum_morph.tsv")
  morph_json <- file.path(anat_dir, "sub-11_ses-test_desc-preproc_label-cerebellum_morph.json")
  file.create(c(tacs_file, tacs_json, morph_file, morph_json))

  result <- summarise_tacs_descriptions(pipeline_dir)

  expect_s3_class(result, "data.frame")
  expect_true("description" %in% colnames(result))
  expect_equal(nrow(result), 1L)
  expect_true(stringr::str_detect(result$description, "label-cerebellum"))
  expect_false(stringr::str_detect(result$description, "seg-"))
})

test_that("create_tacs_list discovers seg-only TACs with matching morph files", {
  derivatives_dir <- file.path(tempdir(), "petfit_seg_only_derivatives")
  unlink(derivatives_dir, recursive = TRUE)

  pipeline_dir <- file.path(derivatives_dir, "pmod")
  pet_dir <- file.path(pipeline_dir, "sub-11", "ses-test", "pet")
  anat_dir <- file.path(pipeline_dir, "sub-11", "ses-test", "anat")
  purrr::walk(c(pet_dir, anat_dir), dir.create, recursive = TRUE, showWarnings = FALSE)

  tacs_file <- file.path(pet_dir, "sub-11_ses-test_trc-11CMC1_desc-preproc_seg-hammers_tacs.tsv")
  tacs_json <- file.path(pet_dir, "sub-11_ses-test_trc-11CMC1_desc-preproc_seg-hammers_tacs.json")
  morph_file <- file.path(anat_dir, "sub-11_ses-test_desc-preproc_seg-hammers_morph.tsv")
  morph_json <- file.path(anat_dir, "sub-11_ses-test_desc-preproc_seg-hammers_morph.json")
  file.create(c(tacs_file, tacs_json, morph_file, morph_json))

  tacs_list <- create_tacs_list(derivatives_dir)

  expect_s3_class(tacs_list, "data.frame")
  expect_gte(nrow(tacs_list), 1L)
  expect_true(any(tacs_list$tacs_path == tacs_file))
  expect_true(any(tacs_list$morph_path == morph_file))
})
