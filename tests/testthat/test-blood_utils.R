test_that("determine_blood_source identifies blood files correctly", {

  # Create temporary structure with blood data
  temp_dir <- withr::local_tempdir()
  analysis_folder <- file.path(temp_dir, "analysis")
  dir.create(analysis_folder, recursive = TRUE, showWarnings = FALSE)
  
  # Create blood data files in analysis folder
  blood_files <- c(
    "sub-01_ses-01_trc-18FFDG_blood.tsv",
    "sub-02_ses-01_trc-18FFDG_inputfunction.tsv"
  )
  
  for (blood_file in blood_files) {
    blood_path <- file.path(analysis_folder, blood_file)
    blood_data <- tibble::tibble(
      time = c(0, 1, 2, 5),
      activity = c(0, 150, 280, 220)
    )
    readr::write_tsv(blood_data, blood_path)
  }
  
  result <- determine_blood_source(analysis_folder)

  expect_type(result, "character")
  expect_equal(length(result), 1)

  # Should find blood data in analysis folder
  expect_equal(result, "analysis_folder")
})

test_that("determine_blood_source handles missing blood data", {

  temp_dir <- withr::local_tempdir()
  analysis_folder <- file.path(temp_dir, "no_blood")
  dir.create(analysis_folder, recursive = TRUE, showWarnings = FALSE)
  
  result <- determine_blood_source(analysis_folder)
  
  expect_type(result, "character") 
  expect_equal(length(result), 1)
  
  # Should return "none" when no blood data found
  expect_equal(result, "none")
  
  # Cleanup
  unlink(analysis_folder, recursive = TRUE)
})

test_that("get_blood_data_status provides correct status information", {

  temp_dir <- withr::local_tempdir()
  analysis_folder <- file.path(temp_dir, "analysis")
  dir.create(analysis_folder, recursive = TRUE, showWarnings = FALSE)
  
  # Test with processed input function data present
  blood_file <- file.path(analysis_folder, "sub-01_ses-01_trc-18FFDG_inputfunction.tsv")
  blood_data <- tibble::tibble(
    time = c(0, 1, 2),
    activity = c(0, 100, 200)
  )
  readr::write_tsv(blood_data, blood_file)
  
  result <- get_blood_data_status(analysis_folder = analysis_folder)

  expect_type(result, "list")
  expect_true("has_analysis_blood" %in% names(result))
  expect_true("has_bids_blood" %in% names(result))
  expect_true("priority_source" %in% names(result))

  # Should find processed input function data in analysis folder
  expect_true(result$has_analysis_blood)
})

test_that("get_blood_data_status handles no blood data", {
  
  temp_dir <- tempdir()
  analysis_folder <- file.path(temp_dir, "no_blood_status")
  dir.create(analysis_folder, recursive = TRUE, showWarnings = FALSE)
  
  result <- get_blood_data_status(analysis_folder = analysis_folder)
  
  expect_type(result, "list")
  expect_false(result$has_analysis_blood)
  expect_false(result$has_bids_blood)
  expect_equal(result$priority_source, "none")
  
  # Cleanup
  unlink(analysis_folder, recursive = TRUE)
})

test_that("get_blood_data_status with explicit blood_dir", {
  
  # Create explicit blood directory
  temp_dir <- tempdir()
  blood_dir <- file.path(temp_dir, "blood_data")
  dir.create(blood_dir, recursive = TRUE, showWarnings = FALSE)
  
  analysis_folder <- file.path(temp_dir, "analysis")
  dir.create(analysis_folder, showWarnings = FALSE)
  
  # Add processed input function file to blood directory
  blood_file <- file.path(blood_dir, "sub-01_inputfunction.tsv")
  blood_data <- tibble::tibble(
    time = c(0, 1, 2),
    activity = c(0, 100, 200)
  )
  readr::write_tsv(blood_data, blood_file)
  
  result <- get_blood_data_status(blood_dir = blood_dir, analysis_folder = analysis_folder)
  
  expect_true(result$has_blood_dir)
  expect_equal(result$priority_source, "blood_dir")
  
  # Cleanup
  unlink(temp_dir, recursive = TRUE)
})

test_that("get_blood_data_status ignores non-blood TSV files in explicit blood_dir", {
  
  temp_dir <- tempdir()
  blood_dir <- file.path(temp_dir, "blood_data_nonblood_tsv")
  dir.create(blood_dir, recursive = TRUE, showWarnings = FALSE)
  
  analysis_folder <- file.path(temp_dir, "analysis_nonblood_tsv")
  dir.create(analysis_folder, showWarnings = FALSE)
  
  non_blood_file <- file.path(blood_dir, "participants.tsv")
  readr::write_tsv(tibble::tibble(participant_id = "sub-01"), non_blood_file)
  
  result <- get_blood_data_status(blood_dir = blood_dir, analysis_folder = analysis_folder)
  
  expect_false(result$has_blood_dir)
  expect_equal(result$priority_source, "none")
  
  # Cleanup
  unlink(temp_dir, recursive = TRUE)
})

test_that("get_blood_data_status ignores raw blood TSV files in explicit blood_dir", {
  
  temp_dir <- tempdir()
  blood_dir <- file.path(temp_dir, "blood_data_raw_tsv")
  dir.create(blood_dir, recursive = TRUE, showWarnings = FALSE)
  
  analysis_folder <- file.path(temp_dir, "analysis_raw_tsv")
  dir.create(analysis_folder, showWarnings = FALSE)
  
  raw_blood_file <- file.path(blood_dir, "sub-01_blood.tsv")
  readr::write_tsv(
    tibble::tibble(time = c(0, 1), activity = c(0, 100)),
    raw_blood_file
  )
  
  result <- get_blood_data_status(blood_dir = blood_dir, analysis_folder = analysis_folder)
  
  expect_false(result$has_blood_dir)
  expect_equal(result$priority_source, "none")
  
  # Cleanup
  unlink(temp_dir, recursive = TRUE)
})

test_that("blooddata2inputfunction_tsv function exists and is callable", {
  
  # Test that the function exists
  expect_true(exists("blooddata2inputfunction_tsv"))
  expect_true(is.function(blooddata2inputfunction_tsv))
  
  # The function requires complex kinfitr blooddata objects,
  # so we'll just test that it exists and handles simple validation
  temp_file <- file.path(tempdir(), "test_inputfunction.tsv")
  
  # Test with NULL input (should error gracefully)
  expect_error({
    blooddata2inputfunction_tsv(NULL, temp_file)
  })
  
  # Cleanup if file was created
  if (file.exists(temp_file)) {
    file.remove(temp_file)
  }
})

test_that("blooddata2inputfunction_tsv filename handling", {
  
  # Test that filename processing logic works (without calling the full function)
  test_filenames <- c(
    "test.tsv",
    "test_file.tsv", 
    "no_extension"
  )
  
  # Test the pattern that would be used in the function
  for (filename in test_filenames) {
    # This tests the stringr::str_remove pattern used in the function
    result <- stringr::str_remove(filename, "\\.tsv$")
    
    if (grepl("\\.tsv$", filename)) {
      expect_false(grepl("\\.tsv$", result))
    } else {
      expect_equal(result, filename)
    }
  }
})

test_that("blood file pattern matching works", {
  
  # Test the patterns used in blood file detection
  test_files <- c(
    "sub-01_blood.tsv",
    "sub-01_ses-01_blood.tsv", 
    "sub-02_inputfunction.tsv",
    "sub-02_ses-01_trc-18FFDG_inputfunction.tsv",
    "not_blood_file.tsv"
  )
  
  # Test blood pattern
  blood_pattern <- "_(blood|inputfunction)\\.tsv$"
  matches <- grepl(blood_pattern, test_files)
  
  expect_true(matches[1])  # sub-01_blood.tsv
  expect_true(matches[2])  # sub-01_ses-01_blood.tsv
  expect_true(matches[3])  # sub-02_inputfunction.tsv
  expect_true(matches[4])  # sub-02_ses-01_trc-18FFDG_inputfunction.tsv
  expect_false(matches[5]) # not_blood_file.tsv
})

test_that("determine_blood_source handles BIDS directory blood data", {

  temp_dir <- withr::local_tempdir()
  bids_dir <- file.path(temp_dir, "bids")
  dir.create(bids_dir, recursive = TRUE)

  # Create blood file in BIDS directory structure
  sub_dir <- file.path(bids_dir, "sub-01", "ses-01", "pet")
  dir.create(sub_dir, recursive = TRUE)
  blood_data <- tibble::tibble(time = c(0, 1), activity = c(0, 100))
  readr::write_tsv(blood_data, file.path(sub_dir, "sub-01_ses-01_blood.tsv"))

  analysis_folder <- file.path(temp_dir, "analysis")
  dir.create(analysis_folder)

  result <- determine_blood_source(analysis_folder, bids_dir)

  expect_type(result, "character")
  expect_equal(length(result), 1)
  expect_true(result %in% c("analysis_folder", "bids_dir", "none"))
})

test_that("blood data detection patterns work correctly", {
  
  temp_dir <- tempdir()
  test_dir <- file.path(temp_dir, "pattern_test")
  dir.create(test_dir, showWarnings = FALSE)
  
  # Create files matching different patterns
  blood_files <- c(
    "sub-01_blood.tsv",
    "sub-01_ses-01_blood.tsv", 
    "sub-02_inputfunction.tsv",
    "sub-02_ses-01_trc-18FFDG_inputfunction.tsv",
    "not_blood_file.tsv"  # Should not match
  )
  
  for (file in blood_files) {
    file.create(file.path(test_dir, file))
  }
  
  result <- determine_blood_source(test_dir)
  
  expect_type(result, "character")
  expect_equal(length(result), 1)
  
  # Should find inputfunction files and return "analysis_folder"
  expect_equal(result, "analysis_folder")
  
  # Cleanup
  unlink(test_dir, recursive = TRUE)
})

# --- Merging the input functions of a measurement's runs ---------------------

# One run's interpolated input function, as blooddata_inputfunction_table()
# returns it: interpolated from zero whatever time sampling actually started,
# with the measured span recorded separately.
run_inputfunction <- function(measured_from, measured_to, value,
                              interp_points = 601) {

  table <- tibble::tibble(
    time = seq(0, measured_to, length.out = interp_points),
    whole_blood_radioactivity = value,
    plasma_radioactivity = value,
    metabolite_parent_fraction = 1,
    AIF = value
  )

  attr(table, "measured_range") <- c(measured_from, measured_to)
  table
}

test_that("a single run's input function is returned untouched", {

  only_run <- run_inputfunction(0, 5100, 100)

  expect_equal(merge_inputfunction_tables(list(only_run)), only_run)
})

test_that("merged input functions span both runs", {

  merged <- merge_inputfunction_tables(
    list(run_inputfunction(0, 5100, 100),
         run_inputfunction(5400, 10500, 50)),
    interp_points = 1000)

  expect_equal(nrow(merged), 1000)
  expect_equal(min(merged$time), 0)
  expect_equal(max(merged$time), 10500)
  expect_equal(colnames(merged), colnames(run_inputfunction(0, 100, 1)))
})

test_that("the later run's padding does not overwrite the earlier run", {

  # The second run's own table runs from zero, where it holds padding rather
  # than data. Keeping that padding would replace the first run's real values.
  merged <- merge_inputfunction_tables(
    list(run_inputfunction(0, 5100, 100),
         run_inputfunction(5400, 10500, 50)),
    interp_points = 1000)

  early <- dplyr::filter(merged, time < 5000)
  late <- dplyr::filter(merged, time > 6000)

  expect_true(all(early$AIF == 100))
  expect_true(all(late$AIF == 50))
})

test_that("the gap between runs is bridged, not left empty", {

  merged <- merge_inputfunction_tables(
    list(run_inputfunction(0, 5100, 100),
         run_inputfunction(5400, 10500, 50)),
    interp_points = 1000)

  gap <- dplyr::filter(merged, time > 5100, time < 5400)

  expect_gt(nrow(gap), 0)
  expect_false(any(is.na(gap$AIF)))
  # Linearly interpolated between the two runs, so bounded by them
  expect_true(all(gap$AIF <= 100 & gap$AIF >= 50))
})

test_that("input functions are merged in time order, whatever order they arrive", {

  forwards <- merge_inputfunction_tables(
    list(run_inputfunction(0, 5100, 100),
         run_inputfunction(5400, 10500, 50)),
    interp_points = 500)

  backwards <- merge_inputfunction_tables(
    list(run_inputfunction(5400, 10500, 50),
         run_inputfunction(0, 5100, 100)),
    interp_points = 500)

  expect_equal(forwards, backwards, ignore_attr = TRUE)
})

test_that("overlapping blood sampling windows are an error", {

  expect_error(
    merge_inputfunction_tables(
      list(run_inputfunction(0, 5100, 100),
           run_inputfunction(0, 5100, 50)),
      label = "sub-01_ses-test"),
    "sampling windows of two runs overlap")

  expect_error(
    merge_inputfunction_tables(
      list(run_inputfunction(0, 5100, 100),
           run_inputfunction(0, 5100, 50)),
      label = "sub-01_ses-test"),
    "sub-01_ses-test")
})

test_that("a run with no measured samples cannot be merged", {

  unsampled <- run_inputfunction(0, 5100, 100)
  attr(unsampled, "measured_range") <- c(NA_real_, NA_real_)

  expect_error(
    merge_inputfunction_tables(list(unsampled, run_inputfunction(5400, 10500, 50))),
    "no measured blood samples")
})

test_that("write_inputfunction_tsv writes the table and its sidecar", {

  out_dir <- withr::local_tempdir()
  target <- file.path(out_dir, "sub-01", "ses-test", "pet",
                      "sub-01_ses-test_inputfunction.tsv")

  write_inputfunction_tsv(run_inputfunction(0, 600, 100, 11), target)

  expect_true(file.exists(target))
  expect_true(file.exists(stringr::str_replace(target, "\\.tsv$", ".json")))

  written <- readr::read_tsv(target, show_col_types = FALSE)
  expect_equal(nrow(written), 11)

  sidecar <- jsonlite::fromJSON(stringr::str_replace(target, "\\.tsv$", ".json"))
  expect_equal(sidecar$time$Units, "s")
  expect_equal(sidecar$AIF$Units, "Bq")
})

test_that("a merged measurement's input function is named without a run", {

  # The output is named after the TACs file, which is what carries the merge
  # decision through to the blood filenames.
  expect_equal(
    inputfunction_output_path(
      "/analysis",
      "sub-01/ses-test/pet/sub-01_ses-test_desc-combinedregions_tacs.tsv"),
    "/analysis/sub-01/ses-test/pet/sub-01_ses-test_inputfunction.tsv")

  expect_equal(
    inputfunction_output_path(
      "/analysis",
      "sub-01/pet/sub-01_run-01_desc-combinedregions_weights.tsv"),
    "/analysis/sub-01/pet/sub-01_run-01_inputfunction.tsv")
})

# --- Guarding the join between TACs and input functions ----------------------

test_that("per-run input functions against merged TACs are an error", {

  merged_tacs <- tibble::tibble(sub = "01", ses = "test", region = "Striatum")
  per_run_blood <- tibble::tibble(sub = c("01", "01"), ses = "test",
                                  run = c("01", "02"))

  expect_error(check_blood_run_alignment(merged_tacs, per_run_blood),
               "merged across runs, but the input functions are still one per run")
  expect_error(check_blood_run_alignment(merged_tacs, per_run_blood),
               "bloodstream")
})

test_that("merged input functions against per-run TACs are an error", {

  # The quieter direction: bloodstream merges runs by default, so an analysis
  # which kept its runs apart can be handed one merged curve per measurement.
  # The join would pair it with both runs and say nothing.
  per_run_tacs <- tibble::tibble(sub = "01", ses = "test",
                                 run = c("01", "02"), region = "Striatum")
  merged_blood <- tibble::tibble(sub = "01", ses = "test")

  expect_error(check_blood_run_alignment(per_run_tacs, merged_blood),
               "keep each run as a separate measurement")
  expect_error(check_blood_run_alignment(per_run_tacs, merged_blood),
               "MergeRuns")
})

test_that("a single run against a run-less input function is fine", {

  # One run and an input function that simply omits the entity describe the
  # same acquisition, so there is nothing to mispair.
  single_run <- tibble::tibble(sub = "01", ses = "test", run = "01",
                               region = "Striatum")

  expect_true(check_blood_run_alignment(single_run,
                                        tibble::tibble(sub = "01", ses = "test")))
})

test_that("runs are counted per measurement, not across the cohort", {

  # Two subjects with one run each is not a multi-run measurement, even though
  # the cohort carries two distinct run labels between them.
  one_each <- tibble::tibble(sub = c("01", "02"), ses = "test",
                             run = c("01", "02"), region = "Striatum")

  expect_true(check_blood_run_alignment(
    one_each, tibble::tibble(sub = c("01", "02"), ses = "test")))
})

test_that("input functions and TACs which agree about runs pass", {

  # Both merged
  expect_true(check_blood_run_alignment(
    tibble::tibble(sub = "01", ses = "test"),
    tibble::tibble(sub = "01", ses = "test")))

  # Both per-run
  expect_true(check_blood_run_alignment(
    tibble::tibble(sub = "01", ses = "test", run = "01"),
    tibble::tibble(sub = "01", ses = "test", run = "01")))

  # A run column that exists but is empty is not a per-run input function
  expect_true(check_blood_run_alignment(
    tibble::tibble(sub = "01", ses = "test"),
    tibble::tibble(sub = "01", ses = "test", run = NA_character_)))
})

# --- Building input functions from raw BIDS blood data -----------------------

# A minimal raw BIDS dataset: one subject, one session, two runs of one
# injection, each with its own manual blood sampling. The second run's sample
# times continue from where the first run's stopped, which is the timeline
# merging assumes.
write_two_run_bids <- function(root, run2_start = 5400, run2_blood = TRUE,
                               time_zeros = c("11:00:16", "11:00:16")) {

  pet_dir <- file.path(root, "sub-01", "ses-test", "pet")
  dir.create(pet_dir, recursive = TRUE, showWarnings = FALSE)

  write_run <- function(run, start, blood, time_zero) {

    stem <- paste0("sub-01_ses-test_run-", run)

    file.create(file.path(pet_dir, paste0(stem, "_pet.nii.gz")))
    jsonlite::write_json(
      list(Units = "Bq/mL",
           TimeZero = time_zero, ScanStart = start, InjectionStart = 0,
           FrameTimesStart = c(start, start + 300),
           FrameDuration = c(300, 300),
           TracerName = "MC1", TracerRadionuclide = "11C",
           InjectedRadioactivity = 700000,
           InjectedRadioactivityUnits = "kBq",
           ModeOfAdministration = "bolus"),
      file.path(pet_dir, paste0(stem, "_pet.json")), auto_unbox = TRUE)

    if (!blood) {
      return(invisible(NULL))
    }

    readr::write_tsv(
      tibble::tibble(
        time = seq(start + 10, start + 600, length.out = 8),
        plasma_radioactivity = seq(30, 5, length.out = 8),
        metabolite_parent_fraction = 0.9,
        whole_blood_radioactivity = seq(25, 4, length.out = 8)),
      file.path(pet_dir, paste0(stem, "_recording-manual_blood.tsv")))

    jsonlite::write_json(
      list(PlasmaAvail = TRUE, WholeBloodAvail = TRUE, MetaboliteAvail = TRUE,
           MetaboliteRecoveryCorrectionApplied = FALSE,
           DispersionCorrected = FALSE,
           time = list(Units = "s"),
           plasma_radioactivity = list(Units = "kBq/mL"),
           metabolite_parent_fraction = list(Units = "arbitrary"),
           whole_blood_radioactivity = list(Units = "kBq/mL")),
      file.path(pet_dir, paste0(stem, "_recording-manual_blood.json")),
      auto_unbox = TRUE)
  }

  write_run("01", 0, TRUE, time_zeros[1])
  write_run("02", run2_start, run2_blood, time_zeros[2])

  invisible(root)
}

# TAC data as a report loads it: one row per region, naming the TACs file the
# input function will be named after. Merged data carries no run entity.
merged_tac_data <- function() {
  tibble::tibble(
    filename = "sub-01/ses-test/pet/sub-01_ses-test_desc-combinedregions_tacs.tsv",
    sub = "01", ses = "test", region = c("Putamen", "Cerebellum"))
}

test_that("a merged measurement gets one input function spanning its runs", {

  bids_dir <- withr::local_tempdir()
  analysis_folder <- withr::local_tempdir()
  write_two_run_bids(bids_dir)

  result <- create_analysis_inputfunctions(bids_dir, merged_tac_data(),
                                           analysis_folder)

  expect_length(result$files, 1)
  expect_equal(basename(result$files), "sub-01_ses-test_inputfunction.tsv")
  expect_match(paste(result$messages, collapse = " "),
               "pooled the blood data of more than one run")
  expect_match(paste(result$messages, collapse = " "),
               "bridged by linear interpolation")

  input <- readr::read_tsv(result$files[1], show_col_types = FALSE)

  # Spans both runs' sampling, not just the first
  expect_equal(min(input$time), 0)
  expect_equal(max(input$time), 6000)

  # The second run's real samples are there, and are not the padding its own
  # interpolation would have opened with
  late <- dplyr::filter(input, time > 5410)
  expect_true(all(late$AIF > 0))
})

test_that("blood times restarting each run are aligned by TimeZero", {

  # Both runs sample from 10 s to 600 s on their own clocks, 90 minutes apart.
  # Concatenating them as they are would overlap; the TimeZero difference is
  # what puts them end to end -- the same rule bloodstream applies.
  bids_dir <- withr::local_tempdir()
  analysis_folder <- withr::local_tempdir()
  write_two_run_bids(bids_dir, run2_start = 0,
                     time_zeros = c("11:00:00", "12:30:00"))

  result <- create_analysis_inputfunctions(bids_dir, merged_tac_data(),
                                           analysis_folder)

  expect_length(result$files, 1)

  input <- readr::read_tsv(result$files[1], show_col_types = FALSE)

  # run-02's samples land after run-01's rather than on top of them
  expect_equal(min(input$time), 0)
  expect_gt(max(input$time), 5400)
})

test_that("unmerged runs each get their own input function", {

  bids_dir <- withr::local_tempdir()
  analysis_folder <- withr::local_tempdir()
  write_two_run_bids(bids_dir)

  per_run_tacs <- tibble::tibble(
    filename = c(
      "sub-01/ses-test/pet/sub-01_ses-test_run-01_desc-combinedregions_tacs.tsv",
      "sub-01/ses-test/pet/sub-01_ses-test_run-02_desc-combinedregions_tacs.tsv"),
    sub = "01", ses = "test", run = c("01", "02"))

  result <- create_analysis_inputfunctions(bids_dir, per_run_tacs,
                                           analysis_folder)

  expect_length(result$files, 2)
  expect_setequal(basename(result$files),
                  c("sub-01_ses-test_run-01_inputfunction.tsv",
                    "sub-01_ses-test_run-02_inputfunction.tsv"))
  expect_no_match(paste(result$messages, collapse = " "), "pooled")
})

test_that("a run without blood samples of its own does not sink the merge", {

  # Sampling stopped after the first scan. The runs still share a bloodstream,
  # so the measurement gets the input function the sampled run supports -- with
  # a warning, because it covers less than the measurement does.
  bids_dir <- withr::local_tempdir()
  analysis_folder <- withr::local_tempdir()
  write_two_run_bids(bids_dir, run2_blood = FALSE)

  expect_warning(
    result <- create_analysis_inputfunctions(bids_dir, merged_tac_data(),
                                             analysis_folder),
    "no blood samples of their own")

  expect_length(result$files, 1)

  input <- readr::read_tsv(result$files[1], show_col_types = FALSE)
  expect_equal(max(input$time), 600)
})

test_that("merged TACs whose runs' blood overlaps in time are an error", {

  bids_dir <- withr::local_tempdir()
  analysis_folder <- withr::local_tempdir()
  write_two_run_bids(bids_dir, run2_start = 0)

  expect_error(
    create_analysis_inputfunctions(bids_dir, merged_tac_data(), analysis_folder),
    "sampling windows of two runs overlap")
})

test_that("a measurement with no raw blood data at all is reported", {

  bids_dir <- withr::local_tempdir()
  analysis_folder <- withr::local_tempdir()
  write_two_run_bids(bids_dir, run2_blood = FALSE)

  # Only the unsampled run is asked for, so nothing can be built for it
  only_run2 <- tibble::tibble(
    filename = "sub-01/ses-test/pet/sub-01_ses-test_run-02_desc-combinedregions_tacs.tsv",
    sub = "01", ses = "test", run = "02", region = "Putamen")

  expect_warning(
    create_analysis_inputfunctions(bids_dir, only_run2, analysis_folder),
    "No blood samples at all")
})

test_that("input functions are built for a dataset with no run entity", {

  # The common case, and the one that broke: `runs$run` is NULL where the
  # dataset has no run entity, so ordering the runs must not be attempted.
  bids_dir <- withr::local_tempdir()
  analysis_folder <- withr::local_tempdir()

  pet_dir <- file.path(bids_dir, "sub-01", "ses-test", "pet")
  dir.create(pet_dir, recursive = TRUE)
  stem <- "sub-01_ses-test"

  file.create(file.path(pet_dir, paste0(stem, "_pet.nii.gz")))
  jsonlite::write_json(
    list(Units = "Bq/mL", TimeZero = "11:00:16", ScanStart = 0,
         InjectionStart = 0, FrameTimesStart = c(0, 300),
         FrameDuration = c(300, 300), TracerName = "MC1",
         TracerRadionuclide = "11C", InjectedRadioactivity = 700000,
         InjectedRadioactivityUnits = "kBq", ModeOfAdministration = "bolus"),
    file.path(pet_dir, paste0(stem, "_pet.json")), auto_unbox = TRUE)

  readr::write_tsv(
    tibble::tibble(time = seq(10, 600, length.out = 8),
                   plasma_radioactivity = seq(30, 5, length.out = 8),
                   metabolite_parent_fraction = 0.9,
                   whole_blood_radioactivity = seq(25, 4, length.out = 8)),
    file.path(pet_dir, paste0(stem, "_recording-manual_blood.tsv")))
  jsonlite::write_json(
    list(PlasmaAvail = TRUE, WholeBloodAvail = TRUE, MetaboliteAvail = TRUE,
         MetaboliteRecoveryCorrectionApplied = FALSE,
         DispersionCorrected = FALSE, time = list(Units = "s"),
         plasma_radioactivity = list(Units = "kBq/mL"),
         metabolite_parent_fraction = list(Units = "arbitrary"),
         whole_blood_radioactivity = list(Units = "kBq/mL")),
    file.path(pet_dir, paste0(stem, "_recording-manual_blood.json")),
    auto_unbox = TRUE)

  tac_data <- tibble::tibble(
    filename = "sub-01/ses-test/pet/sub-01_ses-test_desc-combinedregions_tacs.tsv",
    sub = "01", ses = "test", region = c("Putamen", "Cerebellum"))

  result <- create_analysis_inputfunctions(bids_dir, tac_data, analysis_folder)

  expect_length(result$files, 1)
  expect_equal(basename(result$files), "sub-01_ses-test_inputfunction.tsv")
})

test_that("a mixed cohort from bloodstream is not rejected", {

  # bloodstream keeps `run` in the filename of a measurement it did not merge,
  # while petfit blanks it cohort-wide once anything merges. So run-less and
  # per-run input functions legitimately sit side by side, and the mere
  # presence of a run entity is not the thing to check.
  merged_and_single <- tibble::tibble(
    sub = c("01", "02"), ses = "test", region = "Striatum")
  blood <- tibble::tibble(sub = c("01", "02"), ses = "test",
                          run = c(NA, "01"))

  expect_true(check_blood_run_alignment(merged_and_single, blood))
})

test_that("one measurement matching several blood records is still an error", {

  expect_error(
    check_blood_run_alignment(
      tibble::tibble(sub = "01", ses = "test", region = "Striatum"),
      tibble::tibble(sub = c("01", "01"), ses = "test", run = c("01", "02"))),
    "merged across runs")
})

test_that("runs which do not carry the same curves refuse to merge", {

  # Metabolites sampled in the first block only. bd_create_input() fills the
  # second run's parent fraction with its default of 1, and pooling the pieces
  # would present that as measurement -- inflating the late input function.
  with_metabolite <- run_inputfunction(0, 5100, 100)
  attr(with_metabolite, "available_curves") <-
    c("whole_blood", "plasma", "metabolite")

  without_metabolite <- run_inputfunction(5400, 10500, 50)
  attr(without_metabolite, "available_curves") <- c("whole_blood", "plasma")

  expect_error(
    merge_inputfunction_tables(list(with_metabolite, without_metabolite),
                               label = "sub-01_ses-test"),
    "do not carry the same curves")

  # And it says where the modelling that would fill the gap can be done
  expect_error(
    merge_inputfunction_tables(list(with_metabolite, without_metabolite),
                               label = "sub-01_ses-test"),
    "bloodstream")
})

test_that("runs carrying the same curves merge as before", {

  same <- lapply(list(c(0, 5100, 100), c(5400, 10500, 50)), function(x) {
    table <- run_inputfunction(x[1], x[2], x[3])
    attr(table, "available_curves") <- c("whole_blood", "plasma", "metabolite")
    table
  })

  merged <- merge_inputfunction_tables(same, interp_points = 500)

  expect_equal(nrow(merged), 500)
  expect_equal(max(merged$time), 10500)
})
