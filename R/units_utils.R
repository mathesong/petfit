#' Units of the TAC data in an analysis
#'
#' @description
#' Reads the units of the combined regions TACs, which the region definition
#' step records in `desc-combinedregions_tacs.json` alongside the file it
#' describes. Every later step works from those TACs, so this is where the units
#' of every derived TAC come from: the reference TAC, the target region TACs and
#' the fitted values a model writes back out.
#'
#' The region definition step converts every TAC to kBq as it combines them,
#' whatever the source data used, and the data definition step converts any
#' analysis whose TACs are not already kBq — writing a sidecar of its own beside
#' the converted copies — so in practice the answer is `"kBq/mL"`. It is read
#' rather than assumed so that the sidecars cannot claim units the data does not
#' have.
#'
#' Note that the frame times are **not** the same throughout. The TAC files
#' record them in seconds, as BIDS does, while the models are fitted in minutes
#' and write their fitted values back out in minutes. Each sidecar states which
#' it is; `time` here is the units of the TAC files.
#'
#' @param analysis_folder Path to the analysis folder. The analysis's own
#'   sidecar is preferred where it exists, since it describes the copies of the
#'   TACs this analysis actually reads; otherwise the shared one, one level
#'   above next to the combined regions TACs, is used.
#'
#' @return A list with `radioactivity` (e.g. `"kBq/mL"`) and `time` (e.g.
#'   `"s"`). Where the sidecar is missing or unreadable, the defaults the region
#'   definition step writes are returned.
#'
#' @export
petfit_tac_units <- function(analysis_folder) {
  # The analysis's own sidecar wins: where the data definition step converted
  # these copies to kBq, it is the only record of that, and the shared one still
  # describes the units the TACs were combined in.
  sidecar <- file.path(analysis_folder, "desc-combinedregions_tacs.json")
  if (!file.exists(sidecar)) {
    sidecar <- file.path(dirname(analysis_folder), "desc-combinedregions_tacs.json")
  }

  radioactivity <- NULL
  time <- NULL

  if (file.exists(sidecar)) {
    meta <- tryCatch(jsonlite::fromJSON(sidecar), error = function(e) NULL)
    # `radioactivity` and `time` are written for exactly this purpose; the TAC
    # column carries the same units and is the fallback if an older sidecar
    # lacks them.
    radioactivity <- meta$radioactivity$Units %||% meta$TAC$Units
    time <- meta$time$Units %||% meta$frame_mid$Units
  }

  list(
    radioactivity = radioactivity %||% "kBq/mL",
    time = time %||% "s"
  )
}

#' Convert an analysis's TACs to kBq, once
#'
#' @description
#' petfit works in kBq throughout. The region definition step converts every TAC
#' as it combines them, so an analysis built by the current version has nothing
#' to do here; TACs written by an older petfit, or brought in from elsewhere, are
#' converted by this function instead — once, in the analysis's own copies of the
#' files, so that every later step reads kBq rather than each of them having to
#' convert again.
#'
#' What it did is recorded in a sidecar beside those copies, rather than in the
#' shared one above the analysis folder: the shared file describes other
#' analyses' copies too, which have not been touched. That sidecar is also what
#' stops a second run from converting the same files a second time, which would
#' scale them by a further thousand.
#'
#' @param analysis_folder Path to the analysis folder.
#' @param tacs_files Paths of the analysis's combined regions TACs files,
#'   relative to `analysis_folder`.
#'
#' @return Invisibly, a list with `from_units` (the units the files were in),
#'   `converted` (whether anything was rewritten) and `message`, a sentence for
#'   the report to print. When `converted` is `TRUE`, the caller's own copy of
#'   the data still needs converting from `from_units`.
#'
#' @export
standardise_analysis_tac_units <- function(analysis_folder, tacs_files) {
  analysis_sidecar <- file.path(analysis_folder, "desc-combinedregions_tacs.json")
  shared_sidecar <- file.path(dirname(analysis_folder),
                              "desc-combinedregions_tacs.json")
  sidecar_path <- if (file.exists(analysis_sidecar)) {
    analysis_sidecar
  } else {
    shared_sidecar
  }

  unchanged <- function(message) {
    invisible(list(from_units = "kBq", converted = FALSE, message = message))
  }

  if (!file.exists(sidecar_path)) {
    return(unchanged("Combined TACs JSON not found, assuming TAC values already in kBq"))
  }

  meta <- tryCatch(jsonlite::fromJSON(sidecar_path), error = function(e) NULL)
  if (is.null(meta)) {
    return(unchanged("Combined TACs JSON could not be read, assuming TAC values already in kBq"))
  }

  recorded <- meta$radioactivity$Units %||% meta$TAC$Units
  if (is.null(recorded)) {
    return(unchanged("No radioactivity units found in JSON metadata, assuming already in kBq"))
  }

  from_units <- kinfitr::get_units_radioactivity(recorded)$rad
  if (identical(from_units, "kBq")) {
    return(unchanged(paste("TAC units from combined regions JSON:", recorded)))
  }

  to_kBq <- function(x) {
    kinfitr::unit_convert(x, from_units = from_units, to_units = "kBq")
  }

  purrr::walk(tacs_files, function(relative_path) {
    tac_path <- file.path(analysis_folder, relative_path)
    tacs <- readr::read_tsv(tac_path, show_col_types = FALSE)
    tacs <- dplyr::mutate(tacs,
                          dplyr::across(dplyr::any_of(c("TAC", "seg_meanTAC")),
                                        to_kBq))
    readr::write_tsv(tacs, tac_path)
  })

  meta$radioactivity <- list(Units = "kBq/mL")
  if (!is.null(meta$TAC)) meta$TAC$Units <- "kBq/mL"
  if (!is.null(meta$seg_meanTAC)) meta$seg_meanTAC$Units <- "kBq/mL"
  jsonlite::write_json(meta, analysis_sidecar, pretty = TRUE, auto_unbox = TRUE)

  invisible(list(
    from_units = from_units,
    converted = TRUE,
    message = paste0("Converted ", length(tacs_files), " TACs files from ",
                     from_units, " to kBq, and recorded kBq/mL in ",
                     basename(analysis_sidecar))
  ))
}

# The units of every column petfit writes, in one table, so that the reports
# cannot disagree with each other about what a column holds. A column which
# carries no quantity at all — a region name, a fit statistic — is absent, and
# is then described without units rather than given a made-up one. An outcome
# which is genuinely dimensionless is not the same thing: it says so, so that a
# consumer can tell "no units" from "units not stated".
#
# `radioactivity_units` is the concentration the TACs are in, and `time_units`
# the time base of the file being described: the TAC files record seconds, while
# the models are fitted, and write their fitted values, in minutes.
.petfit_column_units <- function(column, radioactivity_units, time_units) {
  # A distribution volume is a tissue concentration over a plasma concentration,
  # so the radioactivity cancels and a volume ratio is what remains.
  volume_ratio <- "mL/cm^3"
  influx <- paste0(volume_ratio, "/", time_units)
  rate <- paste0("1/", time_units)

  # The conventional SUV: a concentration in kBq/mL over a dose in kBq per gram
  # of body mass. suv_denominator() converts the recorded body weight from kg to
  # g for exactly this reason. These two are not parameterised on
  # radioactivity_units, unlike everything else here, because both the dose and
  # the TACs are standardised to kBq before any model sees them — the region
  # definition step converts the TACs it writes, and the data definition step
  # converts an analysis whose TACs arrived in anything else.
  suv <- "g/mL"

  # A ratio of two like quantities, whose units cancel. Stated rather than left
  # out, so that a column which has no units is distinguishable from one whose
  # units nobody worked out.
  unitless <- "unitless"

  # A part of a whole, reported as a percentage once multiplied by 100.
  fraction <- "fraction"

  # kinfitr reports a standard error as |SE / estimate|, a coefficient of
  # variation, so whatever a parameter's own units its error is a fraction of
  # it. The kinpar files name these columns `-se`; the reports carry them as
  # `.se` until they are written.
  if (grepl("[.-]se$", column)) {
    return(fraction)
  }

  known <- list(
    # Measured and fitted radioactivity concentrations
    TAC              = radioactivity_units,
    TAC_fitted       = radioactivity_units,
    Target           = radioactivity_units,
    Target_fitted    = radioactivity_units,
    Reference        = radioactivity_units,
    Reference_fitted = radioactivity_units,
    RefTAC           = radioactivity_units,
    RefTAC_original  = radioactivity_units,
    seg_meanTAC      = radioactivity_units,

    # Frame timings and other times
    frame_start      = time_units,
    frame_end        = time_units,
    frame_dur        = time_units,
    frame_mid        = time_units,
    Time             = time_units,
    Duration         = time_units,
    t0               = time_units,
    tstar            = time_units,
    inpshift         = time_units,
    blood_timeshift  = time_units,
    window_start     = time_units,
    window_end       = time_units,
    window_duration  = time_units,

    # The Logan transformations divide an integrated concentration by a
    # concentration, so both of their axes are times. Patlak does that only on
    # its x axis; its y axis is a tissue-to-plasma ratio, i.e. a volume ratio.
    Logan_x          = time_units,
    Logan_y          = time_units,
    Logan_fitted     = time_units,
    refLogan_x       = time_units,
    refLogan_y       = time_units,
    refLogan_fitted  = time_units,
    Patlak_x         = time_units,
    Patlak_y         = volume_ratio,
    Patlak_fitted    = volume_ratio,

    # Kinetic parameters
    K1               = influx,
    Ki               = influx,
    k2               = rate,
    k3               = rate,
    k4               = rate,
    k2a              = rate,
    k2prime          = rate,
    VT               = volume_ratio,
    Vnd              = volume_ratio,
    BPp              = volume_ratio,
    BPnd             = unitless,
    R1               = unitless,
    SUVR             = unitless,

    # The blood volume of the tissue over its total volume.
    vB               = fraction,

    # SUV outcomes
    SUV              = suv,
    SUV_ref          = suv,
    SUV_AUC          = paste0("g*", time_units, "/mL"),
    SUV_ref_AUC      = paste0("g*", time_units, "/mL"),
    SUV_denominator  = "kBq/g"
  )

  known[[column]]
}

#' Attach BIDS units to a set of column descriptions
#'
#' @description
#' Turns a named list of plain column descriptions into the BIDS data dictionary
#' form, in which each column maps to an object carrying a `Description` and,
#' where the column has them, `Units`.
#'
#' @param descriptions Named list (or character vector) of column name to
#'   description.
#' @param radioactivity_units Units of the radioactivity concentration columns,
#'   from [petfit_tac_units()].
#' @param time_units Units of the time columns in *this* file. The TAC files
#'   record seconds; a model's fitted values are written in minutes, which is
#'   what the models are fitted in.
#'
#' @return A named list suitable for writing as a JSON sidecar, one entry per
#'   column, in the order given.
#'
#' @export
bids_column_units <- function(descriptions, radioactivity_units = "kBq/mL",
                              time_units = "min") {
  descriptions <- as.list(descriptions)

  purrr::imap(descriptions, function(description, column) {
    entry <- list(Description = description)
    units <- .petfit_column_units(column, radioactivity_units, time_units)
    if (!is.null(units)) entry$Units <- units
    entry
  })
}

#' Units of the kinetic parameters a model reports
#'
#' @description
#' The units of the outcome parameters present in a kinpar table, derived from
#' the units of the TACs the model was fitted to and the minutes it was fitted
#' in. Parameters which are ratios of like quantities — `BPnd`, `R1`, `SUVR` —
#' say so, as `"unitless"`, and `vB` is a `"fraction"`: the blood volume of the
#' tissue over its total volume, which is what is reported as a percentage when
#' multiplied by 100. The standard errors are `"fraction"` too, whatever the
#' parameter they belong to: kinfitr reports them as `|SE / estimate|`. The
#' goodness-of-fit columns carry no quantity and are given no entry at all.
#'
#' See [petfit_tac_units()] for where the radioactivity units come from. `SUV`
#' is the conventional g/mL: the dose is standardised to kBq and
#' [suv_denominator()] converts the body weight to grams.
#'
#' @param columns Character vector of the columns present in the kinpar table.
#' @param radioactivity_units Units of the radioactivity concentration, from
#'   [petfit_tac_units()].
#' @param time_units Units of time in the fitted model. Always minutes.
#'
#' @return A named list of `list(Units = ...)`, holding only those columns which
#'   have units.
#'
#' @export
kinpar_units <- function(columns, radioactivity_units = "kBq/mL",
                         time_units = "min") {
  units <- purrr::map(stats::setNames(columns, columns),
                      ~.petfit_column_units(.x, radioactivity_units, time_units))
  units <- purrr::compact(units)

  purrr::map(units, ~list(Units = .x))
}
