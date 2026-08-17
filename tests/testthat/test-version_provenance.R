# Version provenance: petfit stamps what it writes, and warns when a later step
# meets a file an older version wrote. Warn, never stop -- the analysis may be
# perfectly fine, and the user is the one who decides whether to regenerate.

test_that("petfit_generated_by() records name and running version", {
  gb <- petfit_generated_by()
  expect_equal(gb$Name, "petfit")
  expect_equal(gb$Version, as.character(utils::packageVersion("petfit")))
})

test_that("a current version passes silently", {
  current <- as.character(utils::packageVersion("petfit"))
  expect_silent(petfit_check_version(list(petfit_version = current), "config"))
  expect_true(petfit_check_version(list(petfit_version = current), "config"))
  expect_silent(petfit_check_version(
    list(GeneratedBy = list(list(Name = "petfit", Version = current))), "sidecar"))
})

test_that("an older version warns and says to re-run region definition", {
  expect_warning(res <- petfit_check_version(list(petfit_version = "0.0.1"), "config"),
                 "older than")
  expect_false(res)
  expect_warning(petfit_check_version(list(petfit_version = "0.0.1"), "config"),
                 "region definition")
})

test_that("a missing version warns rather than passing", {
  expect_warning(res <- petfit_check_version(list(), "analysis configuration"),
                 "does not record which version")
  expect_false(res)
})

test_that("an unreadable version warns rather than erroring", {
  expect_warning(petfit_check_version(list(petfit_version = "not-a-version"), "config"),
                 "unreadable")
})

test_that("GeneratedBy is read from the data-frame shape jsonlite may return", {
  current <- as.character(utils::packageVersion("petfit"))
  df <- data.frame(Name = c("other", "petfit"), Version = c("9.9.9", current))
  expect_silent(petfit_check_version(list(GeneratedBy = df), "sidecar"))
  old <- data.frame(Name = "petfit", Version = "0.0.1")
  expect_warning(petfit_check_version(list(GeneratedBy = old), "sidecar"), "older than")
})

test_that("the combined TACs check reads the sidecar beside the file", {
  dir <- withr::local_tempdir()
  tsv <- file.path(dir, "desc-combinedregions_tacs.tsv")
  writeLines("pet\tregion\nsub-01\tCortex", tsv)

  # no sidecar at all: nothing to check, and no noise about it
  expect_silent(petfit_check_combined_tacs_version(tsv))

  json <- file.path(dir, "desc-combinedregions_tacs.json")
  jsonlite::write_json(list(GeneratedBy = list(list(Name = "petfit", Version = "0.0.1"))),
                       json, auto_unbox = TRUE)
  expect_warning(petfit_check_combined_tacs_version(tsv),
                 "combined regions TACs file")

  jsonlite::write_json(list(pet = list(Description = "id")), json, auto_unbox = TRUE)
  expect_warning(petfit_check_combined_tacs_version(tsv),
                 "does not record which version")

  jsonlite::write_json(list(GeneratedBy = list(petfit_generated_by())),
                       json, auto_unbox = TRUE)
  expect_silent(petfit_check_combined_tacs_version(tsv))
})

test_that("notify receives the same message as the warning", {
  seen <- NULL
  suppressWarnings(
    petfit_check_version(list(petfit_version = "0.0.1"), "config",
                         notify = function(msg, type) seen <<- list(msg = msg, type = type)))
  expect_equal(seen$type, "warning")
  expect_match(seen$msg, "older than")
})
