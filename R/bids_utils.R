#' Extract a pet variable from BIDS attributes
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
#'   The key must not depend on which other measurements happen to be analysed
#'   alongside it. The identifier this replaces was built from only the
#'   attributes that *varied* across the current cohort, so three subjects all in
#'   `ses-test` were identified as `sub-01`, `sub-02`, `sub-03`, and adding one
#'   retest scan silently renamed every one of them to `sub-01_ses-test` and so
#'   on. Previously written files were orphaned, saved configurations referred to
#'   measurements that no longer existed, and an analysis containing a single
#'   measurement produced a key matching no file at all -- which is what left the
#'   PET dropdown empty.
#'
#'   Because the key is exactly the stem its files are written under, reading it
#'   back is not a lookup and so cannot fail.
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
    root <- normalizePath(analysis_folder, mustWork = FALSE)
    relative <- sub(paste0("^", stringr::fixed(root), "/?"), "",
                    normalizePath(file_paths, mustWork = FALSE))
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