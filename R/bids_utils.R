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
      bidsdata <- bidsdata[,which(!apply(bidsdata, 2,
                                         FUN = function(x) length(unique(x))==1))]
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

#' Get PET identifiers from file paths using unified BIDS parsing
#'
#' @param file_paths Vector of file paths
#' @param analysis_folder Path to analysis folder
#'
#' @returns Vector of PET identifiers matching the file paths
#' @export
#'
#' @examples
#' \dontrun{
#' tacs_files <- list.files("analysis/", pattern = "*_tacs.tsv", recursive = TRUE)
#' pet_ids <- get_pet_identifiers(tacs_files, "analysis/")
#' }
get_pet_identifiers <- function(file_paths, analysis_folder) {
  if (length(file_paths) == 0) {
    return(character(0))
  }
  
  # Use kinfitr to parse the file structure and get standardized pet IDs
  bidsdata <- kinfitr::bids_parse_files(analysis_folder)
  pet_ids <- attributes_to_title(bidsdata)
  
  # Extract pet identifiers from filenames by removing suffix patterns
  file_pet_ids <- stringr::str_remove(basename(file_paths), "_desc-.*$")
  
  # Return matching pet IDs in same order as input files
  result <- character(length(file_paths))
  for (i in seq_along(file_paths)) {
    file_pet_id <- file_pet_ids[i]
    match_idx <- which(pet_ids == file_pet_id)
    if (length(match_idx) > 0) {
      result[i] <- pet_ids[match_idx[1]]
    }
  }
  
  return(result)
}