#' Parse Semicolon-Separated Values
#'
#' @description Parse a semicolon-separated subsetting string into a vector of
#'   values.
#'
#'   Values are separated by `;` and **may not contain commas**. A comma is
#'   always a mistyped separator, and silently treating `"A, B"` as one value is
#'   what caused analyses to run on fewer regions than were asked for.
#'
#'   A string whose first non-whitespace character is `-` selects everything
#'   *except* the values listed, so `"-test;retest"` means "neither test nor
#'   retest". The `-` applies to the whole field, so including and excluding
#'   cannot be mixed within a single field. Each subsetting field reads its own
#'   prefix independently.
#'
#' @param input_string Character string with semicolon-separated values
#' @param field Optional name of the field being parsed, used to make error and
#'   warning messages specific (e.g. `"Regions"`).
#' @return Character vector of parsed values, or `NULL` if empty. The result
#'   carries a `negate` attribute — `TRUE` when the field was prefixed with `-`,
#'   otherwise `FALSE`. Read it with `attr(x, "negate")`.
#' @export
parse_semicolon_values <- function(input_string, field = NULL) {
  if (is.null(input_string) || length(input_string) == 0) {
    return(NULL)
  }

  input_string <- stringr::str_trim(as.character(input_string)[1])

  if (is.na(input_string) || input_string == "") {
    return(NULL)
  }

  # A leading "-" negates the whole field, not just the first value
  negate <- stringr::str_starts(input_string, stringr::fixed("-"))
  if (negate) {
    input_string <- stringr::str_sub(input_string, 2)
  }

  # Split by semicolon and trim whitespace
  values <- stringr::str_split(input_string, ";")[[1]]
  values <- stringr::str_trim(values)

  # Remove empty values
  values <- values[values != ""]

  if (length(values) == 0) {
    if (negate) {
      warning(subset_field_prefix(field),
              "\"-\" on its own excludes nothing; no filter applied.",
              call. = FALSE)
    }
    return(NULL)
  }

  check_no_commas(values, field)

  attr(values, "negate") <- negate

  return(values)
}

#' Subset Combined TACs Data
#'
#' @description Filter combined TACs data based on subsetting criteria.
#'
#'   Every value is validated first — see [validate_subset_params()]. A value
#'   you asked to include that matches nothing is an error rather than a silent
#'   no-op.
#'
#'   A field parsed from a string prefixed with `-` (see
#'   [parse_semicolon_values()]) excludes its values instead of including them.
#'   Note the asymmetry around missing entities: including `ses = "test"` drops
#'   rows whose session is `NA`, whereas excluding `ses = "-test"` **keeps**
#'   them, since a measurement with no session at all is indeed not `ses-test`.
#'
#' @param combined_tacs_data Tibble with combined TACs data
#' @param subset_params List of subsetting parameters
#' @return Filtered tibble
#' @export
subset_combined_tacs <- function(combined_tacs_data, subset_params) {

  if (is.null(combined_tacs_data) || nrow(combined_tacs_data) == 0) {
    return(tibble::tibble())
  }

  validate_subset_params(combined_tacs_data, subset_params)

  filtered_data <- combined_tacs_data

  # Apply filters for each parameter
  for (field in names(subset_field_columns)) {
    values <- subset_params[[field]]
    if (is.null(values) || length(values) == 0) {
      next
    }

    column <- subset_field_columns[[field]]
    if (!column %in% colnames(filtered_data)) {
      # Only reachable for an exclusion; an inclusion has already errored.
      next
    }

    # as.character() on both sides mirrors what %in% does anyway, and base
    # subsetting keeps NA rows under negation rather than dropping them the way
    # dplyr::filter() would.
    keep <- as.character(filtered_data[[column]]) %in% as.character(values)
    if (isTRUE(attr(values, "negate"))) {
      keep <- !keep
    }

    filtered_data <- filtered_data[keep, , drop = FALSE]
  }

  return(filtered_data)
}

#' Subset TACs by Frame or Time Range
#'
#' @description Filter TAC data to keep only specified frame range or time window
#' @param tacs_data Tibble with TAC data
#' @param subset_type Type of subsetting: "frame", "time", or NULL for no subsetting
#' @param start_point Start frame number or time in minutes
#' @param end_point End frame number or time in minutes
#' @return Filtered tibble with only specified frames
#' @export
subset_tacs_by_frames <- function(tacs_data, subset_type = NULL,
                                  start_point = NULL, end_point = NULL) {

  # If no subsetting specified, return data as-is
  if (is.null(subset_type) || subset_type == "" ||
      is.null(start_point) || is.null(end_point)) {
    return(tacs_data)
  }

  if (is.null(tacs_data) || nrow(tacs_data) == 0) {
    return(tibble::tibble())
  }

  filtered_data <- tacs_data

  if (subset_type == "frame") {
    # Subset by frame number (assuming frames are numbered sequentially)
    # Create frame number column if not exists
    if (!"frame_num" %in% colnames(filtered_data)) {
      filtered_data <- filtered_data %>%
        dplyr::group_by(dplyr::across(dplyr::any_of(c("pet", "region")))) %>%
        dplyr::mutate(frame_num = dplyr::row_number()) %>%
        dplyr::ungroup()
    }

    filtered_data <- filtered_data %>%
      dplyr::filter(frame_num >= start_point & frame_num <= end_point) %>%
      dplyr::select(-dplyr::any_of("frame_num"))

  } else if (subset_type == "time") {
    # Subset by time in minutes using frame midpoint
    # Convert time inputs from minutes to seconds (frame_mid is in seconds)
    start_seconds <- start_point * 60
    end_seconds <- end_point * 60
    filtered_data <- filtered_data %>%
      dplyr::filter(frame_mid >= start_seconds & frame_mid <= end_seconds)
  }

  return(filtered_data)
}

#' Cleanup Individual TACs Files
#'
#' @description Remove existing analysis files before regeneration. Handles
#'   cleanup at multiple levels:
#'   1. Subject folders - removes entire sub-* folders for filtered-out subjects
#'   2. Session folders - removes ses-* folders for filtered-out sessions
#'   3. Individual files - removes files whose pet identifier doesn't match filter
#' @param output_dir Output directory containing individual files
#' @param pattern File pattern to match (default: "*_desc-combinedregions_tacs.tsv")
#' @param keep_subjects Character vector of subject IDs to keep (without "sub-" prefix).
#'   If provided, entire folders for subjects NOT in this list will be removed.
#' @param keep_sessions Character vector of session IDs to keep (without "ses-" prefix).
#'   If provided, session folders NOT in this list will be removed from kept subjects.
#' @param keep_pets Character vector of pet identifiers to keep. If provided,
#'   files whose pet identifier doesn't match will be removed.
#' @return List with counts of removed files and directories
#' @export
cleanup_individual_tacs_files <- function(output_dir,
                                         pattern = "*_desc-combinedregions_tacs.tsv",
                                         keep_subjects = NULL,
                                         keep_sessions = NULL,
                                         keep_pets = NULL) {

  files_removed <- 0
  dirs_removed <- 0

  if (!dir.exists(output_dir)) {
    return(list(files_removed = 0, dirs_removed = 0,
                summary = "Output directory does not exist"))
  }

  # 1. Remove entire folders for subjects NOT in the list
  if (!is.null(keep_subjects)) {
    all_dirs <- list.dirs(output_dir, recursive = FALSE, full.names = TRUE)
    sub_dirs <- all_dirs[grepl("^sub-", basename(all_dirs))]

    keep_folders <- paste0("sub-", keep_subjects)
    dirs_to_remove <- sub_dirs[!basename(sub_dirs) %in% keep_folders]

    for (dir_path in dirs_to_remove) {
      files_in_dir <- list.files(dir_path, recursive = TRUE)
      files_removed <- files_removed + length(files_in_dir)

      unlink(dir_path, recursive = TRUE)
      dirs_removed <- dirs_removed + 1
      cat("Removed subject folder:", basename(dir_path), "\n")
    }
  }

  # 2. Remove session folders NOT in the list (within kept subjects)
  if (!is.null(keep_sessions)) {
    sub_dirs <- list.dirs(output_dir, recursive = FALSE, full.names = TRUE)
    sub_dirs <- sub_dirs[grepl("^sub-", basename(sub_dirs))]

    for (sub_dir in sub_dirs) {
      ses_dirs <- list.dirs(sub_dir, recursive = FALSE, full.names = TRUE)
      ses_dirs <- ses_dirs[grepl("^ses-", basename(ses_dirs))]

      keep_ses_folders <- paste0("ses-", keep_sessions)
      ses_to_remove <- ses_dirs[!basename(ses_dirs) %in% keep_ses_folders]

      for (ses_path in ses_to_remove) {
        files_in_dir <- list.files(ses_path, recursive = TRUE)
        files_removed <- files_removed + length(files_in_dir)

        unlink(ses_path, recursive = TRUE)
        dirs_removed <- dirs_removed + 1
        cat("Removed session folder:", file.path(basename(sub_dir), basename(ses_path)), "\n")
      }
    }
  }

  # 3. Remove files whose pet identifier doesn't match filtered data
  if (!is.null(keep_pets)) {
    all_files <- list.files(output_dir, recursive = TRUE, full.names = TRUE)
    # Only consider files, not directories
    all_files <- all_files[!dir.exists(all_files)]

    for (filepath in all_files) {
      filename <- basename(filepath)
      # Extract pet identifier from filename (everything before _desc-)
      pet_from_file <- stringr::str_extract(filename, "^.+(?=_desc-)")

      if (!is.na(pet_from_file) && !pet_from_file %in% keep_pets) {
        file.remove(filepath)
        files_removed <- files_removed + 1
        cat("Removed file for filtered pet:", filename, "\n")
      }
    }
  }

  # Clean up empty directories (recursively remove empty sub-*/ses-*/pet directories)
  pet_dirs <- list.dirs(output_dir, recursive = TRUE, full.names = TRUE)
  pet_dirs <- pet_dirs[grepl("/pet$", pet_dirs)]

  for (pet_dir in pet_dirs) {
    if (dir.exists(pet_dir) && length(list.files(pet_dir, all.files = FALSE)) == 0) {
      unlink(pet_dir, recursive = TRUE)
      dirs_removed <- dirs_removed + 1

      parent_dir <- dirname(pet_dir)
      if (grepl("ses-", basename(parent_dir)) &&
          dir.exists(parent_dir) &&
          length(list.files(parent_dir, all.files = FALSE)) == 0) {
        unlink(parent_dir, recursive = TRUE)
        dirs_removed <- dirs_removed + 1

        grandparent_dir <- dirname(parent_dir)
        if (grepl("sub-", basename(grandparent_dir)) &&
            dir.exists(grandparent_dir) &&
            length(list.files(grandparent_dir, all.files = FALSE)) == 0) {
          unlink(grandparent_dir, recursive = TRUE)
          dirs_removed <- dirs_removed + 1
        }
      }
      else if (grepl("sub-", basename(parent_dir)) &&
               dir.exists(parent_dir) &&
               length(list.files(parent_dir, all.files = FALSE)) == 0) {
        unlink(parent_dir, recursive = TRUE)
        dirs_removed <- dirs_removed + 1
      }
    }
  }

  # Return summary
  summary_msg <- if (files_removed > 0 || dirs_removed > 0) {
    paste("Removed", files_removed, "files and", dirs_removed, "directories")
  } else {
    "No existing analysis files found"
  }

  return(list(
    files_removed = files_removed,
    dirs_removed = dirs_removed,
    summary = summary_msg
  ))
}

#' Create Individual TACs Files
#'
#' @description Create individual TACs files for each subject/session/pet combination
#' @param filtered_data Filtered combined TACs data
#' @param output_dir Output directory for individual files
#' @return Summary of created files
#' @export
create_individual_tacs_files <- function(filtered_data, output_dir) {
  
  if (is.null(filtered_data) || nrow(filtered_data) == 0) {
    warning("No data to create individual files")
    return(list(files_created = 0, summary = "No data"))
  }
  
  # Group by individual measurements (sub, ses, pet)
  measurement_groups <- filtered_data %>%
    dplyr::group_by(sub, ses, pet) %>%
    dplyr::group_nest(.key = "tacs_data", keep = TRUE)
  
  created_files <- c()
  
  # Create individual files for each measurement group
  for (i in 1:nrow(measurement_groups)) {
    sub_id <- measurement_groups$sub[i]
    ses_id <- measurement_groups$ses[i]
    pet_id <- measurement_groups$pet[i]
    tacs_data <- measurement_groups$tacs_data[[i]]
    
    # Create folder structure
    if (!is.na(ses_id)) {
      folder_path <- file.path(output_dir, paste0("sub-", sub_id), paste0("ses-", ses_id), "pet")
    } else {
      folder_path <- file.path(output_dir, paste0("sub-", sub_id), "pet")
    }
    
    # Create directories recursively
    if (!dir.exists(folder_path)) {
      dir.create(folder_path, recursive = TRUE)
    }
    
    # Generate filename using pet column
    filename <- paste0(pet_id, "_desc-combinedregions_tacs.tsv")
    filepath <- file.path(folder_path, filename)
    
    # Select and reorder columns for output
    output_data <- tacs_data %>%
      dplyr::select(pet, region, volume_mm3, InjectedRadioactivity, bodyweight, 
                   frame_start, frame_end, frame_dur, frame_mid, TAC) %>%
      dplyr::arrange(region, frame_start)
    
    # Write file
    tryCatch({
      readr::write_tsv(output_data, filepath)
      created_files <- c(created_files, filepath)
      cat("Created:", filename, "\n")
    }, error = function(e) {
      warning(paste("Error creating file", filename, ":", e$message))
    })
  }
  
  # Return summary
  return(list(
    files_created = length(created_files),
    file_paths = created_files,
    summary = paste("Created", length(created_files), "individual TACs files")
  ))
}