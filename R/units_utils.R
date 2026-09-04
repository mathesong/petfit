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
#' whatever the source data used, so in practice the answer is `"kBq/mL"`. It is
#' read rather than assumed so that the sidecars cannot claim units the data
#' does not have.
#'
#' Note that the frame times are **not** the same throughout. The TAC files
#' record them in seconds, as BIDS does, while the models are fitted in minutes
#' and write their fitted values back out in minutes. Each sidecar states which
#' it is; `time` here is the units of the TAC files.
#'
#' @param analysis_folder Path to the analysis folder. The sidecar lives one
#'   level above it, next to the shared combined regions TACs.
#'
#' @return A list with `radioactivity` (e.g. `"kBq/mL"`) and `time` (e.g.
#'   `"s"`). Where the sidecar is missing or unreadable, the defaults the region
#'   definition step writes are returned.
#'
#' @export
petfit_tac_units <- function(analysis_folder) {
  sidecar <- file.path(dirname(analysis_folder), "desc-combinedregions_tacs.json")

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

# The units of every column petfit writes, in one table, so that the reports
# cannot disagree with each other about what a column holds. A column which is
# genuinely dimensionless — a weight, a binding potential, a region name, a
# relative standard error — is absent, and is then described without units
# rather than given a made-up one.
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
  # g for exactly this reason.
  suv <- "g/mL"

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
#' in. Parameters which are ratios — `BPnd`, `R1`, `SUVR`, `vB` — are
#' dimensionless and are given none, as are the standard errors, which every
#' report expresses as a fraction of the estimate, and the goodness-of-fit
#' columns.
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
