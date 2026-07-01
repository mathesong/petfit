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

normalize_bids_join_entities <- function(data, entity_cols) {
  data %>%
    dplyr::mutate(
      dplyr::across(
        dplyr::all_of(entity_cols),
        ~{
          value <- as.character(.x)
          value[trimws(value) %in% c("", "NA", "N/A", "n/a", "<NA>")] <- NA_character_
          value
        }
      )
    )
}

#' Join BIDS tables with hierarchical matching for missing right-hand entities
#'
#' @description
#' Joins a PET-level table (`x`) to an ancillary table (`y`) while allowing
#' missing entities in `y` to match more specific rows in `x`. This supports
#' common BIDS layouts such as run-specific PET files with a session-level blood
#' file that has no `run` entity. If a parser has expanded a generic file into
#' specific entity rows, missing entities in `x` can also fall back to those
#' specific rows, while true generic matches are preferred.
#'
#' @param x Left table, usually PET TAC data.
#' @param y Right table, usually blood/input-function data.
#' @param entity_cols BIDS entity columns to use for matching.
#'
#' @return A tibble with one best matching `y` row per matched `x` row.
#' @export
bids_hierarchical_inner_join <- function(x, y,
                                         entity_cols = c("sub", "ses", "trc",
                                                         "rec", "task", "run")) {
  x <- tibble::as_tibble(x)
  y <- tibble::as_tibble(y)

  common_entities <- intersect(entity_cols, intersect(colnames(x), colnames(y)))
  if (length(common_entities) == 0) {
    stop("No common BIDS entity columns found for hierarchical join")
  }

  if (nrow(x) == 0 || nrow(y) == 0) {
    return(dplyr::inner_join(x, y, by = common_entities))
  }

  original_x_cols <- colnames(x)

  x <- normalize_bids_join_entities(x, common_entities) %>%
    dplyr::mutate(.petfit_join_x_id = dplyr::row_number())
  y <- normalize_bids_join_entities(y, common_entities) %>%
    dplyr::mutate(.petfit_join_y_id = dplyr::row_number())

  # Columns that are always present on both sides can be joined exactly up
  # front. Columns with missing values on either side are filtered afterwards
  # so generic rows and parser-expanded rows can still match.
  exact_join_cols <- common_entities[
    purrr::map_lgl(common_entities, ~ all(!is.na(x[[.x]])) && all(!is.na(y[[.x]])))
  ]

  joined <- dplyr::inner_join(
    x,
    y,
    by = exact_join_cols,
    suffix = c(".x", ".y"),
    relationship = "many-to-many"
  )

  wildcard_cols <- setdiff(common_entities, exact_join_cols)
  for (entity in wildcard_cols) {
    x_col <- paste0(entity, ".x")
    y_col <- paste0(entity, ".y")
    keep <- is.na(joined[[y_col]]) |
      is.na(joined[[x_col]]) |
      joined[[x_col]] == joined[[y_col]]
    joined <- joined[keep %in% TRUE, , drop = FALSE]
  }

  if (nrow(joined) == 0) {
    return(joined %>%
             dplyr::select(-dplyr::any_of(c(".petfit_join_x_id",
                                            ".petfit_join_y_id"))))
  }

  joined$.petfit_join_score <- length(exact_join_cols) * 2L

  for (entity in wildcard_cols) {
    x_col <- paste0(entity, ".x")
    y_col <- paste0(entity, ".y")
    joined$.petfit_join_score <- joined$.petfit_join_score +
      dplyr::case_when(
        !is.na(joined[[x_col]]) & !is.na(joined[[y_col]]) & joined[[x_col]] == joined[[y_col]] ~ 2L,
        is.na(joined[[y_col]]) ~ 1L,
        is.na(joined[[x_col]]) & !is.na(joined[[y_col]]) ~ 0L,
        TRUE ~ -1000L
      )
  }

  joined <- joined %>%
    dplyr::arrange(.petfit_join_x_id,
                   dplyr::desc(.petfit_join_score),
                   .petfit_join_y_id) %>%
    dplyr::group_by(.petfit_join_x_id) %>%
    dplyr::slice(1) %>%
    dplyr::ungroup()

  # Preserve x's entity columns in the output. dplyr suffixes non-exact join
  # columns, but downstream reports expect the PET-side names (e.g. `run`).
  for (entity in wildcard_cols) {
    x_col <- paste0(entity, ".x")
    if (x_col %in% colnames(joined)) {
      joined[[entity]] <- joined[[x_col]]
    }
  }

  joined %>%
    dplyr::select(
      dplyr::any_of(original_x_cols),
      dplyr::everything(),
      -dplyr::any_of(c(".petfit_join_x_id",
                       ".petfit_join_y_id",
                       ".petfit_join_score",
                       paste0(wildcard_cols, ".x"),
                       paste0(wildcard_cols, ".y")))
    )
}
