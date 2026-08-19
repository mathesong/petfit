#' Extract a pet variable from BIDS attributes
#'
#' @description Deprecated. Use [pet_key()] for identity
#'   and [pet_label()] for display.
#'
#'   This builds an identifier from only the attributes that vary across the
#'   data it is handed, so identity depends on the cohort: adding a scan renames
#'   the existing measurements, and a single measurement is named in a way that
#'   matches none of its own files.
#'
#' @param bidsdata The result of bids_parse_files()
#' @param all_attributes Make a column including attributes which are all the same.
#'
#' @returns A vector of pet measurement identifiers specific to each PET.
#' @export
#'
#' @examples
#' \dontrun{
#' studydata <- bids_parse_files(studypath)
#' studydata$pet <- attributes_to_title(studydata)
#' }
attributes_to_title <- function(bidsdata, all_attributes = FALSE) {

  warning(
    "attributes_to_title() is deprecated in favour of pet_key() for identity ",
    "and pet_label() for display, and will be removed in 2027.\n",
    "It builds an identifier from only the attributes that vary across the ",
    "data it is given, so the same measurement is named differently depending ",
    "on what else is being analysed. Adding one scan to a study renames the ",
    "others and orphans their files, and a study of a single measurement ",
    "produces a name matching no file at all.",
    call. = FALSE)

  
  
  if( !all_attributes ) {
    if(nrow(bidsdata) > 1) {
      # More than one PET measurement
      # Filter out columns where all values are identical, but always keep 'sub'
      cols_to_keep <- apply(bidsdata, 2, FUN = function(x) length(unique(x)) > 1)
      if ("sub" %in% colnames(bidsdata)) {
        cols_to_keep["sub"] <- TRUE  # Always include 'sub'
      }
      bidsdata <- bidsdata[, cols_to_keep, drop = FALSE]
    } else {
      # Situation if only one PET
      bidsdata <- dplyr::select(bidsdata, sub, ses, task, filedata)
    }
  }
  
  cnames <- colnames(bidsdata)
  
  filedata_colno <- which(cnames=="filedata")
  
  cname_attributes <- cnames[1:(filedata_colno-1)]
  attributes <- bidsdata[1:(filedata_colno-1)]
  
  # i for rows --> attributes
  # j for columns --> measurements
  
  title <- rep("", times=nrow(attributes))
  
  for(j in 1:nrow(attributes)) {
    for(i in 1:length(cname_attributes)) {
      title[j] <- paste0(title[j], cname_attributes[i], "-", attributes[j,i], "_")
    }
  }
  
  stringr::str_remove(title, "_$")
  
}

#' Cohort-Invariant Key for a PET Measurement
#'
#' @description Build each measurement's identifier from the entities that
#'   measurement's own path carries, and nothing else.
#'
#'   The key does not depend on which other measurements are analysed alongside
#'   it, so it never moves: a measurement keeps the same key whether it is
#'   analysed alone or in a cohort of fifty, and the files written under it stay
#'   findable when the study grows.
#'
#'   It is exactly the stem its files are written under, so reading it back is
#'   not a lookup and cannot fail. Use [pet_label()] for display.
#'
#' @param file_paths Vector of file paths.
#' @param analysis_folder Path to the analysis folder the paths sit in. Entities
#'   are read relative to it, so directories above it cannot contribute.
#'
#' @returns Character vector of keys, one per path.
#' @export
#'
#' @examples
#' \dontrun{
#' tacs_files <- list.files("analysis/", pattern = "*_tacs.tsv", recursive = TRUE)
#' pet_key(tacs_files, "analysis/")
#' }
pet_key <- function(file_paths, analysis_folder = NULL) {

  if (length(file_paths) == 0) {
    return(character(0))
  }

  relative <- file_paths
  if (!is.null(analysis_folder)) {
    # A literal prefix strip, not a pattern: the folder path is user-chosen
    # text, and characters like "+" or "(" in it must not be read as regex.
    root <- paste0(normalizePath(analysis_folder, mustWork = FALSE), "/")
    normalized <- normalizePath(file_paths, mustWork = FALSE)
    relative <- ifelse(startsWith(normalized, root),
                       substring(normalized, nchar(root) + 1L),
                       normalized)
  }

  selectors <- c("sub", "ses", "task", "trc", "rec", "run")

  vapply(relative, function(path) {

    attributes <- kinfitr::bids_filename_attributes(path)
    present <- selectors[selectors %in% colnames(attributes)]
    if (length(present) > 0) {
      present <- present[!is.na(unlist(attributes[1, present]))]
    }

    if (length(present) == 0) {
      return(NA_character_)
    }

    paste(paste0(present, "-", unlist(attributes[1, present])), collapse = "_")

  }, character(1), USE.NAMES = FALSE)
}

#' Display Label for a PET Measurement
#'
#' @description Shorten a set of keys for display by dropping the entities they
#'   all share.
#'
#'   This is deliberately cohort-dependent, which is safe only because it is
#'   never persisted: labels are shown to a user, while [pet_key()] is what goes
#'   into filenames, joins and saved configurations. Making *identity*
#'   cohort-dependent is what orphaned files whenever a dataset grew.
#'
#' @param keys Character vector of keys, as returned by [pet_key()].
#'
#' @returns Character vector of labels. Never use these as values.
#' @export
#'
#' @examples
#' pet_label(c("sub-01_ses-test", "sub-02_ses-test"))
pet_label <- function(keys) {

  if (length(keys) < 2) {
    return(keys)
  }

  parts <- strsplit(keys, "_", fixed = TRUE)
  shared <- Reduce(intersect, parts)

  vapply(parts, function(p) {
    kept <- setdiff(p, shared)
    if (length(kept) == 0) paste(p, collapse = "_") else paste(kept, collapse = "_")
  }, character(1))
}