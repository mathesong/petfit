test_that("parse_semicolon_values handles normal input", {

  # ignore_attr because the result now carries a `negate` attribute recording
  # whether the field was prefixed with "-"; asserted separately below.

  # Test basic semicolon separation
  result <- parse_semicolon_values("value1;value2;value3")
  expect_equal(result, c("value1", "value2", "value3"), ignore_attr = TRUE)

  # Test with spaces
  result <- parse_semicolon_values("value1 ; value2 ; value3")
  expect_equal(result, c("value1", "value2", "value3"), ignore_attr = TRUE)

  # Test single value
  result <- parse_semicolon_values("single_value")
  expect_equal(result, "single_value", ignore_attr = TRUE)

  # Plain input is an inclusion
  expect_false(attr(result, "negate"))
})

test_that("parse_semicolon_values handles edge cases", {
  
  # Test NULL input
  result <- parse_semicolon_values(NULL)
  expect_null(result)
  
  # Test empty string
  result <- parse_semicolon_values("")
  expect_null(result)
  
  # Test string with only semicolons
  result <- parse_semicolon_values(";;")
  expect_null(result)
  
  # Test mixed empty and valid values
  result <- parse_semicolon_values("value1;;value2;")
  expect_equal(result, c("value1", "value2"), ignore_attr = TRUE)
  
  # Test whitespace only
  result <- parse_semicolon_values("   ;   ;   ")
  expect_null(result)
})

test_that("parse_semicolon_values handles special characters", {
  
  # Test values with special characters. Note the hyphens here are interior, so
  # none of these is an exclusion.
  result <- parse_semicolon_values("sub-01;ses-02;task_rest")
  expect_equal(result, c("sub-01", "ses-02", "task_rest"), ignore_attr = TRUE)
  expect_false(attr(result, "negate"))

  # Test values with numbers
  result <- parse_semicolon_values("18FFDG;11CRACWAY;15OH2O")
  expect_equal(result, c("18FFDG", "11CRACWAY", "15OH2O"), ignore_attr = TRUE)
})

test_that("parse_semicolon_values rejects commas", {

  # Bug 3, verbatim from analysis10's config: splitting on ";" alone yields
  # "H_Striatum, H_CerebellarWM" as a single value, which matches no region and
  # used to be dropped in silence, so only the amygdala ran.
  expect_error(
    parse_semicolon_values("H_Amygdala; H_Striatum, H_CerebellarWM", field = "Regions"),
    "H_Striatum, H_CerebellarWM"
  )
  expect_error(
    parse_semicolon_values("H_Amygdala; H_Striatum, H_CerebellarWM", field = "Regions"),
    "may not contain commas"
  )

  # The message names the field and suggests the intended separator
  expect_error(
    parse_semicolon_values("H_Amygdala; H_Striatum, H_CerebellarWM", field = "Regions"),
    "^Regions:"
  )
  expect_error(
    parse_semicolon_values("a, b", field = "sub"),
    "Did you mean:    \"a; b\""
  )

  # Still rejected when the field is negated
  expect_error(parse_semicolon_values("-a, b"), "may not contain commas")
})

test_that("parse_semicolon_values reads the exclusion prefix", {

  # The "-" binds to the field, not to the first value
  result <- parse_semicolon_values("-test;retest")
  expect_equal(result, c("test", "retest"), ignore_attr = TRUE)
  expect_true(attr(result, "negate"))

  # Surrounding and interior whitespace
  result <- parse_semicolon_values("  - test ; retest  ")
  expect_equal(result, c("test", "retest"), ignore_attr = TRUE)
  expect_true(attr(result, "negate"))

  # Single exclusion
  result <- parse_semicolon_values("-pfmdd09")
  expect_equal(result, "pfmdd09", ignore_attr = TRUE)
  expect_true(attr(result, "negate"))

  # Only the leading "-" is consumed; later values keep theirs
  result <- parse_semicolon_values("-a;-b")
  expect_equal(result, c("a", "-b"), ignore_attr = TRUE)

  # A lone "-" excludes nothing and is far more likely a truncated entry
  expect_warning(result <- parse_semicolon_values("-", field = "ses"),
                 "excludes nothing")
  expect_null(result)
})

test_that("subset_combined_tacs filters data correctly", {
  
  # Create test data
  test_data <- tibble::tibble(
    sub = c("01", "02", "01", "02"),
    ses = c("01", "01", "02", "02"),
    trc = c("18FFDG", "18FFDG", "11CRACWAY", "11CRACWAY"),
    rec = c("", "", "rec1", "rec1"),
    task = c("", "rest", "", "rest"),
    run = c("", "", "1", "1"),
    desc = c("freesurfer", "freesurfer", "freesurfer", "spm"),
    region = c("cortex", "cortex", "cortex", "cortex"),
    TAC = c(100, 110, 90, 95),
    frame_start = c(0, 0, 0, 0)
  )
  
  # Test subject filtering
  subset_params <- list(sub = c("01"))
  result <- subset_combined_tacs(test_data, subset_params)
  expect_equal(unique(result$sub), "01")
  expect_equal(nrow(result), 2)
  
  # Test session filtering
  subset_params <- list(ses = c("01"))
  result <- subset_combined_tacs(test_data, subset_params)
  expect_equal(unique(result$ses), "01")
  expect_equal(nrow(result), 2)
  
  # Test tracer filtering
  subset_params <- list(trc = c("18FFDG"))
  result <- subset_combined_tacs(test_data, subset_params)
  expect_equal(unique(result$trc), "18FFDG")
  expect_equal(nrow(result), 2)
})

test_that("subset_combined_tacs handles multiple filters", {
  
  test_data <- tibble::tibble(
    sub = c("01", "02", "01", "02"),
    ses = c("01", "01", "02", "02"),
    trc = c("18FFDG", "18FFDG", "11CRACWAY", "11CRACWAY"),
    rec = c("", "", "rec1", "rec1"),
    task = c("", "rest", "", "rest"),
    run = c("", "", "1", "1"),
    desc = c("freesurfer", "freesurfer", "freesurfer", "spm"),
    region = c("cortex", "cortex", "cortex", "cortex"),
    TAC = c(100, 110, 90, 95),
    frame_start = c(0, 0, 0, 0)
  )
  
  # Test combined filtering
  subset_params <- list(
    sub = c("01"), 
    trc = c("18FFDG")
  )
  result <- subset_combined_tacs(test_data, subset_params)
  expect_equal(nrow(result), 1)
  expect_equal(result$sub, "01")
  expect_equal(result$trc, "18FFDG")
  expect_equal(result$ses, "01")
  
  # Test filtering with no matches. This used to return zero rows in silence,
  # which is the defect behind bugs 2 and 3; an included value matching nothing
  # is now an error naming the offender.
  subset_params <- list(
    sub = c("99"),
    trc = c("18FFDG")
  )
  expect_error(subset_combined_tacs(test_data, subset_params), "sub: \"99\"")
})

test_that("subset_combined_tacs excludes values from a negated field", {

  # Absent entities are NA here, as they are in real combined TACs files
  test_data <- tibble::tibble(
    sub    = c("01", "02", "03", "04"),
    ses    = c("test", "test", "retest", NA_character_),
    region = "cortex",
    TAC    = c(100, 110, 90, 95)
  )

  negated <- function(x) parse_semicolon_values(x)

  # Simple exclusion
  result <- subset_combined_tacs(test_data, list(sub = negated("-02")))
  expect_equal(result$sub, c("01", "03", "04"))

  # Several values excluded at once
  result <- subset_combined_tacs(test_data, list(sub = negated("-02;03")))
  expect_equal(result$sub, c("01", "04"))

  # Measurements with no session at all survive an exclusion: a measurement
  # without a session is indeed not ses-test. This is the mirror image of
  # inclusion, which drops NA rows.
  result <- subset_combined_tacs(test_data, list(ses = negated("-test")))
  expect_equal(result$sub, c("03", "04"))

  result <- subset_combined_tacs(test_data, list(ses = negated("test")))
  expect_equal(result$sub, c("01", "02"))

  # A negated and a plain field compose, each reading its own prefix
  result <- subset_combined_tacs(test_data,
                                 list(sub = negated("-04"), ses = negated("test")))
  expect_equal(result$sub, c("01", "02"))

  # Excluding everything is allowed, and yields nothing
  result <- subset_combined_tacs(test_data, list(sub = negated("-01;02;03;04")))
  expect_equal(nrow(result), 0)
})

test_that("subset_combined_tacs warns but proceeds on an unmatched exclusion", {

  test_data <- tibble::tibble(
    sub    = c("01", "02"),
    region = "cortex",
    TAC    = c(100, 110)
  )

  expect_warning(
    result <- subset_combined_tacs(test_data,
                                   list(sub = parse_semicolon_values("-99"))),
    "nothing was excluded"
  )
  expect_equal(nrow(result), 2)
})

test_that("subset_combined_tacs handles optional BIDS entities", {
  
  test_data <- tibble::tibble(
    sub = c("01", "02"),
    ses = c("01", "01"),
    trc = c("18FFDG", "18FFDG"),
    rec = c("", "rec1"),
    task = c("", "rest"),
    run = c("", "1"),
    desc = c("freesurfer", "spm"),
    region = c("cortex", "cortex"),
    TAC = c(100, 110),
    frame_start = c(0, 0)
  )
  
  # Test rec filtering (including empty values)
  subset_params <- list(rec = c(""))
  result <- subset_combined_tacs(test_data, subset_params)
  expect_equal(nrow(result), 1)
  expect_equal(result$rec, "")
  
  # Test task filtering
  subset_params <- list(task = c("rest"))
  result <- subset_combined_tacs(test_data, subset_params)
  expect_equal(nrow(result), 1)
  expect_equal(result$task, "rest")
  
  # Test run filtering
  subset_params <- list(run = c("1"))
  result <- subset_combined_tacs(test_data, subset_params)
  expect_equal(nrow(result), 1)
  expect_equal(result$run, "1")
  
  # Note: desc filtering not implemented in subset_combined_tacs function
  # Test that desc column exists in result but isn't filtered
  subset_params <- list()  # No filtering
  result <- subset_combined_tacs(test_data, subset_params)
  expect_equal(nrow(result), 2)  # Should return all rows
  expect_true("desc" %in% colnames(result))
})

test_that("subset_combined_tacs handles region filtering", {
  
  test_data <- tibble::tibble(
    sub = c("01", "01", "01"),
    ses = c("01", "01", "01"),
    trc = c("18FFDG", "18FFDG", "18FFDG"),
    rec = c("", "", ""),
    task = c("", "", ""),
    run = c("", "", ""),
    desc = c("freesurfer", "freesurfer", "freesurfer"),
    region = c("cortex", "hippocampus", "striatum"),
    TAC = c(100, 110, 90),
    frame_start = c(0, 0, 0)
  )
  
  # Test region filtering
  subset_params <- list(regions = c("cortex", "hippocampus"))
  result <- subset_combined_tacs(test_data, subset_params)
  expect_equal(nrow(result), 2)
  expect_true(all(result$region %in% c("cortex", "hippocampus")))
})

test_that("subset_combined_tacs handles invalid inputs", {
  
  # Test NULL input
  result <- subset_combined_tacs(NULL, list())
  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 0)
  
  # Test empty data
  empty_data <- tibble::tibble()
  result <- subset_combined_tacs(empty_data, list())
  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 0)
  
  # Test with NULL subset_params (should return original data)
  test_data <- tibble::tibble(
    sub = "01",
    ses = "01", 
    trc = "18FFDG",
    TAC = 100
  )
  result <- subset_combined_tacs(test_data, list())
  expect_equal(result, test_data)
})

test_that("create_individual_tacs_files creates correct file structure", {

  # Create test data with required columns (sub, ses, pet)
  test_data <- tibble::tibble(
    sub = c("01", "01", "02"),
    ses = c("01", "01", "01"),
    pet = c("sub-01_ses-01_trc-18FFDG", "sub-01_ses-01_trc-18FFDG", "sub-02_ses-01_trc-18FFDG"),
    region = c("cortex", "hippocampus", "cortex"),
    volume_mm3 = c(50000, 4000, 52000),
    InjectedRadioactivity = c(400000, 400000, 450000),
    bodyweight = c(70, 70, 65),
    frame_start = c(0, 0, 0),
    frame_end = c(1, 1, 1),
    frame_dur = c(1, 1, 1),
    frame_mid = c(0.5, 0.5, 0.5),
    TAC = c(100, 80, 105)
  )
  
  # Create temporary output directory
  temp_dir <- file.path(tempdir(), "test_output")
  dir.create(temp_dir, showWarnings = FALSE)
  
  result <- create_individual_tacs_files(test_data, temp_dir)
  
  expect_type(result, "list")
  expect_true("file_paths" %in% names(result))
  expect_true(length(result$file_paths) >= 2) # At least 2 unique PET files
  
  # Check that files were created
  expect_true(all(file.exists(result$file_paths)))
  
  # Check file naming convention
  expect_true(all(grepl("_desc-combinedregions_tacs\\.tsv$", basename(result$file_paths))))
  
  # Read one file and check structure
  test_file_data <- readr::read_tsv(result$file_paths[1], show_col_types = FALSE)
  expect_s3_class(test_file_data, "tbl_df")
  
  required_cols <- c("pet", "region", "volume_mm3", "InjectedRadioactivity", 
                     "bodyweight", "frame_start", "frame_end", "frame_dur", 
                     "frame_mid", "TAC")
  expect_true(all(required_cols %in% colnames(test_file_data)))
  
  # Check column order (pet should be first)
  expect_equal(colnames(test_file_data)[1], "pet")
  
  # Cleanup
  unlink(temp_dir, recursive = TRUE)
})

test_that("create_individual_tacs_files handles edge cases", {
  
  # Test with empty data
  empty_data <- tibble::tibble()
  temp_dir <- file.path(tempdir(), "test_empty")
  dir.create(temp_dir, showWarnings = FALSE)
  
  expect_warning(
    result <- create_individual_tacs_files(empty_data, temp_dir),
    "No data to create individual files"
  )
  expect_type(result, "list")
  expect_true("files_created" %in% names(result))
  expect_equal(result$files_created, 0)
  
  # Cleanup
  unlink(temp_dir, recursive = TRUE)
})

test_that("create_individual_tacs_files creates proper directory structure", {

  # Test data with nested directory structure
  test_data <- tibble::tibble(
    sub = "01",
    ses = "02", 
    pet = "sub-01_ses-02_trc-11CRACWAY_rec-test",
    region = "cortex",
    volume_mm3 = 50000,
    InjectedRadioactivity = 400000,
    bodyweight = 70,
    frame_start = 0,
    frame_end = 1,
    frame_dur = 1,
    frame_mid = 0.5,
    TAC = 100
  )
  
  temp_dir <- file.path(tempdir(), "test_structure")
  dir.create(temp_dir, showWarnings = FALSE)
  
  result <- create_individual_tacs_files(test_data, temp_dir)
  
  expect_true(length(result$file_paths) == 1)
  expect_true(file.exists(result$file_paths[1]))
  
  # Check that the file is in the correct subdirectory structure
  expected_path <- file.path(temp_dir, "sub-01", "ses-02", "pet", "sub-01_ses-02_trc-11CRACWAY_rec-test_desc-combinedregions_tacs.tsv")
  expect_equal(normalizePath(result$file_paths[1]), normalizePath(expected_path))
  
  # Cleanup
  unlink(temp_dir, recursive = TRUE)
})
test_that("data definition clears every derived output, keeping the config", {

  # Rerunning data definition changes the data every later step consumes, so
  # TACs, weights, delay fits, model results and reports are all invalidated
  # -- whatever identifiers they were written under. Only the configuration
  # survives. The previous cleanup compared filename stems against kept
  # measurements, which deleted files it did not understand and spared stale
  # ones it did.
  dir <- tempfile("petfit-cleanup-")
  pet_dir <- file.path(dir, "sub-01", "ses-test", "pet")
  dir.create(pet_dir, recursive = TRUE)
  dir.create(file.path(dir, "reports"))

  writeLines("{}", file.path(dir, "desc-petfitoptions_config.json"))
  file.create(file.path(pet_dir, "sub-01_desc-combinedregions_tacs.tsv"))
  file.create(file.path(pet_dir, "sub-01_desc-weights_weights.tsv"))
  file.create(file.path(pet_dir, "sub-01_model-2TCM_desc-model1_kinpar.tsv"))
  file.create(file.path(dir, "model-2TCM_desc-model1_kinpar.tsv"))
  file.create(file.path(dir, "reports", "model1_report.html"))
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  result <- cleanup_individual_tacs_files(dir)

  expect_equal(list.files(dir, recursive = TRUE),
               "desc-petfitoptions_config.json")
  expect_equal(result$files_removed, 5)
})

test_that("cleanup keeps input functions: they are a blood source, not stale", {

  # determine_blood_source() looks for *_inputfunction.tsv in the analysis
  # folder, and users may place such files there by hand. petfit's own are
  # derived from the BIDS blood, which a data definition does not change.
  dir <- tempfile("petfit-cleanup-if-")
  pet_dir <- file.path(dir, "sub-01", "pet")
  dir.create(pet_dir, recursive = TRUE)

  writeLines("{}", file.path(dir, "desc-petfitoptions_config.json"))
  file.create(file.path(pet_dir, "sub-01_inputfunction.tsv"))
  file.create(file.path(pet_dir, "sub-01_inputfunction.json"))
  file.create(file.path(pet_dir, "sub-01_desc-combinedregions_tacs.tsv"))
  file.create(file.path(pet_dir, "sub-01_desc-weights_weights.tsv"))
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  result <- cleanup_individual_tacs_files(dir)

  expect_setequal(list.files(dir, recursive = TRUE),
                  c("desc-petfitoptions_config.json",
                    "sub-01/pet/sub-01_inputfunction.tsv",
                    "sub-01/pet/sub-01_inputfunction.json"))
  expect_equal(result$files_removed, 2)
})

test_that("cleanup refuses a folder that is not an analysis folder", {

  # An analysis folder is recognised by the configuration defining it. A
  # mispointed path -- the petfit derivatives root, "." -- must not be
  # emptied wholesale.
  dir <- tempfile("petfit-notanalysis-")
  dir.create(dir, recursive = TRUE)
  file.create(file.path(dir, "petfit_regions_files.tsv"))
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  expect_error(cleanup_individual_tacs_files(dir),
               "does not look like an analysis folder")
  expect_true(file.exists(file.path(dir, "petfit_regions_files.tsv")))

  # An empty folder is fine: there is nothing to protect
  empty <- tempfile("petfit-empty-")
  dir.create(empty)
  on.exit(unlink(empty, recursive = TRUE), add = TRUE)
  expect_equal(cleanup_individual_tacs_files(empty)$files_removed, 0)
})

test_that("cleanup never follows a symbolic link out of the analysis folder", {

  # For an analysis folder holding a link to an external source
  # directory, list.files(recursive = TRUE) descends *through* such a link and
  # reports the files on the far side. So a cleanup that deletes what it lists
  # deletes somebody else's data and then removes the link behind it.
  skip_on_os("windows")

  root <- withr::local_tempdir()
  external <- file.path(root, "external")
  analysis <- file.path(root, "analysis")
  dir.create(file.path(external, "precious"), recursive = TRUE)
  dir.create(file.path(analysis, "sub-01", "pet"), recursive = TRUE)

  writeLines("irreplaceable", file.path(external, "precious", "source.tsv"))
  writeLines("also irreplaceable", file.path(external, "precious", "notes.txt"))
  writeLines("{}", file.path(analysis, "desc-petfitoptions_config.json"))
  file.create(file.path(analysis, "sub-01", "pet",
                        "sub-01_desc-combinedregions_tacs.tsv"))

  skip_if_not(suppressWarnings(file.symlink(
                file.path(external, "precious"),
                file.path(analysis, "linked_source"))),
              "filesystem does not support symbolic links")
  suppressWarnings(file.symlink(
    file.path(external, "precious", "source.tsv"),
    file.path(analysis, "sub-01", "pet", "linked_file.tsv")))

  result <- cleanup_individual_tacs_files(analysis)

  # nothing outside the analysis folder was touched
  expect_true(dir.exists(file.path(external, "precious")))
  expect_true(file.exists(file.path(external, "precious", "source.tsv")))
  expect_true(file.exists(file.path(external, "precious", "notes.txt")))
  expect_equal(readLines(file.path(external, "precious", "source.tsv")),
               "irreplaceable")

  # the links themselves are gone, along with the derived file
  expect_false(petfit:::petfit_link_state(file.path(analysis, "linked_source")))
  expect_equal(list.files(analysis, recursive = TRUE),
               "desc-petfitoptions_config.json")

  # and the summary says what happened to them
  expect_match(result$summary, "symbolic links")
})

test_that("a directory holding only hidden files is not treated as empty", {

  # list.files() hides dotfiles by default, so such a directory reads as empty
  # and a recursive unlink would take the hidden files with it.
  dir <- withr::local_tempdir()
  keepdir <- file.path(dir, "sub-01", "pet")
  dir.create(keepdir, recursive = TRUE)
  writeLines("{}", file.path(dir, "desc-petfitoptions_config.json"))
  writeLines("", file.path(keepdir, ".gitkeep"))

  cleanup_individual_tacs_files(dir)

  # the dotfile is a derived-folder entry like any other: removed as a file,
  # not silently destroyed by a recursive delete of a "empty" directory
  expect_false(file.exists(file.path(keepdir, ".gitkeep")))
  expect_false(dir.exists(keepdir))
})

test_that("a symlinked input function is kept, like a real one", {

  skip_on_os("windows")
  root <- withr::local_tempdir()
  external <- file.path(root, "blood")
  analysis <- file.path(root, "analysis")
  dir.create(external, recursive = TRUE)
  dir.create(file.path(analysis, "sub-01", "pet"), recursive = TRUE)

  writeLines("time\tAIF\n0\t0", file.path(external, "sub-01_inputfunction.tsv"))
  writeLines("{}", file.path(analysis, "desc-petfitoptions_config.json"))

  skip_if_not(suppressWarnings(file.symlink(
                file.path(external, "sub-01_inputfunction.tsv"),
                file.path(analysis, "sub-01", "pet",
                          "sub-01_inputfunction.tsv"))),
              "filesystem does not support symbolic links")

  cleanup_individual_tacs_files(analysis)

  expect_true(petfit:::petfit_link_state(
    file.path(analysis, "sub-01", "pet", "sub-01_inputfunction.tsv")))
  expect_true(file.exists(file.path(external, "sub-01_inputfunction.tsv")))
})

test_that("the tree scan refuses anything resolving outside the folder", {

  # A directory that leads out of the analysis folder but which fs does not
  # call a link -- a reparse point, a mount, something on a filesystem fs
  # cannot describe -- must stop the cleanup rather than be guessed at. This
  # exercises the containment test itself, on every platform.
  root <- withr::local_tempdir()
  inside <- file.path(root, "sub-01")
  dir.create(inside)
  real_root <- petfit:::petfit_real_path(root)

  expect_true(fs::path_has_parent(petfit:::petfit_real_path(inside), real_root))

  outside <- withr::local_tempdir()
  expect_false(fs::path_has_parent(petfit:::petfit_real_path(outside), real_root))

  # a sibling whose name merely starts the same way is not "inside": the test
  # compares path components, not string prefixes
  sibling <- paste0(root, "-other")
  dir.create(sibling)
  withr::defer(unlink(sibling, recursive = TRUE))
  expect_false(fs::path_has_parent(petfit:::petfit_real_path(sibling), real_root))
})

test_that("an unresolvable path stops the cleanup before anything is removed", {

  root <- withr::local_tempdir()
  expect_error(petfit:::petfit_real_path(file.path(root, "does-not-exist")),
               "could not resolve")
})

test_that("petfit_is_symlink answers FALSE for real files and missing paths", {

  # Windows returns "" for every path, and an unreadable path gives NA. Both
  # must read as "not a link": a path is only treated as one when known to be.
  root <- withr::local_tempdir()
  real <- file.path(root, "real.tsv")
  writeLines("x", real)

  expect_false(petfit:::petfit_link_state(real))
  expect_false(petfit:::petfit_link_state(root))
  expect_false(petfit:::petfit_link_state(file.path(root, "does-not-exist")))
})

test_that("Windows junctions are removed without traversing their targets", {

  # A dangerous Windows case, and the one file.symlink() cannot cover: a
  # true Windows symbolic link may need Developer Mode or extra privileges,
  # whereas mklink /J normally does not. A junction presents to
  # directory-walking code as an ordinary directory while redirecting
  # traversal, which is exactly what must not happen here.
  skip_if_not(.Platform$OS.type == "windows", "Windows-only")

  root <- withr::local_tempdir()
  analysis <- file.path(root, "analysis")
  external <- file.path(root, "external")
  junction <- file.path(analysis, "linked-source")
  dir.create(analysis)
  dir.create(external)

  writeLines("{}", file.path(analysis, "desc-petfitoptions_config.json"))
  writeLines("irreplaceable", file.path(external, "source.tsv"))
  writeLines("derived", file.path(analysis, "derived.tsv"))

  # shell(), not system(): "On Windows, system does not use a shell and there
  # is a separate function shell which passes command lines to a shell"
  # (?system). mklink is a cmd.exe builtin with no executable of its own, so
  # system() would look for mklink.exe and fail before testing anything.
  command <- sprintf('mklink /J "%s" "%s"',
                     normalizePath(junction, winslash = "\\", mustWork = FALSE),
                     normalizePath(external, winslash = "\\", mustWork = TRUE))
  status <- shell(command, intern = FALSE)
  # Not skipped on failure: junction creation does not normally need the
  # symbolic-link privilege, so a failure here is a CI configuration problem
  # that should be visible rather than quietly passed over.
  expect_equal(status, 0)

  # If fs cannot see a junction as a link, the safety of everything below
  # rests on nothing. Fail loudly rather than fall back to traversal.
  expect_true(fs::is_link(junction))

  cleanup_individual_tacs_files(analysis)

  expect_true(file.exists(file.path(external, "source.tsv")))
  expect_equal(readLines(file.path(external, "source.tsv")), "irreplaceable")
  expect_true(dir.exists(external))
  expect_false(fs::link_exists(junction))
  expect_false(file.exists(file.path(analysis, "derived.tsv")))
  expect_true(file.exists(file.path(analysis, "desc-petfitoptions_config.json")))
})

test_that("a link inside the analysis folder is still not followed", {

  # The policy is "never follow a link", not "never leave the folder". A link
  # pointing at a sibling directory within the analysis is removed as a link,
  # and the directory it names is cleared on its own account, once.
  skip_on_os("windows")

  root <- withr::local_tempdir()
  target <- file.path(root, "sub-01", "pet")
  dir.create(target, recursive = TRUE)
  writeLines("{}", file.path(root, "desc-petfitoptions_config.json"))
  file.create(file.path(target, "sub-01_desc-weights_weights.tsv"))

  skip_if_not(suppressWarnings(file.symlink(target, file.path(root, "shortcut"))),
              "filesystem does not support symbolic links")

  tree <- petfit:::petfit_list_tree(root)
  expect_equal(basename(tree$links), "shortcut")
  # the weights file is found once, by its real path, not twice via the link
  expect_equal(sum(basename(tree$files) == "sub-01_desc-weights_weights.tsv"), 1L)

  cleanup_individual_tacs_files(root)
  expect_equal(list.files(root, recursive = TRUE),
               "desc-petfitoptions_config.json")
})

test_that("a broken link is classified as a link and never resolved", {

  skip_on_os("windows")
  root <- withr::local_tempdir()
  writeLines("{}", file.path(root, "desc-petfitoptions_config.json"))
  skip_if_not(suppressWarnings(file.symlink(file.path(root, "nowhere"),
                                            file.path(root, "dangling"))),
              "filesystem does not support symbolic links")

  tree <- petfit:::petfit_list_tree(root)
  expect_equal(basename(tree$links), "dangling")
  expect_length(tree$files, 1)

  expect_no_error(cleanup_individual_tacs_files(root))
  expect_false(fs::link_exists(file.path(root, "dangling")))
})

test_that("nothing is removed when a path cannot be classified", {

  # Enumeration completes before any deletion, so a folder containing
  # something unresolvable is left exactly as it was found.
  root <- withr::local_tempdir()
  writeLines("{}", file.path(root, "desc-petfitoptions_config.json"))
  file.create(file.path(root, "derived.tsv"))

  local_mocked_bindings(
    petfit_list_tree = function(dir) stop("could not resolve path", call. = FALSE))

  expect_error(cleanup_individual_tacs_files(root), "could not resolve")
  expect_true(file.exists(file.path(root, "derived.tsv")))
})

test_that("a link that will not delete is an error, not a silent undercount", {

  skip_on_os("windows")
  root <- withr::local_tempdir()
  writeLines("{}", file.path(root, "desc-petfitoptions_config.json"))
  writeLines("x", file.path(root, "target.tsv"))
  skip_if_not(suppressWarnings(file.symlink(file.path(root, "target.tsv"),
                                            file.path(root, "alias.tsv"))),
              "filesystem does not support symbolic links")

  # a link_delete() that reports success while leaving the link behind must
  # not be counted as a removal
  local_mocked_bindings(.package = "fs", link_delete = function(path) invisible(path))

  expect_error(cleanup_individual_tacs_files(root), "still there")
})

test_that("a configless folder of hidden files is refused, not emptied", {

  # The guard and the walker have to agree on what counts as an entry. The
  # walker enumerates hidden files and removes them, so a guard blind to them
  # reads a directory holding only a .env as empty, waves it through as having
  # nothing to protect, and the walker then deletes precisely those files.
  dir <- withr::local_tempdir()
  writeLines("IRREPLACEABLE", file.path(dir, ".precious"))
  writeLines("secrets", file.path(dir, ".env"))

  expect_error(cleanup_individual_tacs_files(dir),
               "does not look like an analysis folder")

  expect_true(file.exists(file.path(dir, ".precious")))
  expect_equal(readLines(file.path(dir, ".precious")), "IRREPLACEABLE")
  expect_true(file.exists(file.path(dir, ".env")))
  expect_equal(readLines(file.path(dir, ".env")), "secrets")

  # a hidden entry nested below the top level is protected by the same guard
  nested <- withr::local_tempdir()
  dir.create(file.path(nested, "sub-01"))
  writeLines("IRREPLACEABLE", file.path(nested, "sub-01", ".precious"))
  expect_error(cleanup_individual_tacs_files(nested),
               "does not look like an analysis folder")
  expect_true(file.exists(file.path(nested, "sub-01", ".precious")))
})

test_that("a genuinely empty folder is still allowed through", {

  # The guard protects files, not directories: an empty analysis folder has
  # nothing to lose and is a normal first-run state.
  empty <- withr::local_tempdir()
  result <- cleanup_individual_tacs_files(empty)
  expect_equal(result$files_removed, 0)
  expect_equal(result$dirs_removed, 0)
})
