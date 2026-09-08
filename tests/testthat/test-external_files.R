# Unit tests for externally supplied config and regions files
#
# These cover the helpers which copy a user-supplied file into the location
# petfit expects, and the plumbing of those helpers through the automatic
# pipelines.

regions_columns <- c("RegionName", "folder", "description", "ConstituentRegion")

make_derivatives <- function(root, folder = "freesurfer") {
  deriv <- file.path(root, "derivatives")
  dir.create(file.path(deriv, folder), recursive = TRUE, showWarnings = FALSE)
  deriv
}

write_regions_fixture <- function(path, region = "Cerebellum") {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  readr::write_tsv(
    tibble::tibble(
      RegionName = region,
      folder = "freesurfer",
      description = "seg-gtm_desc-preproc",
      ConstituentRegion = "Left-Cerebellum-Cortex"
    ),
    path
  )
  path
}

write_config_fixture <- function(path, type = "plasma input") {
  jsonlite::write_json(
    list(modelling_configuration_type = type,
         Subsetting = list(sub = ""),
         Models = list(Model1 = list(type = "none"))),
    path,
    auto_unbox = TRUE
  )
  path
}

# ---------------------------------------------------------------------------
# install_external_file()
# ---------------------------------------------------------------------------

test_that("install_external_file copies the file and reports where it went", {
  tmp <- withr::local_tempdir()
  source <- write_regions_fixture(file.path(tmp, "external_regions.tsv"))
  destination <- file.path(tmp, "derivatives", "petfit", "petfit_regions.tsv")

  install <- install_external_file(source, destination, label = "regions file")
  messages <- install$messages

  expect_true(file.exists(destination))
  expect_equal(
    readr::read_tsv(destination, show_col_types = FALSE)$RegionName,
    "Cerebellum"
  )
  expect_true(any(grepl("External regions file", messages)))
  expect_true(any(grepl(basename(source), messages, fixed = TRUE)))
  expect_true(any(grepl("Copied to", messages)))
  # Nothing was replaced, so no replacement warning and no backup
  expect_false(any(grepl("REPLACED", messages)))
  expect_null(install$backup)
})

test_that("install_external_file flags that an existing file was replaced", {
  tmp <- withr::local_tempdir()
  source <- write_regions_fixture(file.path(tmp, "external_regions.tsv"), "Thalamus")
  destination <- write_regions_fixture(file.path(tmp, "petfit_regions.tsv"), "Cerebellum")

  install <- install_external_file(source, destination, label = "regions file")
  messages <- install$messages

  expect_true(any(grepl("REPLACED", messages)))
  expect_equal(
    readr::read_tsv(destination, show_col_types = FALSE)$RegionName,
    "Thalamus"
  )
})

test_that("install_external_file leaves the file alone when source is the destination", {
  tmp <- withr::local_tempdir()
  path <- write_regions_fixture(file.path(tmp, "petfit_regions.tsv"))

  messages <- install_external_file(path, path, label = "regions file")$messages

  expect_true(any(grepl("same file", messages)))
  expect_true(file.exists(path))
})

test_that("install_external_file rejects a missing file or a directory", {
  tmp <- withr::local_tempdir()

  expect_error(
    install_external_file(file.path(tmp, "absent.tsv"), file.path(tmp, "out.tsv")),
    "does not exist"
  )
  expect_error(
    install_external_file(tmp, file.path(tmp, "out.tsv")),
    "is a directory"
  )
})

# ---------------------------------------------------------------------------
# check_external_config()
# ---------------------------------------------------------------------------

test_that("check_external_config accepts valid JSON and returns the config", {
  tmp <- withr::local_tempdir()
  config_file <- write_config_fixture(file.path(tmp, "config.json"))

  config <- check_external_config(config_file)

  expect_equal(config$modelling_configuration_type, "plasma input")
})

test_that("check_external_config rejects malformed JSON", {
  tmp <- withr::local_tempdir()
  config_file <- file.path(tmp, "config.json")
  writeLines("{not valid json", config_file)

  expect_error(check_external_config(config_file), "not valid JSON")
})

test_that("check_external_config rejects a config for the wrong modelling type", {
  tmp <- withr::local_tempdir()
  config_file <- write_config_fixture(file.path(tmp, "config.json"), "reference tissue")

  expect_error(
    check_external_config(config_file, expected_type = "plasma input"),
    "reference tissue"
  )
  expect_silent(check_external_config(config_file, expected_type = "reference tissue"))
})

# ---------------------------------------------------------------------------
# check_external_regions_file()
# ---------------------------------------------------------------------------

test_that("check_external_regions_file accepts a well-formed regions file", {
  tmp <- withr::local_tempdir()
  regions_file <- write_regions_fixture(file.path(tmp, "petfit_regions.tsv"))

  regions <- check_external_regions_file(regions_file)

  expect_true(all(regions_columns %in% names(regions)))
})

test_that("check_external_regions_file names the columns which are missing", {
  tmp <- withr::local_tempdir()
  regions_file <- file.path(tmp, "petfit_regions.tsv")
  readr::write_tsv(tibble::tibble(RegionName = "Cerebellum"), regions_file)

  expect_error(check_external_regions_file(regions_file), "folder")
  expect_error(check_external_regions_file(regions_file), "ConstituentRegion")
})

# ---------------------------------------------------------------------------
# Plumbing through the automatic pipelines
# ---------------------------------------------------------------------------

test_that("petfit_auto and the pipelines expose the external file arguments", {
  expect_true(all(c("config_file", "regions_file") %in% names(formals(petfit_auto))))
  expect_true("config_file" %in% names(formals(petfit_modelling_auto)))
  expect_true("regions_file" %in% names(formals(petfit_regiondef_auto)))
  expect_true("regions_file" %in% names(formals(petfit_interactive)))
})

test_that("petfit_modelling_auto installs an external config into a new analysis folder", {
  tmp <- withr::local_tempdir()
  derivatives_dir <- file.path(tmp, "derivatives")
  dir.create(derivatives_dir, recursive = TRUE)
  config_file <- write_config_fixture(file.path(tmp, "external_config.json"))

  result <- suppressWarnings(petfit_modelling_auto(
    derivatives_dir = derivatives_dir,
    analysis_foldername = "Brand_New_Analysis",
    config_file = config_file
  ))

  installed <- file.path(derivatives_dir, "petfit", "Brand_New_Analysis",
                         "desc-petfitoptions_config.json")
  expect_true(file.exists(installed))
  expect_true(any(grepl("External config file", result$messages)))
})

test_that("petfit_modelling_auto reports a broken external config without clobbering the old one", {
  tmp <- withr::local_tempdir()
  analysis_folder <- file.path(tmp, "derivatives", "petfit", "Primary_Analysis")
  dir.create(analysis_folder, recursive = TRUE)
  existing <- write_config_fixture(
    file.path(analysis_folder, "desc-petfitoptions_config.json")
  )

  broken <- file.path(tmp, "broken.json")
  writeLines("{not valid json", broken)

  result <- petfit_modelling_auto(
    derivatives_dir = file.path(tmp, "derivatives"),
    config_file = broken
  )

  expect_false(result$success)
  expect_true(any(grepl("not valid JSON", result$messages)))
  expect_equal(
    jsonlite::fromJSON(existing)$modelling_configuration_type,
    "plasma input"
  )
})

test_that("petfit_regiondef_auto installs an external regions file before searching", {
  tmp <- withr::local_tempdir()
  derivatives_dir <- make_derivatives(tmp)
  regions_file <- write_regions_fixture(file.path(tmp, "external_regions.tsv"), "Thalamus")

  result <- suppressWarnings(petfit_regiondef_auto(
    derivatives_dir = derivatives_dir,
    regions_file = regions_file
  ))

  installed <- file.path(derivatives_dir, "petfit", "petfit_regions.tsv")

  # The file was installed, and the usual search then found it there
  expect_true(any(grepl("External regions file", result$messages)))
  expect_true(any(grepl(installed, result$messages, fixed = TRUE)))
  expect_true(any(grepl("Found petfit_regions.tsv at", result$messages)))

  # This derivatives tree holds no TACs, so the run fails and, there having been
  # no regions file before, rollback leaves the folder as it found it
  expect_false(result$success)
  expect_true(any(grepl("Removed the external regions file", result$messages)))
  expect_false(file.exists(installed))
})

test_that("petfit_regiondef_auto reports a malformed external regions file", {
  tmp <- withr::local_tempdir()
  derivatives_dir <- file.path(tmp, "derivatives")
  dir.create(derivatives_dir, recursive = TRUE)
  regions_file <- file.path(tmp, "external_regions.tsv")
  readr::write_tsv(tibble::tibble(RegionName = "Cerebellum"), regions_file)

  result <- petfit_regiondef_auto(
    derivatives_dir = derivatives_dir,
    regions_file = regions_file
  )

  expect_false(result$success)
  expect_true(any(grepl("missing required column", result$messages)))
  expect_false(file.exists(file.path(derivatives_dir, "petfit", "petfit_regions.tsv")))
})


# ---------------------------------------------------------------------------
# restore_external_file()
# ---------------------------------------------------------------------------

test_that("restore_external_file puts the replaced file back", {
  tmp <- withr::local_tempdir()
  source <- write_regions_fixture(file.path(tmp, "external_regions.tsv"), "Thalamus")
  destination <- write_regions_fixture(file.path(tmp, "petfit_regions.tsv"), "Cerebellum")

  install <- install_external_file(source, destination, label = "regions file")
  expect_equal(readr::read_tsv(destination, show_col_types = FALSE)$RegionName, "Thalamus")

  messages <- restore_external_file(install, "regions file")

  expect_true(any(grepl("Restored the previous", messages)))
  expect_equal(readr::read_tsv(destination, show_col_types = FALSE)$RegionName, "Cerebellum")
})

test_that("restore_external_file removes a file which replaced nothing", {
  tmp <- withr::local_tempdir()
  source <- write_regions_fixture(file.path(tmp, "external_regions.tsv"))
  destination <- file.path(tmp, "fresh", "petfit_regions.tsv")

  install <- install_external_file(source, destination, label = "regions file")
  expect_true(file.exists(destination))

  messages <- restore_external_file(install, "regions file")

  expect_true(any(grepl("Removed the external", messages)))
  expect_false(file.exists(destination))
  # The user's own external file is untouched
  expect_true(file.exists(source))
})

# ---------------------------------------------------------------------------
# config_type_for_pipeline()
# ---------------------------------------------------------------------------

test_that("config_type_for_pipeline maps pipeline types to config types", {
  expect_equal(config_type_for_pipeline("plasma"), "plasma input")
  expect_equal(config_type_for_pipeline("reference"), "reference tissue")
  expect_null(config_type_for_pipeline(NULL))
  expect_null(config_type_for_pipeline("nonsense"))
})

# ---------------------------------------------------------------------------
# Stronger preflight validation
# ---------------------------------------------------------------------------

test_that("check_external_config rejects a config missing required sections", {
  tmp <- withr::local_tempdir()
  config_file <- file.path(tmp, "config.json")
  jsonlite::write_json(list(modelling_configuration_type = "plasma input"),
                       config_file, auto_unbox = TRUE)

  expect_error(check_external_config(config_file), "Subsetting")
  expect_error(check_external_config(config_file), "Models")
})

test_that("check_external_config rejects a config which declares no type when one is expected", {
  tmp <- withr::local_tempdir()
  config_file <- file.path(tmp, "config.json")
  jsonlite::write_json(list(Subsetting = list(sub = ""), Models = list()),
                       config_file, auto_unbox = TRUE)

  expect_error(check_external_config(config_file, expected_type = "plasma input"),
               "does not declare modelling_configuration_type")
  # With no expectation, an undeclared type is fine
  expect_silent(check_external_config(config_file))
})

test_that("check_external_regions_file rejects a header-only file", {
  tmp <- withr::local_tempdir()
  regions_file <- file.path(tmp, "petfit_regions.tsv")
  readr::write_tsv(
    tibble::tibble(RegionName = character(0), folder = character(0),
                   description = character(0), ConstituentRegion = character(0)),
    regions_file
  )

  expect_error(check_external_regions_file(regions_file), "defines no regions")
})

test_that("check_external_regions_file rejects folders absent from the derivatives tree", {
  tmp <- withr::local_tempdir()
  deriv <- make_derivatives(tmp, folder = "freesurfer")
  regions_file <- write_regions_fixture(file.path(tmp, "petfit_regions.tsv"))

  # The fixture names "freesurfer", which exists
  expect_silent(check_external_regions_file(regions_file, derivatives_dir = deriv))

  elsewhere <- file.path(tmp, "empty_derivatives")
  dir.create(elsewhere)
  expect_error(check_external_regions_file(regions_file, derivatives_dir = elsewhere),
               "names no folder which exists")
})

# ---------------------------------------------------------------------------
# Finding 1: a mismatched config must not replace the analysis config
# ---------------------------------------------------------------------------

test_that("a config for the other pipeline is refused before it replaces anything", {
  tmp <- withr::local_tempdir()
  analysis_folder <- file.path(tmp, "derivatives", "petfit", "Primary_Analysis")
  dir.create(analysis_folder, recursive = TRUE)
  installed <- file.path(analysis_folder, "desc-petfitoptions_config.json")
  write_config_fixture(installed, "plasma input")

  external <- write_config_fixture(file.path(tmp, "reference.json"), "reference tissue")

  result <- petfit_modelling_auto(
    derivatives_dir = file.path(tmp, "derivatives"),
    pipeline_type = "plasma",
    config_file = external
  )

  expect_false(result$success)
  expect_true(any(grepl("expects plasma input modelling", result$messages)))
  # The existing config is untouched
  expect_equal(jsonlite::fromJSON(installed)$modelling_configuration_type, "plasma input")
})

test_that("a config failing after install restores the previous one", {
  tmp <- withr::local_tempdir()
  analysis_folder <- file.path(tmp, "derivatives", "petfit", "Primary_Analysis")
  dir.create(analysis_folder, recursive = TRUE)
  installed <- file.path(analysis_folder, "desc-petfitoptions_config.json")
  jsonlite::write_json(list(modelling_configuration_type = "reference tissue",
                            marker = "ORIGINAL",
                            Subsetting = list(sub = ""), Models = list()),
                       installed, auto_unbox = TRUE)

  # Valid and of the right type, but references an ancillary folder that is absent,
  # which fails before any step runs.
  external <- file.path(tmp, "external.json")
  jsonlite::write_json(list(modelling_configuration_type = "reference tissue",
                            marker = "EXTERNAL",
                            Subsetting = list(sub = ""),
                            Models = list(Model1 = list(type = "SRTM2",
                                                        k2prime_source = "ancillary_model1"))),
                       external, auto_unbox = TRUE)

  result <- petfit_modelling_auto(
    derivatives_dir = file.path(tmp, "derivatives"),
    pipeline_type = "reference",
    config_file = external
  )

  expect_false(result$success)
  expect_true(any(grepl("Restored the previous config file", result$messages)))
  expect_equal(jsonlite::fromJSON(installed)$marker, "ORIGINAL")
})

# ---------------------------------------------------------------------------
# Finding 2: a regions file that cannot work must not destroy a working one
# ---------------------------------------------------------------------------

test_that("a header-only regions file never replaces a working one", {
  tmp <- withr::local_tempdir()
  deriv <- make_derivatives(tmp)
  installed <- write_regions_fixture(
    file.path(deriv, "petfit", "petfit_regions.tsv"), "Cerebellum"
  )

  empty <- file.path(tmp, "empty_regions.tsv")
  readr::write_tsv(
    tibble::tibble(RegionName = character(0), folder = character(0),
                   description = character(0), ConstituentRegion = character(0)),
    empty
  )

  result <- petfit_regiondef_auto(derivatives_dir = deriv, regions_file = empty)

  expect_false(result$success)
  expect_true(any(grepl("defines no regions", result$messages)))
  expect_equal(readr::read_tsv(installed, show_col_types = FALSE)$RegionName, "Cerebellum")
})

test_that("a regions file naming no real folder never replaces a working one", {
  tmp <- withr::local_tempdir()
  deriv <- make_derivatives(tmp)
  installed <- write_regions_fixture(
    file.path(deriv, "petfit", "petfit_regions.tsv"), "Cerebellum"
  )

  nonmatching <- file.path(tmp, "nonmatching.tsv")
  readr::write_tsv(
    tibble::tibble(RegionName = "Thalamus", folder = "no_such_pipeline",
                   description = "seg-gtm_desc-preproc",
                   ConstituentRegion = "Left-Thalamus"),
    nonmatching
  )

  result <- petfit_regiondef_auto(derivatives_dir = deriv, regions_file = nonmatching)

  expect_false(result$success)
  expect_true(any(grepl("names no folder which exists", result$messages)))
  expect_equal(readr::read_tsv(installed, show_col_types = FALSE)$RegionName, "Cerebellum")
})

test_that("a regions file that fails downstream is rolled back", {
  tmp <- withr::local_tempdir()
  deriv <- make_derivatives(tmp)
  installed <- write_regions_fixture(
    file.path(deriv, "petfit", "petfit_regions.tsv"), "Cerebellum"
  )

  # Passes preflight (folder exists, one row) but the folder holds no TACs, so
  # mapping creation fails.
  external <- write_regions_fixture(file.path(tmp, "external.tsv"), "Thalamus")

  result <- suppressWarnings(
    petfit_regiondef_auto(derivatives_dir = deriv, regions_file = external)
  )

  expect_false(result$success)
  expect_true(any(grepl("Restored the previous regions file", result$messages)))
  expect_equal(readr::read_tsv(installed, show_col_types = FALSE)$RegionName, "Cerebellum")
})

# ---------------------------------------------------------------------------
# Finding 3: the regiondef app must honour petfit_output_foldername
# ---------------------------------------------------------------------------

test_that("region_definition_app writes regions to the requested output folder", {
  tmp <- withr::local_tempdir()
  deriv <- make_derivatives(tmp)
  external <- write_regions_fixture(file.path(tmp, "external.tsv"), "Thalamus")

  # runApp() would block forever; the startup work we care about is all done by
  # the time it is reached.
  testthat::local_mocked_bindings(
    runApp = function(...) invisible(NULL),
    .package = "shiny"
  )

  suppressWarnings(
    region_definition_app(derivatives_dir = deriv,
                          petfit_output_foldername = "petfit_custom",
                          regions_file = external)
  )

  expect_true(file.exists(file.path(deriv, "petfit_custom", "petfit_regions.tsv")))
  expect_equal(
    readr::read_tsv(file.path(deriv, "petfit_custom", "petfit_regions.tsv"),
                    show_col_types = FALSE)$RegionName,
    "Thalamus"
  )
  # and nothing was written to the default folder
  expect_false(file.exists(file.path(deriv, "petfit", "petfit_regions.tsv")))
})

# ---------------------------------------------------------------------------
# Finding 4: existing positional callers must keep working
# ---------------------------------------------------------------------------

test_that("the new arguments come last, so positional callers are unaffected", {
  # The argument lists as they stand on main, before the external file options
  expect_equal(
    head(names(formals(petfit_auto)), 10),
    c("app", "bids_dir", "derivatives_dir", "blood_dir", "petfit_output_foldername",
      "analysis_foldername", "step", "cores", "save_logs", "ancillary_analysis_folder")
  )
  expect_equal(
    head(names(formals(petfit_modelling_auto)), 10),
    c("bids_dir", "derivatives_dir", "petfit_output_foldername", "analysis_foldername",
      "blood_dir", "step", "pipeline_type", "cores", "save_logs",
      "ancillary_analysis_folder")
  )
  expect_equal(
    head(names(formals(petfit_regiondef_auto)), 4),
    c("bids_dir", "derivatives_dir", "petfit_output_foldername", "cores")
  )
  expect_equal(
    head(names(formals(region_definition_app)), 4),
    c("bids_dir", "derivatives_dir", "petfit_output_foldername", "cores")
  )
  expect_equal(
    head(names(formals(petfit_interactive)), 10),
    c("app", "bids_dir", "derivatives_dir", "blood_dir", "petfit_output_foldername",
      "analysis_foldername", "config_file", "cores", "save_logs",
      "ancillary_analysis_folder")
  )

  # cores is still the 8th positional argument of petfit_auto, not a file path
  expect_equal(which(names(formals(petfit_auto)) == "cores"), 8L)
})
