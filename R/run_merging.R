# Merging Multiple Runs of a Single Injection
#
# Some tracers are acquired as two scanning occasions from one injection --
# run-01 and run-02, or run-early and run-late -- with the subject out of the
# scanner in between. Those runs are two windows onto the same bloodstream and
# the same kinetics, and they should be fitted together as one measurement
# rather than separately.
#
# Other datasets use runs for genuinely separate injections, which must stay
# apart. petfit cannot tell the two apart from the filenames, so merging is a
# choice made in the region definition step, on by default because the
# single-injection case is the more common one.
#
# The merge itself is deliberately plain. The combined TACs are already in long
# format with one row per frame, so the runs of one measurement are merged by
# dropping the `run` entity that separated them: the rows need no arithmetic,
# and the frame times are used exactly as the source files recorded them. What
# this file adds is the checking around that -- the frames of the runs must not
# overlap, and the runs must agree on the things a shared injection implies.

# The entity columns which identify a measurement once `run` no longer does.
# `run` is deliberately absent: that is the whole point of a merge.
merged_measurement_entities <- function(data) {
  intersect(c("sub", "ses", "task", "trc", "rec"), colnames(data))
}

# --- Placing the runs of a measurement on one clock -------------------------
#
# BIDS gives frame times relative to the TimeZero of their own acquisition.
# Runs which share a TimeZero are therefore already on one clock, and runs
# which each define their own start again from zero. The offset between two
# runs is the difference between their TimeZero clock times.
#
# This is deliberately the same rule bloodstream applies to blood sample times
# when it merges runs, so that a study which merges in one tool merges in the
# other. The duplication between the two repos is intended, and not a candidate
# for kinfitr: kinfitr does none of the merging, so the rule would have no
# caller there. Keep the two in step by hand.
#
# TimeZero comes from the raw `_pet.json`, so it is available when `bids_dir`
# is given; a derivatives-only run usually has no TimeZero at all, and falls
# back to taking the times as already shared.

# Seconds since midnight for a BIDS TimeZero, or NA when the field carries no
# clock time. A dataset which sets TimeZero to "0" is timing from its own scan
# start rather than from the clock, and so cannot be aligned this way.
petfit_clocktime_seconds <- function(x) {

  if (is.null(x) || length(x) == 0) {
    return(NA_real_)
  }

  x <- stringr::str_trim(as.character(x)[1])
  if (is.na(x)) {
    return(NA_real_)
  }

  parts <- stringr::str_match(x, "^(\\d{1,2}):(\\d{2})(?::(\\d{2}(?:\\.\\d+)?))?$")
  if (is.na(parts[1, 1])) {
    return(NA_real_)
  }

  hours <- as.numeric(parts[1, 2])
  minutes <- as.numeric(parts[1, 3])
  seconds <- if (is.na(parts[1, 4])) 0 else as.numeric(parts[1, 4])

  if (hours > 23 || minutes > 59 || seconds >= 60) {
    return(NA_real_)
  }

  hours * 3600 + minutes * 60 + seconds
}

# Longer than one injection is followed for. Two scanning blocks of a single
# injection follow each other within hours -- the tracer has decayed away
# otherwise -- so a merged measurement spanning longer than this did not come
# from one injection, whatever its labels claim.
max_plausible_run_gap <- 6 * 3600

# The order in which a measurement's runs were collected, from their labels.
#
# Radix order alone is wrong: BIDS run indices need not be zero-padded, and as
# strings "10" sorts before "2". Getting this wrong is not cosmetic --
# run_clock_offsets() unwraps midnight in this order, so a mis-ordered pair an
# hour apart is read as nearly a day apart, and the frame times are shifted by
# 23 hours with the overlap check none the wiser.
#
# Numeric labels are therefore ordered numerically and come first; anything
# else follows in lexicographic order, which is the only order such labels
# offer -- and which is not to be trusted. "early" happens to precede "late",
# but "end" precedes "start", and there will always be another word pair whose
# alphabetical order lies about collection order. No label rule can fix that,
# so the result is checked instead: see the gap check in
# align_measurement_runs(), which catches a mis-ordering without needing a
# vocabulary.
run_label_order <- function(runs) {

  runs <- as.character(runs)
  numeric_value <- suppressWarnings(as.numeric(runs))
  is_numeric <- !is.na(numeric_value)

  order(!is_numeric, numeric_value, runs, method = "radix")
}

# The offset to add to each run's frame times, in seconds, so that they all
# refer to the first run's TimeZero. NULL when any run lacks a usable
# TimeZero: the caller then treats the times as already sharing a clock, which
# is what a dataset timing every run from one injection looks like.
#
# `time_zeros` must be in run-label order, which is the order the runs were
# collected in for run-01/run-02 and run-early/run-late. Frame times cannot be
# used to order them here -- when each run starts again from zero, which is
# exactly the case these offsets exist for, they carry no order at all.
run_clock_offsets <- function(time_zeros) {

  clock <- vapply(time_zeros, petfit_clocktime_seconds, numeric(1),
                  USE.NAMES = FALSE)

  if (length(clock) == 0 || any(is.na(clock))) {
    return(NULL)
  }

  # A session running past midnight gives a later run the smaller clock time,
  # so the sequence is unwrapped rather than read as the later run having come
  # first.
  for (i in seq_along(clock)[-1]) {
    while (clock[i] < clock[i - 1]) {
      clock[i] <- clock[i] + 86400
    }
  }

  clock - clock[1]
}

# Per-measurement scalars which a single injection fixes, and so which the runs
# of one measurement must agree on. A disagreement usually means the runs are
# separate injections and should not have been merged at all.
merged_shared_scalars <- c("InjectedRadioactivity", "bodyweight")

# Name a measurement the way a user will recognise it, for messages.
describe_measurement <- function(row, entities) {
  values <- unlist(row[1, entities, drop = FALSE])
  values <- values[!is.na(values)]
  if (length(values) == 0) {
    return("(measurement with no entities)")
  }
  paste(paste0(names(values), "-", values), collapse = "_")
}

# List at most `limit` offenders, then say how many were not listed. A merge
# problem is usually systematic, so the first few are enough to diagnose it.
list_offenders <- function(descriptions, limit = 5L) {
  shown <- utils::head(descriptions, limit)
  text <- paste0("  - ", shown, collapse = "\n")
  if (length(descriptions) > limit) {
    text <- paste0(text, "\n  - ... and ", length(descriptions) - limit, " more")
  }
  text
}

#' Check That the Runs of a Measurement Do Not Overlap in Time
#'
#' @description Two runs of one injection are consecutive windows on a single
#'   timeline, so their frames sit end to end. Frames which overlap mean the
#'   frame times of each run are counted from that run's own start rather than
#'   from the injection, or that the runs are separate injections. Either way
#'   the rows cannot simply be pooled, and merging them would produce a
#'   measurement whose TAC doubles back on itself.
#'
#'   The check is made on the distinct frames of a measurement, since every
#'   region of a run shares them.
#'
#' @param frames Tibble with `run`, `frame_start` and `frame_end` columns for a
#'   single measurement.
#' @return `NULL` when the frames are consecutive, or a character string
#'   describing the overlap.
#' @noRd
describe_run_overlap <- function(frames) {

  frames <- frames %>%
    dplyr::distinct(run, frame_start, frame_end) %>%
    dplyr::arrange(frame_start, frame_end)

  if (nrow(frames) < 2) {
    return(NULL)
  }

  # Only overlaps *between* runs matter. A run whose own frames overlap is a
  # problem in the source file, and not one merging creates or can fix.
  for (i in seq_len(nrow(frames) - 1L)) {
    later <- frames[i + 1L, ]
    earlier <- frames[i, ]

    if (identical(later$run, earlier$run) || is.na(later$run) || is.na(earlier$run)) {
      next
    }

    if (later$frame_start < earlier$frame_end) {
      return(paste0(
        "run-", earlier$run, " has a frame ending at ",
        round(earlier$frame_end, 1), " s, while run-", later$run,
        " has a frame starting at ", round(later$frame_start, 1), " s"))
    }
  }

  NULL
}

# Remove the TimeZero helper column, which exists only to align runs and has
# no place in the output.
drop_time_zero <- function(data) {
  dplyr::select(data, -dplyr::any_of("time_zero"))
}

# Shift each measurement's runs onto the clock of its first run.
#
# Returns the data with frame times aligned, whatever messages the alignment
# produced, and whether any measurement was actually aligned from TimeZero --
# which decides what to advise if frames still overlap afterwards.
align_measurement_runs <- function(combined_data, group_columns) {

  messages <- character(0)
  frame_columns <- intersect(c("frame_start", "frame_end", "frame_mid"),
                             colnames(combined_data))

  if (!"time_zero" %in% colnames(combined_data) || length(frame_columns) == 0) {
    return(list(data = combined_data, messages = messages,
                aligned_labels = character(0)))
  }

  combined_data$.run_offset <- 0

  aligned_count <- 0L
  aligned_labels <- character(0)
  assumed <- character(0)
  implausible <- character(0)

  keys <- combined_data %>%
    dplyr::distinct(dplyr::across(dplyr::all_of(group_columns)))

  for (i in seq_len(nrow(keys))) {

    in_group <- rep(TRUE, nrow(combined_data))
    for (column in group_columns) {
      value <- keys[[column]][i]
      in_group <- in_group &
        if (is.na(value)) is.na(combined_data[[column]]) else
          (!is.na(combined_data[[column]]) & combined_data[[column]] == value)
    }

    runs <- unique(stats::na.omit(combined_data$run[in_group]))
    if (length(runs) < 2) {
      next
    }

    # Collection order, which is the order run_clock_offsets() unwraps
    # midnight in. See run_label_order() for why radix alone will not do.
    runs <- runs[run_label_order(runs)]

    time_zeros <- vapply(runs, function(r) {
      values <- unique(stats::na.omit(
        combined_data$time_zero[in_group & !is.na(combined_data$run) &
                                  combined_data$run == r]))
      if (length(values) == 0) NA_character_ else as.character(values[1])
    }, character(1), USE.NAMES = FALSE)

    offsets <- run_clock_offsets(time_zeros)
    label <- describe_measurement(keys[i, , drop = FALSE], group_columns)

    if (is.null(offsets)) {
      assumed <- c(assumed, label)
      next
    }

    if (any(offsets != 0)) {
      aligned_count <- aligned_count + 1L
      aligned_labels <- c(aligned_labels, label)
      for (j in seq_along(runs)) {
        rows <- in_group & !is.na(combined_data$run) & combined_data$run == runs[j]
        combined_data$.run_offset[rows] <- offsets[j]
      }

      # Where the runs have landed, now that they have been shifted. A
      # mis-ordering pushes them a day apart rather than on top of each other,
      # so the overlap check downstream sees nothing wrong -- this is what
      # notices.
      extents <- lapply(seq_along(runs), function(j) {
        rows <- in_group & !is.na(combined_data$run) & combined_data$run == runs[j]
        c(min(combined_data$frame_start[rows], na.rm = TRUE) + offsets[j],
          max(combined_data$frame_end[rows], na.rm = TRUE) + offsets[j])
      })

      extents <- extents[order(vapply(extents, `[`, numeric(1), 1))]

      gaps <- vapply(seq_len(length(extents) - 1L), function(j) {
        extents[[j + 1L]][1] - extents[[j]][2]
      }, numeric(1))

      if (any(gaps > max_plausible_run_gap)) {
        implausible <- c(implausible, paste0(
          label, ": placed ", round(max(gaps) / 3600, 1),
          " hours apart, combined in the order ",
          paste(runs, collapse = " + ")))
      }
    } else {
      # Runs sharing a TimeZero are already on one clock; nothing to shift, but
      # the clock was read, so an overlap afterwards is not a missing-metadata
      # problem.
      aligned_count <- aligned_count + 1L
      aligned_labels <- c(aligned_labels, label)
    }
  }

  if (aligned_count > 0) {
    messages <- c(messages, paste0(
      "Placed the runs of ", aligned_count,
      " measurement(s) on one clock using their TimeZero times."))
  }

  if (length(assumed) > 0) {
    messages <- c(messages, paste0(
      "No usable TimeZero for every run of ", length(assumed),
      " measurement(s), so their frame times were taken as already sharing a ",
      "time zero:\n", list_offenders(assumed)))
  }

  # A gap no injection could span means the runs were combined in the wrong
  # order: their TimeZeros were then read as crossing midnight and one run was
  # shifted by a day. The runs are ordered from their labels, and no label rule
  # is reliable, so this is the check that catches it -- for run-start /
  # run-end, and for whatever the next misleading pair turns out to be.
  if (length(implausible) > 0) {
    warning("The runs of ", length(implausible),
            " measurement(s) have been placed further apart than one ",
            "injection is followed for:\n", list_offenders(implausible), "\n",
            "That order was taken from the run labels. If it is not the order ",
            "they were collected in, their TimeZeros have been read as ",
            "crossing midnight and one run's frames shifted by a day. Check ",
            "the run labels.", call. = FALSE)
  }

  for (column in frame_columns) {
    combined_data[[column]] <- combined_data[[column]] + combined_data$.run_offset
  }

  combined_data$.run_offset <- NULL

  list(data = combined_data, messages = messages,
       aligned_labels = aligned_labels)
}

#' Merge the Runs of Each Measurement in Combined TACs Data
#'
#' @description Pool the runs of each measurement into a single measurement, for
#'   datasets where the runs of one measurement are consecutive scans of one
#'   injection.
#'
#'   The runs are placed on one clock by the difference between their `TimeZero`
#'   clock times, which is the rule bloodstream applies to the blood samples of
#'   the same runs. Runs sharing a `TimeZero` are already on one clock and are
#'   not moved; runs which each start again from zero are shifted onto the first
#'   run's. `TimeZero` is read from a `time_zero` column, which
#'   [create_petfit_combined_tacs()] fills from the raw `_pet.json` when a
#'   `bids_dir` is available.
#'
#'   Without a usable `TimeZero` for every run of a measurement -- a
#'   derivatives-only run usually has none, since the pipelines' `_tacs.json`
#'   sidecars do not carry it -- the times are taken as the source files
#'   recorded them, on the assumption that they already share a time zero. That
#'   is the same fallback bloodstream makes.
#'
#'   Either way the result is checked: frames which still overlap between runs
#'   contradict whichever assumption was made, and are an error rather than a
#'   silent pooling.
#'
#'   `run` is dropped from the measurements which were **actually merged**, and
#'   from those alone. A measurement with a single run keeps it, whatever the
#'   rest of the cohort did.
#'
#'   This is the rule bloodstream uses, so the two tools name the same
#'   measurement the same way and their outputs join. It is also the rule
#'   [pet_key()] exists to enforce: a measurement's identity is built from its
#'   own entities and nothing else. Dropping `run` cohort-wide would make one
#'   subject's filenames depend on whether *another* subject happened to have
#'   two runs -- exactly the cohort-dependent naming that orphaned files before
#'   `pet_key()` replaced [attributes_to_title()].
#'
#' @param combined_data Tibble of combined TACs data in long format, carrying
#'   the BIDS entity columns and one row per region and frame. An optional
#'   `time_zero` column holds each measurement's BIDS `TimeZero`, and is used
#'   to place its runs on one clock; it is dropped from the result.
#' @return List with `data` (the merged tibble), `merged` (whether anything was
#'   actually merged) and `messages` (character vector describing what was
#'   merged, for the caller to report). `merged` is what belongs in the output
#'   sidecar: asking to merge a dataset with nothing to merge changes nothing,
#'   and recording it as merged would misdescribe the file.
#' @export
merge_tacs_runs <- function(combined_data) {

  messages <- character(0)

  if (is.null(combined_data) || nrow(combined_data) == 0) {
    return(list(data = combined_data, merged = FALSE, messages = messages))
  }

  if (!"run" %in% colnames(combined_data)) {
    return(list(data = drop_time_zero(combined_data), merged = FALSE,
                messages = "No run entity in the data: nothing to merge."))
  }

  entities <- merged_measurement_entities(combined_data)

  if (length(entities) == 0) {
    stop("Cannot merge runs: the combined TACs data carries no entity columns ",
         "other than run, so there is no way to tell which runs belong to the ",
         "same measurement.", call. = FALSE)
  }

  # A measurement is identified by its entities; the segmentation is carried
  # along because each segmentation is a separate set of frames and regions.
  group_columns <- c(entities, intersect("segmentation", colnames(combined_data)))

  measurements <- combined_data %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(group_columns))) %>%
    dplyr::group_nest(.key = "rows")

  runs_per_measurement <- purrr::map_int(measurements$rows, function(rows) {
    length(unique(stats::na.omit(rows$run)))
  })

  if (all(runs_per_measurement < 2)) {
    # Nothing to merge, so nothing is changed -- `run` included. Dropping a
    # run entity that every measurement carries singly would rename every
    # output of a dataset the merge did not touch, and the consistency it was
    # dropped for has nothing to be consistent with.
    return(list(
      data = drop_time_zero(combined_data),
      merged = FALSE,
      messages = paste0(
        "Run merging is on, but no measurement has more than one run, so ",
        "nothing was merged and the run entity has been left as it is.")))
  }

  # Place each measurement's runs on one clock first, so that everything after
  # this -- the overlap check, the choice of earliest run, the ordering -- reads
  # frame times which mean the same thing across runs.
  aligned <- align_measurement_runs(combined_data, group_columns)
  combined_data <- aligned$data
  messages <- c(messages, aligned$messages)
  aligned_labels <- aligned$aligned_labels

  measurements <- combined_data %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(group_columns))) %>%
    dplyr::group_nest(.key = "rows")

  # Every check runs over every multi-run measurement before anything is
  # merged, so a dataset which cannot be merged says so once, in full, rather
  # than failing on whichever measurement happened to be processed first.
  overlaps <- character(0)
  scalar_mismatches <- character(0)
  volume_mismatches <- character(0)

  for (i in which(runs_per_measurement >= 2L)) {

    rows <- measurements$rows[[i]]
    label <- describe_measurement(measurements[i, ], group_columns)

    overlap <- describe_run_overlap(rows)
    if (!is.null(overlap)) {
      # Why this measurement overlaps, and so what to do about it, depends on
      # whether *it* had a clock to be aligned by -- not on whether some other
      # measurement in the cohort did.
      cause <- if (label %in% aligned_labels) {
        " (aligned by TimeZero, so these are not consecutive scans)"
      } else {
        " (no usable TimeZero, so the times were assumed to be shared)"
      }
      overlaps <- c(overlaps, paste0(label, ": ", overlap, cause))
    }

    for (scalar in intersect(merged_shared_scalars, colnames(rows))) {
      values <- unique(stats::na.omit(rows[[scalar]]))
      if (length(values) > 1) {
        scalar_mismatches <- c(
          scalar_mismatches,
          paste0(label, ": ", scalar, " differs between runs (",
                 paste(signif(values, 6), collapse = ", "), ")"))
      }
    }

    if (all(c("region", "volume_mm3") %in% colnames(rows))) {
      differing <- rows %>%
        dplyr::distinct(region, run, volume_mm3) %>%
        dplyr::group_by(region) %>%
        # na.omit, as the scalar check above uses: a run which simply has no
        # volume is not a run which disagrees about it.
        dplyr::filter(dplyr::n_distinct(stats::na.omit(volume_mm3)) > 1) %>%
        dplyr::ungroup()

      if (nrow(differing) > 0) {
        volume_mismatches <- c(
          volume_mismatches,
          paste0(label, ": ", dplyr::n_distinct(differing$region),
                 " region(s) have a different volume in different runs"))
      }
    }
  }

  if (length(overlaps) > 0) {
    stop("Cannot merge runs: the frames of different runs overlap in time for ",
         length(overlaps), " measurement(s).\n",
         list_offenders(overlaps), "\n",
         "Merging treats the runs of one measurement as consecutive scans of a ",
         "single injection, so that run-02 begins after run-01 ends. Where no ",
         "usable TimeZero was available, rerun with bids_dir pointing at the ",
         "raw BIDS directory, whose _pet.json sidecars carry it, so the runs ",
         "can be placed on one clock. Where one was used and the frames still ",
         "overlap, the runs are not consecutive scans of one injection: switch ",
         "run merging off to keep them as separate measurements.",
         call. = FALSE)
  }

  # A disagreement about the dose or the body weight does not make the merge
  # impossible, but it does mean one of the two premises is wrong, so it is
  # reported rather than quietly resolved. The earliest run's value is the one
  # kept: for a single injection it is the run the dose was recorded against.
  if (length(scalar_mismatches) > 0) {
    warning("The runs being merged disagree about values a single injection ",
            "fixes, which suggests they are separate injections rather than ",
            "two scans of one:\n", list_offenders(scalar_mismatches), "\n",
            "The value from the earliest run of each measurement has been ",
            "used. Switch run merging off if these are separate injections.",
            call. = FALSE)
  }

  if (length(volume_mismatches) > 0) {
    warning("Regions were segmented to different volumes in different runs of ",
            "the same measurement:\n", list_offenders(volume_mismatches), "\n",
            "The volume from the earliest run has been used for the merged ",
            "measurement. The TACs themselves are unchanged -- each run's ",
            "frames keep the values its own segmentation produced.",
            call. = FALSE)
  }

  merged <- combined_data

  # Reconcile to the earliest run of each measurement. "Earliest" is read from
  # the frame times rather than the run label, because a label is only
  # conventionally ordered -- "early"/"late" sort the right way, but "am"/"pm"
  # do not, and neither does "2"/"10".
  run_order <- merged %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(c(group_columns, "run")))) %>%
    dplyr::summarise(first_frame = min(frame_start, na.rm = TRUE),
                     .groups = "drop") %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(group_columns))) %>%
    dplyr::arrange(first_frame, .by_group = TRUE) %>%
    dplyr::mutate(run_rank = dplyr::row_number()) %>%
    dplyr::ungroup() %>%
    dplyr::select(dplyr::all_of(c(group_columns, "run")), run_rank)

  merged <- merged %>%
    dplyr::left_join(run_order,
                     by = c(group_columns, "run"),
                     relationship = "many-to-one")

  # The earliest run's value, but not its *absence*: `na_rm` matters, because
  # first() would otherwise overwrite a dose or a body weight that a later run
  # does record with the earliest run's NA, losing SUV for the measurement and
  # saying nothing -- the mismatch check above ignores NAs, so it has nothing
  # to report either.
  shared_scalars <- intersect(merged_shared_scalars, colnames(merged))
  if (length(shared_scalars) > 0) {
    merged <- merged %>%
      dplyr::group_by(dplyr::across(dplyr::all_of(group_columns))) %>%
      dplyr::mutate(dplyr::across(dplyr::all_of(shared_scalars),
                                  ~dplyr::first(.x, order_by = run_rank,
                                                na_rm = TRUE))) %>%
      dplyr::ungroup()
  }

  if (all(c("region", "volume_mm3") %in% colnames(merged))) {
    merged <- merged %>%
      dplyr::group_by(dplyr::across(dplyr::all_of(c(group_columns, "region")))) %>%
      dplyr::mutate(volume_mm3 = dplyr::first(volume_mm3, order_by = run_rank,
                                              na_rm = TRUE)) %>%
      dplyr::ungroup()
  }

  # Only the measurements which actually pooled runs lose the entity. Blanking
  # it cohort-wide would rename the outputs of a single-run measurement because
  # of what some other subject's data looked like.
  merged <- merged %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(group_columns))) %>%
    dplyr::mutate(run = if (dplyr::n_distinct(run, na.rm = TRUE) > 1) {
      NA_character_
    } else {
      run
    }) %>%
    dplyr::ungroup()

  merged <- merged %>%
    dplyr::select(-run_rank, -dplyr::any_of("time_zero")) %>%
    dplyr::arrange(dplyr::across(dplyr::all_of(
      c(group_columns, intersect("region", colnames(merged)), "frame_start"))))

  n_merged <- sum(runs_per_measurement >= 2L)
  n_runs <- sum(runs_per_measurement[runs_per_measurement >= 2L])

  messages <- c(
    messages,
    paste0("Merged ", n_runs, " runs into ", n_merged,
           " measurement(s), treating each measurement's runs as consecutive ",
           "scans of one injection."),
    paste0("The run entity has been dropped from those ", n_merged,
           " measurement(s). Measurements with a single run keep it."))

  list(data = merged, merged = TRUE, messages = messages)
}
