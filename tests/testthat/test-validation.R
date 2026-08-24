# Fixtures use NA for absent entities, matching what
# extract_bids_attributes_from_filename() writes into the combined TACs file.
# (Some older fixtures in test-subsetting_utils.R use "" instead, which does not
# reflect real data.)
validation_tacs <- function() {
  tibble::tibble(
    sub    = c("01", "01", "02", "02", "03"),
    ses    = c("test", "test", "test", "test", NA_character_),
    task   = NA_character_,
    trc    = "pf974",
    rec    = NA,                       # all-NA reads back as a logical column
    run    = c(1L, 1L, 1L, 2L, 1L),    # integer, as readr parses it
    region = c("cortex", "amygdala", "cortex", "amygdala", "cortex"),
    TAC    = c(1, 2, 3, 4, 5)
  )
}

# Mark a hand-built value vector as an exclusion, as parse_semicolon_values does.
as_excluded <- function(x) {
  attr(x, "negate") <- TRUE
  x
}

test_that("validate_subset_params passes when every value matches", {

  d <- validation_tacs()

  expect_true(validate_subset_params(d, list(sub = c("01", "02"))))
  expect_true(validate_subset_params(d, list(regions = "cortex", ses = "test")))

  # No parameters at all, in each of the shapes callers actually produce
  expect_true(validate_subset_params(d, list()))
  expect_true(validate_subset_params(d, NULL))
  expect_true(validate_subset_params(d, list(sub = NULL, ses = NULL)))
})

test_that("validate_subset_params errors on an included value matching nothing", {

  d <- validation_tacs()

  # Names the offending value...
  expect_error(validate_subset_params(d, list(regions = c("cortex", "amygdla"))),
               "amygdla")
  # ...and lists what is actually available
  expect_error(validate_subset_params(d, list(regions = "amygdla")),
               "Available \\(2\\): amygdala, cortex")
  # ...under the label the user typed it into, not the column name
  expect_error(validate_subset_params(d, list(regions = "amygdla")),
               "Regions:")
})

test_that("validate_subset_params reports every bad field in one error", {

  d <- validation_tacs()

  err <- tryCatch(
    validate_subset_params(d, list(sub = "99", regions = "amygdla")),
    error = function(e) conditionMessage(e)
  )

  expect_match(err, "sub: \"99\"")
  expect_match(err, "Regions: \"amygdla\"")
})

test_that("validate_subset_params handles absent and all-NA columns", {

  d <- validation_tacs()

  # rec exists but is NA throughout
  expect_error(validate_subset_params(d, list(rec = "recA")),
               "no row in the data carries a rec value")

  # run is dropped entirely
  expect_error(validate_subset_params(d[, setdiff(names(d), "run")], list(run = "1")),
               "no row in the data carries a run value")
})

test_that("validate_subset_params coerces like %in% does", {

  d <- validation_tacs()

  # run is an integer column; subsetting values always arrive as text. The
  # validator must agree with the filter it guards, where 1 %in% "1" is TRUE.
  expect_true(validate_subset_params(d, list(run = c("1", "2"))))
  expect_error(validate_subset_params(d, list(run = "3")), "run: \"3\"")
})

test_that("validate_subset_params rejects commas in hand-built parameters", {

  d <- validation_tacs()

  # subset_combined_tacs() is exported, so a caller can bypass
  # parse_semicolon_values() entirely. Guard anyway.
  expect_error(validate_subset_params(d, list(regions = "cortex, amygdala")),
               "may not contain commas")
  expect_error(validate_subset_params(d, list(regions = "cortex, amygdala")),
               "Did you mean")
})

test_that("validate_subset_params rejects unknown fields", {

  d <- validation_tacs()

  expect_error(validate_subset_params(d, list(seg = "gtm")), "Unknown subsetting field")
  expect_error(validate_subset_params(d, list("01")), "named list")
})

test_that("validate_subset_params warns rather than errors on unmatched exclusions", {

  d <- validation_tacs()

  # A typo'd exclusion leaves the analysis complete rather than wrong, so it
  # warns; but it must not pass in silence, because the user believes they
  # removed something they did not.
  expect_warning(validate_subset_params(d, list(ses = as_excluded("tset"))),
                 "nothing was excluded")
  expect_warning(validate_subset_params(d, list(ses = as_excluded("tset"))),
                 "Available \\(1\\): test")

  # A matching exclusion is silent
  expect_silent(validate_subset_params(d, list(ses = as_excluded("test"))))
})

test_that("validate_subset_params judges included and excluded fields independently", {

  d <- validation_tacs()

  params <- list(sub = "99", ses = as_excluded("tset"))

  # The bad include still errors...
  expect_error(suppressWarnings(validate_subset_params(d, params)), "sub: \"99\"")
  # ...and the bad exclude still warns
  expect_warning(try(validate_subset_params(d, params), silent = TRUE), "ses")
})

# ---------------------------------------------------------------------------
# validate_min_regions_per_pet: region counts for nested models
# ---------------------------------------------------------------------------

test_that("validate_min_regions_per_pet summarises region counts per measurement", {

  d <- tibble::tibble(
    pet = rep(c("sub-01_ses-a", "sub-02_ses-a"), each = 6),
    region = rep(c("Frontal", "Temporal", "Occipital"), times = 4),
    TAC = rnorm(12)
  )

  counts <- validate_min_regions_per_pet(d, min_regions = 2)

  expect_equal(nrow(counts), 2)
  expect_equal(counts$n_regions, c(3, 3))
  expect_true(all(counts$sufficient))
})

test_that("validate_min_regions_per_pet warns about insufficient measurements", {

  d <- tibble::tibble(
    pet = c(rep("sub-01_ses-a", 3), rep("sub-02_ses-a", 1)),
    region = c("Frontal", "Temporal", "Occipital", "Frontal")
  )

  expect_warning(counts <- validate_min_regions_per_pet(d, min_regions = 2),
                 "sub-02_ses-a")
  expect_equal(counts$sufficient, c(TRUE, FALSE))
})

test_that("validate_min_regions_per_pet errors when no measurement has enough regions", {

  d <- tibble::tibble(
    pet = c("sub-01_ses-a", "sub-02_ses-a"),
    region = c("Frontal", "Frontal")
  )

  expect_error(validate_min_regions_per_pet(d, min_regions = 2),
               "at least 2 regions")
})

test_that("validate_min_regions_per_pet requires pet and region columns", {

  expect_error(validate_min_regions_per_pet(tibble::tibble(pet = "a")),
               "must contain")
})
