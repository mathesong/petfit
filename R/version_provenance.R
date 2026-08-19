#' Record and Check Which Version of petfit Produced Something
#'
#' @description Helpers for stamping the running version onto the files petfit
#'   writes, and for warning when a later step meets a file an older version
#'   wrote.
#'
#'   The reason is concrete. A measurement's identifier -- the `pet` column, and
#'   the filename stem built from it -- used to be derived from whichever BIDS
#'   entities happened to vary across the cohort, so it moved when the cohort
#'   changed. It is now built from each measurement's own entities. A
#'   `desc-combinedregions_tacs.tsv` written before that change carries the old
#'   identifiers, and a step that constructs the new ones from the same file's
#'   path will not match them. Nothing about the older file looks wrong; it
#'   simply disagrees.
#'
#'   The remedy is always the same -- re-run every step, region definition
#'   included, with the current version -- so these functions warn and say so
#'   rather than stopping.
#'
#' @name petfit_version_provenance
NULL

#' @describeIn petfit_version_provenance The `GeneratedBy` entry to write into a
#'   sidecar, following the BIDS field of the same name.
#' @return For `petfit_generated_by()`, a list with `Name` and `Version`.
#' @export
petfit_generated_by <- function() {
  list(Name = "petfit", Version = as.character(utils::packageVersion("petfit")))
}

# Pull a version out of whatever shape the provenance takes: a bare
# `petfit_version` string, or a BIDS `GeneratedBy` array whose petfit entry
# carries it. Returns NA_character_ when there is nothing to find.
petfit_recorded_version <- function(x) {

  if (is.null(x)) return(NA_character_)

  if (!is.null(x$petfit_version)) {
    return(as.character(x$petfit_version)[1])
  }

  generated <- x$GeneratedBy
  if (is.null(generated)) return(NA_character_)

  # jsonlite gives a list of lists, or a data frame when the entries are uniform
  if (is.data.frame(generated)) {
    row <- generated[tolower(generated$Name) == "petfit", , drop = FALSE]
    if (nrow(row) > 0 && !is.null(row$Version)) return(as.character(row$Version)[1])
    return(NA_character_)
  }

  if (!is.null(generated$Name)) generated <- list(generated)
  for (entry in generated) {
    if (!is.null(entry$Name) && tolower(entry$Name) == "petfit" &&
        !is.null(entry$Version)) {
      return(as.character(entry$Version)[1])
    }
  }

  NA_character_
}

#' @describeIn petfit_version_provenance Warn if `provenance` was written by an
#'   older petfit than the one running, or records no version at all.
#'
#' @param provenance A parsed configuration or sidecar, as a list.
#' @param what Short description of the file, used in the message.
#' @param notify Notification callback taking `(message, type)`.
#'
#' @return For `petfit_check_version()`, invisibly `TRUE` when the version is
#'   current and `FALSE` when it is older or absent.
#' @export
petfit_check_version <- function(provenance, what,
                                 notify = function(msg, type) {}) {

  current <- utils::packageVersion("petfit")
  recorded <- petfit_recorded_version(provenance)

  advice <- paste0(
    "It is recommended to re-run all steps of this analysis with the current version, region ",
    "definition included, so that all of its files agree with each other.")

  if (is.na(recorded)) {
    msg <- paste0(
      "The ", what, " does not record which version of petfit created it, so ",
      "it predates petfit ", current, ". ", advice)
    warning(msg, call. = FALSE)
    notify(msg, "warning")
    return(invisible(FALSE))
  }

  recorded_version <- tryCatch(package_version(recorded), error = function(e) NULL)
  if (is.null(recorded_version)) {
    msg <- paste0(
      "The ", what, " records an unreadable petfit version (\"", recorded,
      "\"). ", advice)
    warning(msg, call. = FALSE)
    notify(msg, "warning")
    return(invisible(FALSE))
  }

  if (recorded_version < current) {
    msg <- paste0(
      "The ", what, " was created with petfit ", recorded_version,
      ", older than the ", current, " now running. ", advice)
    warning(msg, call. = FALSE)
    notify(msg, "warning")
    return(invisible(FALSE))
  }

  invisible(TRUE)
}

#' @describeIn petfit_version_provenance Check the sidecar beside a combined
#'   TACs file, if there is one. Silent when the file has no sidecar to check.
#'
#' @param combined_tacs_file Path to `desc-combinedregions_tacs.tsv`.
#' @export
petfit_check_combined_tacs_version <- function(combined_tacs_file,
                                              notify = function(msg, type) {}) {

  sidecar <- sub("\\.tsv$", ".json", combined_tacs_file)
  if (!file.exists(sidecar)) {
    return(invisible(TRUE))
  }

  provenance <- tryCatch(jsonlite::fromJSON(sidecar), error = function(e) NULL)
  if (is.null(provenance)) {
    return(invisible(TRUE))
  }

  petfit_check_version(provenance, "combined regions TACs file", notify)
}
