# Combined TACs data for a measurement acquired as two runs of one injection.
# Two runs, two regions, two frames per run, with the second run's frame times
# continuing where the first run's stopped -- which is what merging assumes.
two_run_tacs <- function(run2_start = 5400,
                         injected = c(700000, 700000),
                         volumes = c(1000, 1000)) {

  make_run <- function(run, start, dose, volume) {
    tidyr::expand_grid(
      region = c("Cerebellum", "Striatum"),
      frame_start = c(start, start + 300)
    ) %>%
      dplyr::mutate(
        sub = "01",
        ses = "test",
        task = NA_character_,
        trc = NA_character_,
        rec = NA_character_,
        run = run,
        segmentation = "petprep: seg-gtm",
        InjectedRadioactivity = dose,
        bodyweight = 70,
        volume_mm3 = volume,
        frame_end = frame_start + 300,
        frame_dur = 300,
        frame_mid = frame_start + 150,
        seg_meanTAC = 5,
        TAC = 10
      )
  }

  dplyr::bind_rows(
    make_run("01", 0, injected[1], volumes[1]),
    make_run("02", run2_start, injected[2], volumes[2])
  )
}

test_that("merging pools the runs of a measurement into one", {

  tacs <- two_run_tacs()

  result <- merge_tacs_runs(tacs)

  expect_true(result$merged)

  # Every row is kept: merging is a change of identity, not of data
  expect_equal(nrow(result$data), nrow(tacs))
  expect_true(all(is.na(result$data$run)))
  expect_match(paste(result$messages, collapse = " "),
               "Merged 2 runs into 1 measurement")

  # The frames of both runs now belong to one measurement, in time order
  frames <- result$data %>%
    dplyr::filter(region == "Cerebellum") %>%
    dplyr::pull(frame_start)
  expect_equal(frames, c(0, 300, 5400, 5700))
})

test_that("merged measurements get identifiers with no run", {

  merged <- merge_tacs_runs(two_run_tacs())$data

  identified <- reconstruct_pet_column(
    merged, c("sub", "ses", "task", "trc", "rec", "run"))

  expect_equal(unique(identified$pet), "sub-01_ses-test")
})

test_that("a dataset with nothing to merge is left exactly as it is", {

  # Every measurement carries run-01 and nothing else. Dropping that entity
  # would rename every output of a dataset the merge did not touch, and the
  # consistency it would be dropped for has nothing to be consistent with.
  single <- two_run_tacs() %>% dplyr::filter(run == "01")

  result <- merge_tacs_runs(single)

  expect_false(result$merged)
  expect_equal(result$data, single)
  expect_equal(unique(result$data$run), "01")
  expect_match(paste(result$messages, collapse = " "),
               "nothing was merged and the run entity has been left as it is")

  identified <- reconstruct_pet_column(
    result$data, c("sub", "ses", "task", "trc", "rec", "run"))
  expect_equal(unique(identified$pet), "sub-01_ses-test_run-01")
})

test_that("a single-run measurement keeps its run in a merged cohort", {

  # sub-01 has two runs, sub-02 only one. Only sub-01 loses the entity: a
  # measurement's identity is built from its own entities, so sub-02's outputs
  # must not be renamed because of what another subject's data looked like.
  # This is also bloodstream's rule, so the two tools' filenames agree.
  mixed <- dplyr::bind_rows(
    two_run_tacs(),
    two_run_tacs() %>% dplyr::filter(run == "01") %>% dplyr::mutate(sub = "02")
  )

  result <- merge_tacs_runs(mixed)

  identified <- reconstruct_pet_column(
    result$data, c("sub", "ses", "task", "trc", "rec", "run"))

  expect_equal(unique(identified$pet[identified$sub == "01"]),
               "sub-01_ses-test")
  expect_equal(unique(identified$pet[identified$sub == "02"]),
               "sub-02_ses-test_run-01")
})

test_that("overlapping run frames are an error, not a silent merge", {

  # The second run's frame times restart from zero, so the runs are not on a
  # shared timeline and pooling them would fold the measurement back on itself.
  overlapping <- two_run_tacs(run2_start = 0)

  expect_error(merge_tacs_runs(overlapping), "overlap in time")
  expect_error(merge_tacs_runs(overlapping), "sub-01_ses-test")
  expect_error(merge_tacs_runs(overlapping), "switch run merging off")
})

test_that("a run starting inside the previous run is an error", {

  # Not a restart from zero, but still an overlap: run-02's first frame begins
  # before run-01's last frame ends.
  expect_error(merge_tacs_runs(two_run_tacs(run2_start = 400)),
               "overlap in time")
})

test_that("runs disagreeing about the dose warn and keep the earliest value", {

  differing <- two_run_tacs(injected = c(700000, 350000))

  expect_warning(result <- merge_tacs_runs(differing),
                 "disagree about values a single injection fixes")

  expect_equal(unique(result$data$InjectedRadioactivity), 700000)
})

test_that("runs disagreeing about region volume warn and keep the earliest", {

  differing <- two_run_tacs(volumes = c(1000, 1200))

  expect_warning(result <- merge_tacs_runs(differing),
                 "different volumes in different runs|different volume in different runs")

  expect_equal(unique(result$data$volume_mm3), 1000)
})

test_that("the earliest run is read from the frame times, not the run label", {

  # Labels are only conventionally ordered. Here the label that sorts first is
  # the *later* scan, so a label-based rule would keep the wrong dose.
  relabelled <- two_run_tacs(injected = c(700000, 350000)) %>%
    dplyr::mutate(run = dplyr::if_else(run == "01", "pm", "am"))

  suppressWarnings(result <- merge_tacs_runs(relabelled))

  expect_equal(unique(result$data$InjectedRadioactivity), 700000)
})

test_that("data with no run column is left alone", {

  no_run <- two_run_tacs() %>%
    dplyr::filter(run == "01") %>%
    dplyr::select(-run)

  result <- merge_tacs_runs(no_run)

  expect_equal(result$data, no_run)
  expect_match(result$messages, "nothing to merge")
})

test_that("empty data is left alone", {

  empty <- two_run_tacs()[0, ]

  result <- merge_tacs_runs(empty)

  expect_equal(nrow(result$data), 0)
})

test_that("runs of different sessions are not merged with each other", {

  # Two sessions, each with two runs. Merging must join the runs within each
  # session and leave the sessions apart.
  two_sessions <- dplyr::bind_rows(
    two_run_tacs(),
    two_run_tacs() %>% dplyr::mutate(ses = "retest")
  )

  merged <- merge_tacs_runs(two_sessions)$data

  identified <- reconstruct_pet_column(
    merged, c("sub", "ses", "task", "trc", "rec", "run"))

  expect_setequal(unique(identified$pet),
                  c("sub-01_ses-test", "sub-01_ses-retest"))
})

test_that("merging is skipped when it is switched off", {

  petfit_dir <- withr::local_tempdir()

  # Exercised through the sidecar, which is where the decision is recorded: an
  # empty run column otherwise looks the same as a dataset with no runs.
  create_combined_tacs_json_description(
    participants_metadata = NULL,
    injected_radioactivity_units = "kBq",
    original_tac_units = "kBq",
    output_dir = petfit_dir,
    merged_runs = FALSE
  )

  sidecar <- jsonlite::fromJSON(
    file.path(petfit_dir, "desc-combinedregions_tacs.json"))

  expect_false(sidecar$MergedRuns)
  expect_equal(sidecar$run$Description, "Run identifier")
})

test_that("the sidecar records that runs were merged", {

  petfit_dir <- withr::local_tempdir()

  create_combined_tacs_json_description(
    participants_metadata = NULL,
    injected_radioactivity_units = "kBq",
    original_tac_units = "kBq",
    output_dir = petfit_dir,
    merged_runs = TRUE
  )

  sidecar <- jsonlite::fromJSON(
    file.path(petfit_dir, "desc-combinedregions_tacs.json"))

  expect_true(sidecar$MergedRuns)
  expect_match(sidecar$run$Description, "merged")
})

test_that("subsetting by run explains itself once the runs have been merged", {

  merged <- merge_tacs_runs(two_run_tacs())$data

  expect_error(
    validate_subset_params(merged, list(run = "01")),
    "merged in the region definition step")
})

# --- End to end through the region definition pipeline -----------------------

# A minimal derivatives tree: one subject, one session, two runs of one
# injection, one segmentation, two constituent regions. The second run's frame
# times continue from where the first run's stopped.
write_two_run_derivatives <- function(root, run2_start = 5400) {

  pipeline_dir <- file.path(root, "petprep")
  pet_dir <- file.path(pipeline_dir, "sub-01", "ses-test", "pet")
  anat_dir <- file.path(pipeline_dir, "sub-01", "ses-test", "anat")
  purrr::walk(c(pet_dir, anat_dir), dir.create, recursive = TRUE,
              showWarnings = FALSE)

  readr::write_tsv(
    tibble::tibble(name = c("Left-Putamen", "Right-Putamen"),
                   `volume-mm3` = c(4000, 4200)),
    file.path(anat_dir, "sub-01_ses-test_desc-preproc_seg-gtm_morph.tsv"))

  write_run <- function(run, start, values) {
    tacs <- tibble::tibble(
      frame_start = c(start, start + 300),
      frame_end = c(start + 300, start + 600),
      `Left-Putamen` = values,
      `Right-Putamen` = values * 1.1
    )
    stem <- paste0("sub-01_ses-test_run-", run, "_desc-preproc_seg-gtm_tacs")
    readr::write_tsv(tacs, file.path(pet_dir, paste0(stem, ".tsv")))
    jsonlite::write_json(
      list(InjectedRadioactivity = 700000,
           InjectedRadioactivityUnits = "kBq",
           Units = "kBq/mL"),
      file.path(pet_dir, paste0(stem, ".json")),
      auto_unbox = TRUE)
  }

  write_run("01", 0, c(100, 90))
  write_run("02", run2_start, c(40, 35))

  petfit_dir <- file.path(root, "petfit")
  dir.create(petfit_dir, recursive = TRUE, showWarnings = FALSE)
  readr::write_tsv(
    tibble::tibble(
      RegionName = c("Putamen", "Putamen"),
      folder = "petprep",
      description = "seg-gtm_desc-preproc",
      ConstituentRegion = c("Left-Putamen", "Right-Putamen")),
    file.path(petfit_dir, "petfit_regions.tsv"))

  petfit_dir
}

# A raw BIDS tree matching write_two_run_derivatives(), whose _pet.json
# sidecars carry the TimeZero that places the runs on a common clock.
write_two_run_raw_bids <- function(root, time_zeros = c("11:00:00", "12:30:00")) {

  pet_dir <- file.path(root, "sub-01", "ses-test", "pet")
  dir.create(pet_dir, recursive = TRUE, showWarnings = FALSE)

  purrr::walk2(c("01", "02"), time_zeros, function(run, time_zero) {
    stem <- paste0("sub-01_ses-test_run-", run)
    file.create(file.path(pet_dir, paste0(stem, "_pet.nii.gz")))
    jsonlite::write_json(
      list(Units = "Bq/mL", TimeZero = time_zero, ScanStart = 0,
           InjectionStart = 0,
           FrameTimesStart = c(0, 300), FrameDuration = c(300, 300),
           TracerName = "MC1", TracerRadionuclide = "11C",
           InjectedRadioactivity = 700000,
           InjectedRadioactivityUnits = "kBq",
           ModeOfAdministration = "bolus"),
      file.path(pet_dir, paste0(stem, "_pet.json")), auto_unbox = TRUE)
  })

  invisible(root)
}

test_that("runs whose frame times each restart from zero are aligned by TimeZero", {

  # The case that cannot be merged by concatenation: both runs' frames start at
  # 0. Their TimeZero clock times are 90 minutes apart, which is what puts them
  # end to end. This is the same rule bloodstream applies to the blood samples.
  derivatives <- withr::local_tempdir()
  bids_dir <- withr::local_tempdir()
  petfit_dir <- write_two_run_derivatives(derivatives, run2_start = 0)
  write_two_run_raw_bids(bids_dir)

  result <- suppressMessages(
    petfit_regiondef_auto(bids_dir = bids_dir, derivatives_dir = derivatives))

  expect_true(result$success, info = paste(result$messages, collapse = "\n"))

  combined <- readr::read_tsv(
    file.path(petfit_dir, "desc-combinedregions_tacs.tsv"),
    show_col_types = FALSE)

  expect_equal(sort(unique(combined$frame_start)), c(0, 300, 5400, 5700))
  expect_equal(unique(combined$pet), "sub-01_ses-test")

  # The alignment column is scaffolding, and stays out of the output
  expect_false("time_zero" %in% colnames(combined))
})

test_that("runs sharing a TimeZero are not shifted", {

  # Frames already on one clock, TimeZero identical: merging must leave the
  # times exactly as the source files recorded them.
  derivatives <- withr::local_tempdir()
  bids_dir <- withr::local_tempdir()
  petfit_dir <- write_two_run_derivatives(derivatives, run2_start = 5400)
  write_two_run_raw_bids(bids_dir, time_zeros = c("11:00:00", "11:00:00"))

  suppressMessages(
    petfit_regiondef_auto(bids_dir = bids_dir, derivatives_dir = derivatives))

  combined <- readr::read_tsv(
    file.path(petfit_dir, "desc-combinedregions_tacs.tsv"),
    show_col_types = FALSE)

  expect_equal(sort(unique(combined$frame_start)), c(0, 300, 5400, 5700))
})

test_that("without TimeZero, overlapping frames say to supply bids_dir", {

  # Derivatives only: the pipelines' _tacs.json sidecars carry no TimeZero, so
  # there is no clock to align by and the frame times cannot be rescued.
  derivatives <- withr::local_tempdir()
  write_two_run_derivatives(derivatives, run2_start = 0)

  result <- suppressMessages(petfit_regiondef_auto(derivatives_dir = derivatives))

  expect_false(result$success)
  expect_match(paste(result$messages, collapse = " "), "overlap in time")
  expect_match(paste(result$messages, collapse = " "), "bids_dir")
})

test_that("region definition merges runs end to end by default", {

  derivatives <- withr::local_tempdir()
  petfit_dir <- write_two_run_derivatives(derivatives)

  result <- suppressMessages(petfit_regiondef_auto(derivatives_dir = derivatives))

  expect_true(result$success)
  expect_match(paste(result$messages, collapse = " "), "Run merging is on")

  combined <- readr::read_tsv(
    file.path(petfit_dir, "desc-combinedregions_tacs.tsv"),
    show_col_types = FALSE)

  # One measurement spanning both runs, identified without a run
  expect_equal(unique(combined$pet), "sub-01_ses-test")
  expect_true(all(is.na(combined$run)))

  # Both runs' frames are present, in time order
  expect_equal(sort(unique(combined$frame_start)), c(0, 300, 5400, 5700))

  sidecar <- jsonlite::fromJSON(
    file.path(petfit_dir, "desc-combinedregions_tacs.json"))
  expect_true(sidecar$MergedRuns)
})

test_that("a dataset with nothing to merge is not recorded as merged", {

  # Asking to merge a dataset with one run per measurement changes nothing, and
  # the sidecar has to say so -- otherwise a reader is told the run column was
  # emptied by a merge when the dataset simply has nothing to merge.
  derivatives <- withr::local_tempdir()
  petfit_dir <- write_two_run_derivatives(derivatives)
  file.remove(list.files(derivatives, pattern = "_run-02_", recursive = TRUE,
                         full.names = TRUE))

  suppressMessages(petfit_regiondef_auto(derivatives_dir = derivatives))

  sidecar <- jsonlite::fromJSON(
    file.path(petfit_dir, "desc-combinedregions_tacs.json"))
  expect_false(sidecar$MergedRuns)

  combined <- readr::read_tsv(
    file.path(petfit_dir, "desc-combinedregions_tacs.tsv"),
    show_col_types = FALSE)
  expect_equal(unique(combined$pet), "sub-01_ses-test_run-01")
})

test_that("region definition keeps runs apart when merging is switched off", {

  derivatives <- withr::local_tempdir()
  petfit_dir <- write_two_run_derivatives(derivatives)

  result <- suppressMessages(
    petfit_regiondef_auto(derivatives_dir = derivatives, merge_runs = FALSE))

  expect_true(result$success)
  expect_match(paste(result$messages, collapse = " "), "Run merging is off")

  combined <- readr::read_tsv(
    file.path(petfit_dir, "desc-combinedregions_tacs.tsv"),
    show_col_types = FALSE)

  expect_setequal(unique(combined$pet),
                  c("sub-01_ses-test_run-01", "sub-01_ses-test_run-02"))
  expect_setequal(unique(combined$run), c("01", "02"))

  sidecar <- jsonlite::fromJSON(
    file.path(petfit_dir, "desc-combinedregions_tacs.json"))
  expect_false(sidecar$MergedRuns)
})

test_that("region definition refuses to merge runs whose frames overlap", {

  derivatives <- withr::local_tempdir()
  write_two_run_derivatives(derivatives, run2_start = 0)

  result <- suppressMessages(petfit_regiondef_auto(derivatives_dir = derivatives))

  expect_false(result$success)
  expect_match(paste(result$messages, collapse = " "), "overlap in time")
})

test_that("merged measurements produce one TACs file with no run", {

  derivatives <- withr::local_tempdir()
  petfit_dir <- write_two_run_derivatives(derivatives)

  suppressMessages(petfit_regiondef_auto(derivatives_dir = derivatives))

  combined <- readr::read_tsv(
    file.path(petfit_dir, "desc-combinedregions_tacs.tsv"),
    show_col_types = FALSE)

  analysis_folder <- file.path(petfit_dir, "Primary_Analysis")
  dir.create(analysis_folder, recursive = TRUE)

  file_result <- suppressMessages(
    create_individual_tacs_files(combined, analysis_folder))

  expect_equal(file_result$files_created, 1L)
  expect_equal(basename(file_result$file_paths),
               "sub-01_ses-test_desc-combinedregions_tacs.tsv")

  # The input function that would be built for it is named to match, so that
  # blood and TACs join on the same entities
  expect_equal(
    basename(inputfunction_output_path(
      analysis_folder,
      "sub-01/ses-test/pet/sub-01_ses-test_desc-combinedregions_tacs.tsv")),
    "sub-01_ses-test_inputfunction.tsv")
})

# --- Whether the option is worth showing ------------------------------------

test_that("a dataset with several runs per measurement is detected", {

  derivatives <- withr::local_tempdir()
  write_two_run_derivatives(derivatives)

  expect_true(dataset_has_multiple_runs(derivatives))
})

test_that("a dataset labelled run-01 throughout has nothing to merge", {

  # The run entity is present, but no measurement has more than one run, so
  # merging would do nothing and the option should stay out of the way.
  derivatives <- withr::local_tempdir()
  write_two_run_derivatives(derivatives)

  run2 <- list.files(derivatives, pattern = "_run-02_", recursive = TRUE,
                     full.names = TRUE)
  file.remove(run2)

  expect_false(dataset_has_multiple_runs(derivatives))
})

test_that("a dataset with no runs at all has nothing to merge", {

  derivatives <- withr::local_tempdir()
  pet_dir <- file.path(derivatives, "petprep", "sub-01", "ses-test", "pet")
  dir.create(pet_dir, recursive = TRUE)
  file.create(file.path(pet_dir, "sub-01_ses-test_desc-preproc_seg-gtm_tacs.tsv"))

  expect_false(dataset_has_multiple_runs(derivatives))
})

test_that("the same measurement under two pipelines is not read as two runs", {

  # Two pipelines each holding run-01 of one measurement. Keying on the
  # filename alone would collide them and report a multi-run dataset.
  derivatives <- withr::local_tempdir()
  for (pipeline in c("petprep", "petprep_variant")) {
    pet_dir <- file.path(derivatives, pipeline, "sub-01", "ses-test", "pet")
    dir.create(pet_dir, recursive = TRUE)
    file.create(file.path(
      pet_dir, "sub-01_ses-test_run-01_desc-preproc_seg-gtm_tacs.tsv"))
  }

  expect_false(dataset_has_multiple_runs(derivatives))
})

test_that("combined TACs files are not mistaken for source TACs", {

  derivatives <- withr::local_tempdir()
  petfit_dir <- file.path(derivatives, "petfit")
  dir.create(petfit_dir, recursive = TRUE)
  file.create(file.path(petfit_dir, "desc-combinedregions_tacs.tsv"))

  expect_false(dataset_has_multiple_runs(derivatives))
})

test_that("a missing derivatives folder is not an error", {

  expect_false(dataset_has_multiple_runs(file.path(tempdir(), "nowhere")))
  expect_false(dataset_has_multiple_runs(NULL))
})

# --- Ordering and metadata reconciliation -----------------------------------

test_that("numeric run labels are ordered numerically, not as strings", {

  # BIDS run indices need not be zero-padded, and as strings "10" sorts before
  # "2". The offsets unwrap midnight in this order, so getting it wrong reads
  # an hour's gap as nearly a day's and shifts the frames by 23 hours.
  expect_equal(c("2", "10")[run_label_order(c("2", "10"))], c("2", "10"))
  expect_equal(c("10", "2")[run_label_order(c("10", "2"))], c("2", "10"))
  expect_equal(c("01", "02")[run_label_order(c("01", "02"))], c("01", "02"))

  # Labels which are not numbers have only their lexicographic order
  expect_equal(c("late", "early")[run_label_order(c("late", "early"))],
               c("early", "late"))
})

test_that("run-2 and run-10 an hour apart are aligned by one hour", {

  tacs <- dplyr::bind_rows(
    two_run_tacs() %>% dplyr::filter(run == "01") %>%
      dplyr::mutate(run = "2", time_zero = "11:00:00"),
    two_run_tacs() %>% dplyr::filter(run == "01") %>%
      dplyr::mutate(run = "10", time_zero = "12:00:00")
  )

  merged <- merge_tacs_runs(tacs)$data

  # 3600 s apart, not 82800: a string sort would have made run-10 the first run
  # and read run-2's earlier clock time as crossing midnight.
  expect_equal(sort(unique(merged$frame_start)), c(0, 300, 3600, 3900))
})

test_that("a value the earliest run lacks is taken from a later run", {

  # first() does not skip NAs of its own accord, so the earliest run's absent
  # dose would otherwise overwrite the one a later run does record -- losing
  # SUV for the measurement, and silently, since the mismatch check ignores NAs.
  tacs <- two_run_tacs()
  tacs$InjectedRadioactivity[tacs$run == "01"] <- NA_real_
  tacs$bodyweight[tacs$run == "01"] <- NA_real_

  merged <- merge_tacs_runs(tacs)$data

  expect_equal(unique(merged$InjectedRadioactivity), 700000)
  expect_equal(unique(merged$bodyweight), 70)
})

test_that("a volume the earliest run lacks is taken from a later run", {

  tacs <- two_run_tacs()
  tacs$volume_mm3[tacs$run == "01"] <- NA_real_

  merged <- merge_tacs_runs(tacs)$data

  expect_equal(unique(merged$volume_mm3), 1000)
})

test_that("a mis-ordering that no label rule can catch is caught by the gap", {

  # "end" precedes "start" alphabetically, so run-start / run-end order wrongly
  # and their TimeZeros are read as crossing midnight. The frames end up a day
  # apart rather than on top of each other, so the overlap check sees nothing.
  # No label rule can fix this -- the result is what gives it away.
  tacs <- dplyr::bind_rows(
    two_run_tacs() %>% dplyr::filter(run == "01") %>%
      dplyr::mutate(run = "start", time_zero = "11:00:00"),
    two_run_tacs() %>% dplyr::filter(run == "01") %>%
      dplyr::mutate(run = "end", time_zero = "12:00:00")
  )

  expect_warning(merge_tacs_runs(tacs),
                 "further apart than one injection is followed for")
})

test_that("a plausible gap and a genuine midnight crossing stay silent", {

  two_runs <- function(tz1, tz2) {
    dplyr::bind_rows(
      two_run_tacs() %>% dplyr::filter(run == "01") %>%
        dplyr::mutate(time_zero = tz1),
      two_run_tacs() %>% dplyr::filter(run == "01") %>%
        dplyr::mutate(run = "02", time_zero = tz2)
    )
  }

  # An hour apart: ordinary two-block acquisition
  expect_no_warning(merge_tacs_runs(two_runs("11:00:00", "12:00:00")))

  # 23:50 then 00:30 is a 40-minute gap once unwrapped, not a 23-hour one
  expect_no_warning(merge_tacs_runs(two_runs("23:50:00", "00:30:00")))
})

test_that("a run merely missing a volume is not a disagreement about it", {

  # n_distinct() counts NA as a value, so an absent volume used to warn that
  # the runs were segmented differently.
  tacs <- two_run_tacs()
  tacs$volume_mm3[tacs$run == "02"] <- NA_real_

  expect_no_warning(merge_tacs_runs(tacs))
})

test_that("the overlap error names the cause per measurement", {

  # One measurement aligned by TimeZero and still overlapping, another with no
  # clock at all: each needs its own remedy, not the cohort's.
  aligned <- two_run_tacs(run2_start = 60) %>%
    dplyr::mutate(time_zero = "11:00:00")
  unclocked <- two_run_tacs(run2_start = 0) %>%
    dplyr::mutate(sub = "02", time_zero = NA_character_)

  err <- tryCatch(merge_tacs_runs(dplyr::bind_rows(aligned, unclocked)),
                  error = conditionMessage)

  expect_match(err, "sub-01.*aligned by TimeZero")
  expect_match(err, "sub-02.*no usable TimeZero")
})

test_that("disjoint runs with misleading labels and no clock stay silent", {

  # run-start sampled first, run-end second, but "end" sorts before "start".
  # With no TimeZero there is nothing to shift, and the frames are plainly
  # disjoint -- so neither check should fire. Asking "do these overlap?" in
  # label order rather than time order would answer -3600 and warn about two
  # intervals that never touch.
  tacs <- dplyr::bind_rows(
    two_run_tacs() %>% dplyr::filter(run == "01") %>%
      dplyr::mutate(run = "start", time_zero = NA_character_),
    two_run_tacs() %>% dplyr::filter(run == "02") %>%
      dplyr::mutate(run = "end", time_zero = NA_character_)
  )

  expect_no_warning(result <- merge_tacs_runs(tacs))
  expect_true(result$merged)
})

test_that("runs placed on top of each other by their TimeZeros are refused", {

  # TimeZeros only 30 s apart, but the runs are an hour long: the clock parsed
  # fine and still puts them on top of each other, so they are not consecutive
  # scans of one injection.
  long_run <- function(run, time_zero) {
    two_run_tacs() %>%
      dplyr::filter(run == "01") %>%
      dplyr::mutate(run = !!run, time_zero = !!time_zero,
                    frame_end = frame_start + 1800,
                    frame_dur = 1800,
                    frame_mid = frame_start + 900)
  }

  expect_error(
    merge_tacs_runs(dplyr::bind_rows(long_run("01", "11:00:00"),
                                     long_run("02", "11:00:30"))),
    "overlap in time")
})
