#' Parse Semicolon-Separated Values
#'
#' @description Parse semicolon-separated string into vector
#' @param input_string Character string with semicolon-separated values
#' @return Character vector of parsed values, or NULL if empty
#' @export
parse_semicolon_values <- function(input_string) {
  if (is.null(input_string) || input_string == "") {
    return(NULL)
  }
  
  # Split by semicolon and trim whitespace
  values <- stringr::str_split(input_string, ";")[[1]]
  values <- stringr::str_trim(values)
  
  # Remove empty values
  values <- values[values != ""]
  
  if (length(values) == 0) {
    return(NULL)
  }
  
  return(values)
}

#' Subset Combined TACs Data
#'
#' @description Filter combined TACs data based on subsetting criteria
#' @param combined_tacs_data Tibble with combined TACs data
#' @param subset_params List of subsetting parameters
#' @return Filtered tibble
#' @export
subset_combined_tacs <- function(combined_tacs_data, subset_params) {
  
  if (is.null(combined_tacs_data) || nrow(combined_tacs_data) == 0) {
    return(tibble::tibble())
  }
  
  filtered_data <- combined_tacs_data
  
  # Apply filters for each parameter
  if (!is.null(subset_params$sub)) {
    filtered_data <- filtered_data %>%
      dplyr::filter(sub %in% subset_params$sub)
  }
  
  if (!is.null(subset_params$ses)) {
    filtered_data <- filtered_data %>%
      dplyr::filter(ses %in% subset_params$ses)
  }
  
  if (!is.null(subset_params$task)) {
    filtered_data <- filtered_data %>%
      dplyr::filter(task %in% subset_params$task)
  }
  
  if (!is.null(subset_params$trc)) {
    filtered_data <- filtered_data %>%
      dplyr::filter(trc %in% subset_params$trc)
  }
  
  if (!is.null(subset_params$rec)) {
    filtered_data <- filtered_data %>%
      dplyr::filter(rec %in% subset_params$rec)
  }
  
  if (!is.null(subset_params$run)) {
    filtered_data <- filtered_data %>%
      dplyr::filter(run %in% subset_params$run)
  }
  
  if (!is.null(subset_params$regions)) {
    filtered_data <- filtered_data %>%
      dplyr::filter(region %in% subset_params$regions)
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
    # Subset by time in minutes
    # Use frame_start for filtering
    filtered_data <- filtered_data %>%
      dplyr::filter(frame_start >= start_point & frame_start <= end_point)
  }

  return(filtered_data)
}

#' Cleanup Individual TACs Files
#'
#' @description Remove all existing individual TACs files before regeneration
#' @param output_dir Output directory containing individual files
#' @param pattern File pattern to match (default: "*_desc-combinedregions_tacs.tsv")
#' @return List with counts of removed files and directories
#' @export
cleanup_individual_tacs_files <- function(output_dir,
                                         pattern = "*_desc-combinedregions_tacs.tsv") {

  files_removed <- 0
  dirs_removed <- 0

  if (!dir.exists(output_dir)) {
    return(list(files_removed = 0, dirs_removed = 0,
                summary = "Output directory does not exist"))
  }

  # Find all existing TACs files
  existing_files <- list.files(output_dir, pattern = pattern,
                               recursive = TRUE, full.names = TRUE)

  # Remove files
  if (length(existing_files) > 0) {
    file.remove(existing_files)
    files_removed <- length(existing_files)
    cat("Removed", files_removed, "existing TACs files\n")
  }

  # Clean up empty directories (recursively remove empty sub-*/ses-*/pet directories)
  # Find all pet directories
  pet_dirs <- list.dirs(output_dir, recursive = TRUE, full.names = TRUE)
  pet_dirs <- pet_dirs[grepl("/pet$", pet_dirs)]

  # Remove empty pet directories
  for (pet_dir in pet_dirs) {
    if (length(list.files(pet_dir, all.files = FALSE)) == 0) {
      unlink(pet_dir, recursive = TRUE)
      dirs_removed <- dirs_removed + 1

      # Also remove parent session directory if empty
      parent_dir <- dirname(pet_dir)
      if (grepl("ses-", basename(parent_dir)) &&
          length(list.files(parent_dir, all.files = FALSE)) == 0) {
        unlink(parent_dir, recursive = TRUE)
        dirs_removed <- dirs_removed + 1

        # Also remove parent subject directory if empty
        grandparent_dir <- dirname(parent_dir)
        if (grepl("sub-", basename(grandparent_dir)) &&
            length(list.files(grandparent_dir, all.files = FALSE)) == 0) {
          unlink(grandparent_dir, recursive = TRUE)
          dirs_removed <- dirs_removed + 1
        }
      }
      # Remove parent subject directory if empty (for no-session case)
      else if (grepl("sub-", basename(parent_dir)) &&
               length(list.files(parent_dir, all.files = FALSE)) == 0) {
        unlink(parent_dir, recursive = TRUE)
        dirs_removed <- dirs_removed + 1
      }
    }
  }

  # Return summary
  summary_msg <- if (files_removed > 0) {
    paste("Removed", files_removed, "files and", dirs_removed, "empty directories")
  } else {
    "No existing TACs files found"
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