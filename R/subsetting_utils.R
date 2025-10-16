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