#' Determine Blood Data Source
#'
#' @description Decide which blood data source to use when blood_dir is not specified
#'
#' @param analysis_folder Character string path to analysis folder
#' @param bids_dir Character string path to BIDS directory (optional)
#' 
#' @return Character string indicating which source to use: "analysis_folder", "bids_dir", or "none"
#' @export
determine_blood_source <- function(analysis_folder, bids_dir = NULL) {
  
  # Check for inputfunction files in analysis folder
  has_analysis_blood <- length(list.files(analysis_folder, pattern = "*_inputfunction\\.tsv$", recursive = TRUE)) > 0
  
  if (has_analysis_blood) {
    return("analysis_folder")
  }
  
  # Check for raw blood data in BIDS directory if provided
  has_bids_blood <- if (!is.null(bids_dir) && dir.exists(bids_dir)) {
    length(list.files(bids_dir, pattern = "_blood\\.tsv$", recursive = TRUE)) > 0
  } else {
    FALSE
  }
  
  if (has_bids_blood) {
    return("bids_dir")
  }
  
  return("none")
}

#' Interpolated Input Function Table from a blooddata Object
#'
#' @description Build the input function petfit writes to an
#'   `_inputfunction.tsv` file: the interpolated blood, plasma, parent fraction
#'   and metabolite-corrected plasma curves, with time in seconds and
#'   radioactivity in Bq.
#'
#'   Separated from the writing so that the runs of one measurement can be
#'   merged before anything reaches disk. See
#'   [merge_inputfunction_tables()].
#'
#' @param blooddata A blooddata object.
#' @param interp_points Number of points to interpolate over.
#' @return Tibble with `time`, `whole_blood_radioactivity`,
#'   `plasma_radioactivity`, `metabolite_parent_fraction` and `AIF` columns. The
#'   `measured_range` attribute records the first and last *measured* sample
#'   times, in seconds -- the interpolation always starts at zero, whether or
#'   not anything was sampled there, and a merge has to know which part of the
#'   curve rests on data.
#' @export
blooddata_inputfunction_table <- function(blooddata, interp_points = 6000) {

  input_data <- kinfitr::bd_create_input(blooddata, interpPoints = interp_points)

  blood_unit  <- blooddata$Data$Blood$Discrete$activity$Units
  plasma_unit <- blooddata$Data$Plasma$activity$Units

  blood_unit  <- stringr::str_remove(blood_unit, "/\\w*")
  plasma_unit <- stringr::str_remove(plasma_unit, "/\\w*")

  output_data <- input_data %>%
    dplyr::rename(
      "time" = Time,
      "whole_blood_radioactivity" = Blood,
      "plasma_radioactivity" = Plasma,
      "metabolite_parent_fraction" = ParentFraction,
      AIF = AIF
    ) %>%
    # Convert units: min to sec, kBq to Bq
    dplyr::mutate(
      time = time * 60,  # min to sec
      whole_blood_radioactivity = kinfitr::unit_convert(whole_blood_radioactivity,
                                                       from_units = blood_unit,
                                                       to_units = "Bq"),
      plasma_radioactivity = kinfitr::unit_convert(plasma_radioactivity, plasma_unit, "Bq"),
      AIF = kinfitr::unit_convert(AIF, blood_unit, "Bq")
    )

  # The class kinfitr attaches marks an interpolated curve, which this no
  # longer is once the units and time base have been changed.
  output_data <- tibble::as_tibble(output_data)

  attr(output_data, "measured_range") <- blooddata_measured_range(blooddata)

  output_data
}

# The first and last times at which anything was actually sampled, in seconds.
# The same set of curves bd_tidy_times() reads to decide where to stop
# interpolating.
blooddata_measured_range <- function(blooddata) {

  times <- c(
    blooddata$Data$Blood$Discrete$Values$time,
    blooddata$Data$Plasma$Values$time,
    blooddata$Data$Metabolite$Values$time,
    blooddata$Data$Blood$Continuous$Values$time
  )

  times <- times[!is.na(times)]

  if (length(times) == 0) {
    return(c(NA_real_, NA_real_))
  }

  c(min(times), max(times))
}

#' Merge the Input Functions of Several Runs into One
#'
#' @description Pool the input functions of the runs of a single measurement
#'   into one curve, for datasets where those runs are consecutive scans of one
#'   injection.
#'
#'   Deliberately plain: each run's curve is interpolated on its own, the pieces
#'   are laid end to end, and the result is interpolated once more onto a single
#'   grid. Nothing is modelled, and the gap between the runs -- when the subject
#'   was out of the scanner and, usually, unsampled -- is bridged linearly like
#'   any other interval between samples.
#'
#'   Each run contributes only the part of its curve that rests on measured
#'   samples. [kinfitr::bd_create_input()] always interpolates from time zero,
#'   so a second run's table opens with a long stretch of padding standing in
#'   for the first run's real data; keeping it would let that padding overwrite
#'   the first run.
#'
#' @param tables List of tibbles from [blooddata_inputfunction_table()], one per
#'   run, each carrying a `measured_range` attribute.
#' @param interp_points Number of points in the merged grid.
#' @param label How to name this measurement in error messages.
#' @param offsets Seconds to add to each table's times, so that runs which each
#'   count from their own `TimeZero` are placed on one clock -- the same
#'   alignment [merge_tacs_runs()] applies to the frame times, and bloodstream
#'   to these same samples. `NULL` (the default) leaves the times as they are,
#'   for runs already sharing a time zero.
#' @return A single tibble with the same columns as its inputs.
#' @export
merge_inputfunction_tables <- function(tables, interp_points = 6000,
                                       label = "this measurement",
                                       offsets = NULL) {

  if (length(tables) == 0) {
    stop("No input functions to merge for ", label, call. = FALSE)
  }

  if (!is.null(offsets)) {
    stopifnot(length(offsets) == length(tables))
    tables <- purrr::map2(tables, offsets, function(table, offset) {
      if (offset == 0) {
        return(table)
      }
      measured <- attr(table, "measured_range")
      table$time <- table$time + offset
      attr(table, "measured_range") <- measured + offset
      table
    })
  }

  if (length(tables) == 1) {
    return(tables[[1]])
  }

  ranges <- lapply(tables, function(x) attr(x, "measured_range"))

  if (any(vapply(ranges, function(r) is.null(r) || any(is.na(r)), logical(1)))) {
    stop("Cannot merge the input functions for ", label,
         ": at least one run has no measured blood samples at all, so there ",
         "is no way to tell which part of its curve is data and which is ",
         "padding.", call. = FALSE)
  }

  order <- order(vapply(ranges, `[`, numeric(1), 1))
  tables <- tables[order]
  ranges <- ranges[order]

  # The same rule the TACs are merged under: the runs are consecutive windows
  # on one timeline, so a later run's samples begin after an earlier run's end.
  for (i in seq_len(length(ranges) - 1L)) {
    if (ranges[[i + 1L]][1] < ranges[[i]][2]) {
      stop("Cannot merge the input functions for ", label,
           ": the blood sampling windows of two runs overlap (one ends at ",
           round(ranges[[i]][2], 1), " s, the next begins at ",
           round(ranges[[i + 1L]][1], 1), " s).\n",
           "Merging places the runs on one clock using their TimeZero times, ",
           "and expects a later run's samples to come after an earlier run's. ",
           "Overlapping windows mean either that no usable TimeZero was ",
           "available to align them, or that the runs are separate ",
           "injections. Check the TimeZero fields in the _pet.json sidecars, ",
           "or switch run merging off in the region definition step.",
           call. = FALSE)
    }
  }

  # The earliest run keeps its opening interpolation to zero, which is what a
  # single-run analysis writes and what the models expect a curve to start
  # from. Later runs are clipped to their own measured span.
  pieces <- purrr::imap(tables, function(table, i) {
    if (i == 1L) {
      return(table)
    }
    dplyr::filter(table, time >= ranges[[i]][1])
  })

  pooled <- dplyr::bind_rows(pieces) %>%
    dplyr::arrange(time) %>%
    dplyr::filter(!duplicated(time))

  grid <- seq(min(pooled$time), max(pooled$time), length.out = interp_points)

  value_columns <- setdiff(colnames(pooled), "time")

  merged <- tibble::tibble(time = grid)
  for (column in value_columns) {
    merged[[column]] <- stats::approx(pooled$time, pooled[[column]],
                                      xout = grid, rule = 2)$y
  }

  merged <- merged[, c("time", value_columns)]

  attr(merged, "measured_range") <- c(ranges[[1]][1],
                                      ranges[[length(ranges)]][2])

  merged
}

#' Write an Input Function to TSV with its JSON Sidecar
#'
#' @description Write the table produced by [blooddata_inputfunction_table()] or
#'   [merge_inputfunction_tables()] as an `_inputfunction.tsv` file with the
#'   BIDS-style sidecar describing its columns.
#'
#' @param input_data Tibble with `time` in seconds and radioactivity in Bq.
#' @param filename Character string full path for output file (with or without
#'   .tsv extension).
#' @return Invisibly, the paths of the created files.
#' @export
write_inputfunction_tsv <- function(input_data, filename) {

  # Remove .tsv extension if present to get file stem
  file_stem <- stringr::str_remove(filename, "\\.tsv$")

  # Create output filenames
  tsv_file <- paste0(file_stem, ".tsv")
  json_file <- paste0(file_stem, ".json")

  # Ensure output directory exists
  dir.create(dirname(tsv_file), recursive = TRUE, showWarnings = FALSE)

  # Create JSON metadata following bloodstream format
  json_metadata <- list(
    time = list(
      Description = "Interpolated time in relation to time zero defined in _pet.json",
      Units = "s"
    ),
    whole_blood_radioactivity = list(
      Description = "Estimated interpolated radioactivity in whole blood samples",
      Units = "Bq"
    ),
    plasma_radioactivity = list(
      Description = "Estimated interpolated radioactivity in whole plasma samples",
      Units = "Bq"
    ),
    metabolite_parent_fraction = list(
      Description = "Parent fraction of the radiotracer in arterial plasma samples"
    ),
    AIF = list(
      Description = "Estimated interpolated radioactivity in metabolite-corrected arterial plasma samples",
      Units = "Bq"
    )
  )

  # Write TSV file
  readr::write_tsv(input_data, tsv_file)

  # Write JSON file
  jsonlite::write_json(json_metadata, json_file, pretty = TRUE, auto_unbox = TRUE)

  invisible(c(tsv_file, json_file))
}

#' Save inputfunction.tsv data from a blooddata object
#'
#' @description Save inputfunction data as TSV file with accompanying JSON metadata
#'
#' @param blooddata Blooddata object containing the blood data structure
#' @param filename Character string full path for output file (with or without .tsv extension)
#' 
#' @details This function saves inputfunction data in the same way as bloodstream does:
#' - Creates interpolated input function using bd_create_input()
#' - TSV file with time, whole_blood_radioactivity, plasma_radioactivity, 
#'   metabolite_parent_fraction, and AIF columns
#' - JSON sidecar with column descriptions and units following BIDS conventions
#' - If filename contains .tsv, it removes it to create the file stem
#' - Saves both .tsv and .json files using the same stem
#' 
#' @return Invisibly returns the paths of created files
#' @export
blooddata2inputfunction_tsv <- function(blooddata, filename) {
  write_inputfunction_tsv(blooddata_inputfunction_table(blooddata), filename)
}

#' Summarise Blood Data Availability
#'
#' @description Provide a status summary of available blood data sources and priority selection.
#'
#' @param analysis_folder Character string path to the current analysis folder (for *_inputfunction.tsv files)
#' @param bids_dir Character string path to the BIDS directory (optional, for raw *_blood.tsv files)
#' @param blood_dir Character string path to an explicit blood data directory (optional)
#'
#' @return A list containing logical flags (`has_analysis_blood`, `has_bids_blood`, `has_blood_dir`)
#'   and the selected `priority_source` ("blood_dir", "analysis_folder", "bids_dir", or "none")
#' @export
get_blood_data_status <- function(analysis_folder, bids_dir = NULL, blood_dir = NULL) {

  # Helper to count files safely
  count_files <- function(path, pattern) {
    if (is.null(path) || !dir.exists(path)) {
      return(0L)
    }
    length(list.files(path, pattern = pattern, recursive = TRUE))
  }

  has_blood_dir <- count_files(blood_dir, "_inputfunction\\.tsv$") > 0
  has_analysis_blood <- count_files(analysis_folder, "_inputfunction\\.tsv$") > 0
  has_bids_blood <- count_files(bids_dir, "_blood\\.tsv$") > 0

  priority_source <- if (has_blood_dir) {
    "blood_dir"
  } else {
    determine_blood_source(analysis_folder, bids_dir)
  }

  list(
    has_analysis_blood = has_analysis_blood,
    has_bids_blood = has_bids_blood,
    has_blood_dir = has_blood_dir,
    priority_source = priority_source
  )
}

# Where the input function for a measurement is written, derived from the
# relative path of that measurement's TACs or weights file inside the analysis
# folder. This is what makes a merged measurement's input function come out
# without a run entity: the TACs file it is named after has none.
inputfunction_output_path <- function(analysis_folder, tacs_relative_path) {
  stem <- stringr::str_remove(tacs_relative_path, "_desc.*")
  stem <- stringr::str_remove(stem, "_weights.*")
  stem <- stringr::str_remove(stem, "_tacs.*")
  file.path(analysis_folder, paste0(stem, "_inputfunction.tsv"))
}

#' Create Input Functions in the Analysis Folder from Raw BIDS Blood Data
#'
#' @description Build an `_inputfunction.tsv` file, with its JSON sidecar, for
#'   each measurement in `tac_data`, by linear interpolation of the blood curves
#'   in the raw BIDS `_blood.tsv` files. This is the fallback used when no
#'   processed input functions are available from bloodstream.
#'
#'   Measurements are matched to raw acquisitions on whichever BIDS entities the
#'   TACs carry. When the runs were merged in the region definition step the
#'   TACs no longer carry `run`, so one measurement matches every run of that
#'   acquisition, and their input functions are pooled into one curve by
#'   [merge_inputfunction_tables()] before being written. The output is named
#'   after the TACs file, so a merged measurement gets a single input function
#'   with no run entity, which then joins to its TACs.
#'
#' @param bids_dir Path to the raw BIDS directory.
#' @param tac_data Tibble of loaded TAC data, carrying entity columns and the
#'   `filename` of each measurement's TACs file relative to `analysis_folder`.
#' @param analysis_folder Path to the analysis folder to write into.
#' @param interp_points Number of points to interpolate each curve over.
#' @return List with `files` (the input function paths written) and `messages`
#'   (character vector describing what was done, for the caller to report).
#' @export
create_analysis_inputfunctions <- function(bids_dir, tac_data, analysis_folder,
                                           interp_points = 6000) {

  if (is.null(bids_dir) || !dir.exists(bids_dir)) {
    stop("Cannot create input functions from raw blood data: no BIDS ",
         "directory available.", call. = FALSE)
  }

  study <- dplyr::ungroup(kinfitr::bids_parse_study(bids_dir))

  entity_columns <- intersect(c("sub", "ses", "task", "trc", "rec", "run"),
                              colnames(study))
  match_columns <- intersect(entity_columns, colnames(tac_data))

  if (length(match_columns) == 0) {
    stop("Cannot match measurements to raw blood data: the TACs carry none of ",
         "the BIDS entities the raw acquisitions are identified by.",
         call. = FALSE)
  }

  sources <- dplyr::select(study, dplyr::all_of(entity_columns), blooddata,
                           dplyr::any_of("petinfo"))

  targets <- tac_data %>%
    dplyr::ungroup() %>%
    dplyr::distinct(dplyr::across(dplyr::all_of(c(match_columns, "filename")))) %>%
    dplyr::mutate(output_path = inputfunction_output_path(analysis_folder, filename))

  # One measurement may draw on several runs, which is the whole point when the
  # runs have been merged; it must never draw on none.
  joined <- dplyr::inner_join(targets, sources, by = match_columns,
                              relationship = "one-to-many")

  unmatched <- setdiff(targets$output_path, joined$output_path)
  if (length(unmatched) > 0) {
    warning("No raw blood data found for ", length(unmatched),
            " measurement(s), which will have no input function:\n",
            paste0("  - ", basename(unmatched), collapse = "\n"),
            call. = FALSE)
  }

  if (nrow(joined) == 0) {
    stop("No measurement could be matched to raw blood data in ", bids_dir,
         call. = FALSE)
  }

  by_measurement <- joined %>%
    dplyr::group_by(output_path) %>%
    dplyr::group_nest(.key = "runs")

  messages <- character(0)
  merged_count <- 0L
  written <- character(0)
  partial <- character(0)
  unsampled <- character(0)
  unaligned <- character(0)

  for (i in seq_len(nrow(by_measurement))) {

    output_path <- by_measurement$output_path[i]
    runs <- by_measurement$runs[[i]]

    # A run can exist without blood data of its own -- sampling stopped after
    # the first scan, say. Such a run contributes nothing to the input
    # function, and asking kinfitr to interpolate it would fail; the runs which
    # were sampled still describe the bloodstream they share.
    sampled <- purrr::map_lgl(runs$blooddata, function(blooddata) {
      inherits(blooddata, "blooddata") &&
        !any(is.na(blooddata_measured_range(blooddata)))
    })

    if (!any(sampled)) {
      unsampled <- c(unsampled, basename(output_path))
      next
    }

    if (!all(sampled)) {
      partial <- c(partial, basename(output_path))
    }

    # Runs in label order, which is collection order and the order the clock
    # offsets are unwrapped in -- the sample times of a run counting from its
    # own TimeZero carry no order of their own.
    runs <- runs[order(runs$run, method = "radix"), , drop = FALSE]
    sampled <- sampled[order(runs$run, method = "radix")]

    contributing <- runs[sampled, , drop = FALSE]

    offsets <- NULL
    if (nrow(contributing) > 1 && "petinfo" %in% colnames(contributing)) {
      offsets <- run_clock_offsets(purrr::map_chr(
        contributing$petinfo,
        ~as.character((.x$TimeZero %||% NA_character_)[1])))

      if (is.null(offsets)) {
        unaligned <- c(unaligned, basename(output_path))
      }
    }

    tables <- purrr::map(contributing$blooddata,
                         ~blooddata_inputfunction_table(.x, interp_points))

    input_data <- merge_inputfunction_tables(
      tables,
      interp_points = interp_points,
      label = basename(output_path),
      offsets = offsets)

    write_inputfunction_tsv(input_data, output_path)
    written <- c(written, output_path)

    if (length(tables) > 1) {
      merged_count <- merged_count + 1L
    }
  }

  if (length(unsampled) > 0) {
    warning("No blood samples at all for ", length(unsampled),
            " measurement(s), which will have no input function:\n",
            paste0("  - ", unsampled, collapse = "\n"), call. = FALSE)
  }

  if (length(unaligned) > 0) {
    warning("No usable TimeZero for every run of ", length(unaligned),
            " merged measurement(s), so their blood sample times were taken ",
            "as already sharing a time zero:\n",
            paste0("  - ", unaligned, collapse = "\n"), call. = FALSE)
  }

  if (length(partial) > 0) {
    warning("Some runs of ", length(partial),
            " merged measurement(s) have no blood samples of their own, so ",
            "their input function rests on the runs that were sampled:\n",
            paste0("  - ", partial, collapse = "\n"), call. = FALSE)
  }

  messages <- c(messages,
                paste0("Created ", length(written),
                       " input function(s) from the raw BIDS blood data."))

  if (merged_count > 0) {
    messages <- c(
      messages,
      paste0("Of these, ", merged_count,
             " pooled the blood data of more than one run into a single input ",
             "function, because the runs were merged in the region definition ",
             "step."),
      paste0("The interval between one run's last blood sample and the next ",
             "run's first is bridged by linear interpolation, like any other ",
             "interval between samples. Over the long unsampled gap between ",
             "two scanning occasions that is an approximation, so a model ",
             "whose fit depends on the input function through that interval ",
             "should be read with that in mind."))
  }

  list(files = written, messages = messages)
}

#' Check That Input Functions and TACs Agree About Runs
#'
#' @description Stop, with an explanation, when the TACs have been merged across
#'   runs but the input functions have not.
#'
#'   The reports join blood to TACs on whichever entity columns the two have in
#'   common. When the TACs carry no `run` but the input functions do, `run` is
#'   simply not joined on, and every run's input function matches the one merged
#'   measurement -- which either fails as a duplicate or, worse, silently picks
#'   one run's blood curve to model a measurement spanning both.
#'
#'   The mismatch runs in both directions, and the other one is the quieter of
#'   the two. bloodstream merges runs by default, so an analysis which keeps its
#'   runs apart can be handed a single merged input function per measurement;
#'   `run` is again not joined on, the one blood record matches both runs, and
#'   the `many-to-one` relationship is satisfied -- so both runs are modelled
#'   against a curve built from the samples of both, with nothing to show for
#'   it. That is only wrong where a measurement has more than one run: a
#'   single-run measurement whose input function simply omits the entity is
#'   matched correctly.
#'
#' @param tac_data Tibble of loaded TAC data.
#' @param blood_data Tibble of loaded blood data, one row per input function.
#' @return Invisibly `TRUE` when the two agree.
#' @export
check_blood_run_alignment <- function(tac_data, blood_data) {

  tacs_have_run <- "run" %in% colnames(tac_data) &&
    any(!is.na(tac_data$run))

  blood_has_run <- "run" %in% colnames(blood_data) &&
    any(!is.na(blood_data$run))

  if (blood_has_run && !tacs_have_run) {
    stop("The TACs have been merged across runs, but the input functions are ",
         "still one per run.\n",
         "A merged measurement spans every one of its runs, so it needs a ",
         "single input function spanning them too. Either produce run-merged ",
         "input functions (bloodstream can do this), delete the per-run ones ",
         "from the analysis folder so that petfit rebuilds them from the raw ",
         "BIDS blood data, or switch run merging off in the region definition ",
         "step and rerun the analysis.", call. = FALSE)
  }

  if (tacs_have_run && !blood_has_run) {

    # Only a measurement with several runs can be mispaired. One run and a
    # run-less input function describe the same acquisition.
    entities <- intersect(c("sub", "ses", "task", "trc", "rec"),
                          colnames(tac_data))

    multi_run <- if (length(entities) == 0) {
      dplyr::n_distinct(tac_data$run, na.rm = TRUE) > 1
    } else {
      counts <- tac_data %>%
        dplyr::group_by(dplyr::across(dplyr::all_of(entities))) %>%
        dplyr::summarise(runs = dplyr::n_distinct(run, na.rm = TRUE),
                         .groups = "drop")
      any(counts$runs > 1)
    }

    if (multi_run) {
      stop("The TACs keep each run as a separate measurement, but the input ",
           "functions are one per measurement with no run entity.\n",
           "Blood is joined to TACs on the entities they share, so a single ",
           "run-less input function would be paired with every run of its ",
           "measurement, and each run would be modelled against a curve built ",
           "from the samples of all of them. Either merge the runs in the ",
           "region definition step so that the TACs match the blood, or ",
           "produce per-run input functions (set MergeRuns to false in the ",
           "bloodstream configuration).", call. = FALSE)
    }
  }

  invisible(TRUE)
}
