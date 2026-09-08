#' Copy an Externally Supplied File Into Its Canonical Location
#'
#' @description Copy a user-supplied configuration or regions file into the
#'   location where petfit expects to find it, describing clearly what was
#'   copied and whether an existing file was overwritten. Copying (rather than
#'   reading the external file in place) keeps the derivative self-contained:
#'   the config which drove a run always sits beside that run's outputs.
#'
#'   Any file already at the destination is backed up to a temporary file first.
#'   While nothing has yet been run against the new file, a caller which fails
#'   can hand that backup to [restore_external_file()] and leave the analysis as
#'   it found it.
#'
#' @param source_path Path to the external file supplied by the user.
#' @param destination_path Path the file should be copied to.
#' @param label Short human-readable description of the file, used in messages.
#' @return A list with `messages` (character vector describing what happened),
#'   `destination` (the resolved destination), and `backup` (path to the backup
#'   of the replaced file, or `NULL` if there was nothing to replace).
#' @keywords internal
install_external_file <- function(source_path, destination_path, label = "file") {

  if (!file.exists(source_path)) {
    stop("External ", label, " does not exist: ", source_path, call. = FALSE)
  }

  if (dir.exists(source_path)) {
    stop("External ", label, " is a directory, not a file: ", source_path, call. = FALSE)
  }

  source_norm <- normalizePath(source_path, mustWork = TRUE)
  destination_norm <- normalizePath(destination_path, mustWork = FALSE)

  messages <- c(
    paste0("=== External ", label, " ==="),
    paste("  Source:     ", source_norm)
  )

  if (identical(source_norm, destination_norm)) {
    messages <- c(
      messages,
      paste("  Destination:", destination_norm),
      "  Source and destination are the same file: nothing copied."
    )
    return(list(messages = messages, destination = destination_norm, backup = NULL))
  }

  destination_dir <- dirname(destination_norm)
  if (!dir.exists(destination_dir)) {
    dir.create(destination_dir, recursive = TRUE)
    messages <- c(messages, paste("  Created folder:", destination_dir))
  }

  # Keep whatever is being replaced, so a caller which fails before running
  # anything against the new file can put the old one back.
  backup <- NULL
  if (file.exists(destination_norm)) {
    backup <- tempfile(
      pattern = paste0("petfit_replaced_", basename(destination_norm), "_")
    )
    if (!file.copy(destination_norm, backup, overwrite = TRUE)) {
      stop("Could not back up the ", label, " being replaced: ", destination_norm,
           call. = FALSE)
    }
  }

  if (!file.copy(source_norm, destination_norm, overwrite = TRUE)) {
    # The copy failed partway; put back what was there before giving up.
    if (!is.null(backup)) {
      file.copy(backup, destination_norm, overwrite = TRUE)
    }
    stop("Could not copy external ", label, " to: ", destination_norm, call. = FALSE)
  }

  messages <- c(messages, paste("  Copied to:  ", destination_norm))

  if (!is.null(backup)) {
    messages <- c(
      messages,
      paste0("  NOTE: this REPLACED the ", label, " already in that folder.")
    )
  }

  list(messages = messages, destination = destination_norm, backup = backup)
}


#' Put Back the File an External File Replaced
#'
#' @description Restore the backup taken by [install_external_file()]. Callers
#'   use this when they fail before anything has been run against the newly
#'   installed file, so that a rejected run does not cost the user a working
#'   config or regions file.
#'
#' @param install The list returned by [install_external_file()].
#' @param label Short human-readable description of the file, used in messages.
#' @return Character vector of messages describing what was restored.
#' @keywords internal
restore_external_file <- function(install, label = "file") {

  if (is.null(install) || is.null(install$backup)) {
    # Nothing was replaced, so the destination is the caller's own new file.
    if (!is.null(install) && !is.null(install$destination) &&
        file.exists(install$destination)) {
      unlink(install$destination)
      return(paste0("  Removed the external ", label, " again: ", install$destination))
    }
    return(character())
  }

  if (!file.copy(install$backup, install$destination, overwrite = TRUE)) {
    return(paste0(
      "  WARNING: could not restore the previous ", label, ". A copy of it is at: ",
      install$backup
    ))
  }

  paste0("  Restored the previous ", label, ": ", install$destination)
}


#' Config Type Expected for a Pipeline Type
#'
#' @description Translate a pipeline type (`"plasma"` / `"reference"`, as the
#'   container passes it from `--func`) into the `modelling_configuration_type`
#'   a config must declare to belong to it.
#'
#' @param pipeline_type `"plasma"`, `"reference"`, or `NULL`.
#' @return The expected config type, or `NULL` when the pipeline type does not
#'   constrain it.
#' @keywords internal
config_type_for_pipeline <- function(pipeline_type) {
  if (is.null(pipeline_type)) {
    return(NULL)
  }

  switch(pipeline_type,
    plasma = "plasma input",
    reference = "reference tissue",
    NULL
  )
}


#' Check an External Modelling Config Before Installing It
#'
#' @description Confirm that a user-supplied config file is readable JSON, that
#'   it carries the sections the pipeline needs, and that it was written for the
#'   expected modelling type, so that a broken or mismatched file is rejected
#'   before it replaces the config already in the analysis folder.
#'
#'   The type check matters because the pipeline type given to
#'   [petfit_modelling_auto()] takes priority over the config's own declaration
#'   (see [determine_pipeline_type()]). Without this check, a reference tissue
#'   config handed to the plasma app would replace the analysis config and then
#'   start running plasma steps against it.
#'
#' @param config_file Path to the external config file.
#' @param expected_type Expected value of `modelling_configuration_type`
#'   (e.g. `"plasma input"`), or `NULL` to skip the type check.
#' @return The parsed configuration, invisibly.
#' @keywords internal
check_external_config <- function(config_file, expected_type = NULL) {

  if (!file.exists(config_file)) {
    stop("External config file does not exist: ", config_file, call. = FALSE)
  }

  config <- tryCatch(
    jsonlite::fromJSON(config_file),
    error = function(e) {
      stop("External config file is not valid JSON: ", config_file,
           "\n  ", conditionMessage(e), call. = FALSE)
    }
  )

  if (!is.list(config)) {
    stop("External config file does not contain a JSON object: ", config_file,
         call. = FALSE)
  }

  required_sections <- c("Subsetting", "Models")
  missing_sections <- required_sections[
    !purrr::map_lgl(required_sections, ~ !is.null(config[[.x]]))
  ]

  if (length(missing_sections) > 0) {
    stop("External config file is missing required section(s): ",
         paste(missing_sections, collapse = ", "),
         "\n  It does not look like a petfit configuration: ", config_file,
         call. = FALSE)
  }

  config_type <- config$modelling_configuration_type

  if (!is.null(expected_type)) {
    if (is.null(config_type)) {
      stop("External config file does not declare modelling_configuration_type, ",
           "so it cannot be confirmed to be a ", expected_type, " configuration: ",
           config_file, call. = FALSE)
    }

    if (!identical(config_type, expected_type)) {
      stop("External config file is for ", config_type, " modelling, but this run ",
           "expects ", expected_type, " modelling: ", config_file, call. = FALSE)
    }
  }

  invisible(config)
}


#' Check an External Regions File Before Installing It
#'
#' @description Confirm that a user-supplied `petfit_regions.tsv` is readable,
#'   carries the columns the region definition pipeline needs, defines at least
#'   one region, and names folders which exist in the derivatives directory, so
#'   that a file which cannot produce any TACs is rejected before it replaces
#'   the regions file already in place.
#'
#' @param regions_file Path to the external regions file.
#' @param derivatives_dir Derivatives directory the `folder` column is resolved
#'   against, or `NULL` to skip that check (as when no derivatives are available
#'   yet).
#' @return The parsed regions table, invisibly.
#' @keywords internal
check_external_regions_file <- function(regions_file, derivatives_dir = NULL) {

  if (!file.exists(regions_file)) {
    stop("External regions file does not exist: ", regions_file, call. = FALSE)
  }

  regions <- tryCatch(
    readr::read_tsv(regions_file, show_col_types = FALSE),
    error = function(e) {
      stop("External regions file could not be read as TSV: ", regions_file,
           "\n  ", conditionMessage(e), call. = FALSE)
    }
  )

  required_columns <- c("RegionName", "folder", "description", "ConstituentRegion")
  missing_columns <- setdiff(required_columns, names(regions))

  if (length(missing_columns) > 0) {
    stop("External regions file is missing required column(s): ",
         paste(missing_columns, collapse = ", "), "\n  File: ", regions_file,
         call. = FALSE)
  }

  # create_petfit_regions_files() rejects an empty table, so catch it here
  # rather than after the existing regions file has been replaced.
  if (nrow(regions) == 0) {
    stop("External regions file defines no regions: ", regions_file, call. = FALSE)
  }

  if (!is.null(derivatives_dir)) {
    named_folders <- unique(stats::na.omit(regions$folder))

    if (length(named_folders) == 0) {
      stop("External regions file names no folders in its `folder` column: ",
           regions_file, call. = FALSE)
    }

    present <- purrr::map_lgl(named_folders, ~ dir.exists(file.path(derivatives_dir, .x)))

    if (!any(present)) {
      stop("External regions file names no folder which exists in the derivatives ",
           "directory, so it can produce no TACs.\n  Derivatives: ", derivatives_dir,
           "\n  Folders named: ", paste(named_folders, collapse = ", "),
           "\n  File: ", regions_file, call. = FALSE)
    }
  }

  invisible(regions)
}
