# Input validation functions
# Validation logic for user inputs and configuration parameters

# Subsetting fields, and the data column each one filters. `regions` is the name
# used in the config and the UI; the column it filters is `region`.
subset_field_columns <- c(sub = "sub", ses = "ses", task = "task", trc = "trc",
                          rec = "rec", run = "run", regions = "region")

# How each field is spelled where the user typed it, for use in messages.
subset_field_labels <- c(sub = "sub", ses = "ses", task = "task", trc = "trc",
                         rec = "rec", run = "run", regions = "Regions")

#' Prefix a message with the subsetting field it refers to
#' @noRd
subset_field_prefix <- function(field) {
  if (is.null(field) || length(field) == 0) return("")
  if (is.na(field) || !nzchar(field)) return("")
  paste0(field, ": ")
}

#' Reject commas in subsetting values
#'
#' @description Values are separated by `;`. A comma is always a mistyped
#'   separator: `"H_Striatum, H_CerebellarWM"` is one value matching no region,
#'   not two values matching two.
#' @noRd
check_no_commas <- function(values, field = NULL) {
  values <- as.character(values)
  values <- values[!is.na(values)]

  offenders <- values[stringr::str_detect(values, stringr::fixed(","))]
  if (length(offenders) == 0) {
    return(invisible(TRUE))
  }

  suggestions <- vapply(offenders, function(v) {
    parts <- stringr::str_trim(stringr::str_split(v, ",")[[1]])
    paste(parts[nzchar(parts)], collapse = "; ")
  }, character(1), USE.NAMES = FALSE)

  stop(subset_field_prefix(field),
       "subsetting values are separated by \";\" and may not contain commas.\n",
       paste0("  Offending value: \"", offenders, "\"\n",
              "  Did you mean:    \"", suggestions, "\"?",
              collapse = "\n"),
       call. = FALSE)
}

#' Describe the values available in a column
#' @noRd
describe_available_values <- function(available, column) {
  if (length(available) == 0) {
    # An empty `run` column is the ordinary outcome of run merging rather than
    # a sign of missing data, and subsetting by run is the one thing merging
    # makes impossible. Say so here, where the user is looking.
    hint <- if (identical(column, "run")) {
      paste0(" Runs were either merged in the region definition step, which",
             " drops the run entity, or the dataset has no runs at all; either",
             " way there is no run left to subset by.")
    } else {
      ""
    }
    return(paste0("Available: none - no row in the data carries a ",
                  column, " value.", hint))
  }

  shown <- available[seq_len(min(20L, length(available)))]
  paste0("Available (", length(available), "): ",
         paste(shown, collapse = ", "),
         if (length(available) > 20L) {
           paste0(", ... and ", length(available) - 20L, " more")
         } else {
           ""
         })
}

#' Validate Subsetting Values Against the Available Data
#'
#' @description Check that every subsetting value matches at least one row of
#'   the data it will be used to filter.
#'
#'   petfit's subsetting fields are free text, so a typo or a mistyped separator
#'   used to filter silently: the offending value simply matched nothing, the
#'   analysis ran on a narrower dataset than requested, and reports were
#'   generated as though nothing were wrong.
#'
#'   Included and excluded values are treated differently, deliberately. A value
#'   you asked to *include* that matches nothing silently narrows the analysis,
#'   so it is an **error**. A value you asked to *exclude* that matches nothing
#'   leaves the analysis complete rather than wrong, so it is a **warning** — but
#'   it must not pass in silence, because you believe you removed something you
#'   did not.
#'
#' @param data A data frame to be subset — the combined TACs table, or any table
#'   carrying the subsetting columns.
#' @param subset_params Named list of subsetting values, as built by
#'   [parse_semicolon_values()]. Names must be drawn from `sub`, `ses`, `task`,
#'   `trc`, `rec`, `run` and `regions`. A `negate` attribute on a value marks
#'   that field as an exclusion.
#' @return Invisibly `TRUE` when every included value matches. Otherwise an
#'   error naming every offending field and listing the values available in each.
#' @export
validate_subset_params <- function(data, subset_params) {
  if (is.null(subset_params) || length(subset_params) == 0) {
    return(invisible(TRUE))
  }

  fields <- names(subset_params)
  if (is.null(fields) || any(!nzchar(fields))) {
    stop("subset_params must be a named list of subsetting values.",
         call. = FALSE)
  }

  problems <- character(0)

  for (field in fields) {
    values <- subset_params[[field]]
    if (is.null(values) || length(values) == 0) {
      next
    }

    if (!field %in% names(subset_field_columns)) {
      stop("Unknown subsetting field \"", field, "\". Expected one of: ",
           paste(names(subset_field_columns), collapse = ", "), ".",
           call. = FALSE)
    }

    column <- subset_field_columns[[field]]
    label <- subset_field_labels[[field]]
    negate <- isTRUE(attr(values, "negate"))

    # Guard the exported entry points against hand-built parameter lists that
    # never passed through parse_semicolon_values().
    check_no_commas(values, label)

    # A column that is absent, or present but NA throughout, has no available
    # values. Both are ordinary: absent BIDS entities are stored as NA, and a
    # column that is NA throughout is read back as a logical column.
    available <- if (column %in% colnames(data)) {
      unique(as.character(data[[column]]))
    } else {
      character(0)
    }
    available <- sort(available[!is.na(available)])

    # as.character() on both sides mirrors the coercion %in% does in the filter
    # this validates: run is read as integer, but typed as text.
    wanted <- as.character(values)
    unmatched <- unique(wanted[!wanted %in% available])

    if (length(unmatched) == 0) {
      next
    }

    detail <- paste0(paste0("\"", unmatched, "\"", collapse = ", "),
                     "\n    ", describe_available_values(available, column))

    if (negate) {
      warning(label, ": excluded ",
              if (length(unmatched) == 1) "value matches" else "values match",
              " nothing in the data, so nothing was excluded for ",
              if (length(unmatched) == 1) "it" else "them", ":\n    ", detail,
              call. = FALSE)
    } else {
      problems <- c(problems, paste0("  ", label, ": ", detail))
    }
  }

  if (length(problems) > 0) {
    stop("Subsetting values that match nothing in the data:\n",
         paste(problems, collapse = "\n"),
         "\nCorrect the subsetting configuration, or clear a field to include ",
         "everything.",
         call. = FALSE)
  }

  invisible(TRUE)
}

#' Validate the Number of Regions per PET Measurement
#'
#' @description Nested models fit all regions of a PET measurement jointly with
#'   shared parameters, so a measurement with a single region cannot be fitted:
#'   there is nothing to share across. This check summarises how many regions
#'   each measurement carries, warns about measurements that fall below the
#'   minimum (so the caller can drop them), and errors if no measurement
#'   reaches the minimum.
#'
#' @param data A data frame with `pet` and `region` columns, one row per
#'   (measurement, region) or per (measurement, region, frame).
#' @param min_regions Minimum number of distinct regions a measurement needs.
#'   Default is 2.
#' @return A tibble with columns `pet`, `n_regions` and `sufficient`. Errors if
#'   no measurement has at least `min_regions` regions; warns (naming the
#'   measurements) if some do not.
#' @export
validate_min_regions_per_pet <- function(data, min_regions = 2) {
  if (!all(c("pet", "region") %in% colnames(data))) {
    stop("data must contain 'pet' and 'region' columns.", call. = FALSE)
  }

  region_counts <- data %>%
    dplyr::distinct(pet, region) %>%
    dplyr::count(pet, name = "n_regions") %>%
    dplyr::mutate(sufficient = n_regions >= min_regions)

  if (!any(region_counts$sufficient)) {
    stop("Nested models require at least ", min_regions, " regions per PET ",
         "measurement, but no measurement has that many after subsetting. ",
         "Check the Regions field of the Subsetting configuration.",
         call. = FALSE)
  }

  insufficient <- dplyr::filter(region_counts, !sufficient)
  if (nrow(insufficient) > 0) {
    warning("Excluding ",
            nrow(insufficient),
            " PET measurement(s) with fewer than ", min_regions,
            " regions from the nested fit: ",
            paste0(insufficient$pet, " (", insufficient$n_regions,
                   " region(s))", collapse = ", "),
            call. = FALSE)
  }

  region_counts
}

#' Coerce Parameter Bounds to Numeric
#'
#' @description Recursively convert 'start', 'lower', and 'upper' values to numeric
#' in a config list. This fixes the jsonlite integer coercion issue where whole
#' numbers like 5 become integer class instead of numeric, causing minpack.lm to fail.
#' Only targets bound-related fields, preserving integer values for other fields
#' like multstart_iter.
#'
#' @param x A list, vector, or atomic value from JSON config
#' @return The same structure with start/lower/upper values converted to numeric
#' @export
coerce_bounds_numeric <- function(x) {
  if (is.list(x)) {
    # Check for named lists with start/lower/upper keys
    if (!is.null(names(x))) {
      bound_keys <- c("start", "lower", "upper")
      for (key in bound_keys) {
        if (key %in% names(x) && is.numeric(x[[key]])) {
          x[[key]] <- as.numeric(x[[key]])
        }
      }
    }
    # Recurse into all list elements
    lapply(x, coerce_bounds_numeric)
  } else {
    x
  }
}