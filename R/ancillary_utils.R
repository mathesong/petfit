#' Ancillary Analysis Folder Utilities
#'
#' @description
#' Functions for working with ancillary analysis folders. An ancillary analysis
#' is a preliminary analysis run on a subset of high-quality regions to estimate
#' shared parameters (delay, k2prime) that can then be inherited by a full analysis.

#' Validate Ancillary Analysis Folder
#'
#' @description Check that the ancillary folder exists and is a sibling subfolder
#' under the same petfit directory.
#'
#' @param petfit_dir Path to the petfit directory (parent of analysis subfolders)
#' @param ancillary_analysis_folder Name of the ancillary subfolder (not a full path)
#' @return The full resolved path to the ancillary folder
#' @export
validate_ancillary_folder <- function(petfit_dir, ancillary_analysis_folder) {
  if (is.null(ancillary_analysis_folder) || ancillary_analysis_folder == "") {
    stop("ancillary_analysis_folder must be provided", call. = FALSE)
  }

  # Must be a simple folder name, not a path

  if (grepl("[/\\\\]", ancillary_analysis_folder)) {
    stop("ancillary_analysis_folder must be a subfolder name (e.g., 'Ancillary_Analysis'), not a full path",
         call. = FALSE)
  }

  ancillary_path <- file.path(petfit_dir, ancillary_analysis_folder)

  if (!dir.exists(ancillary_path)) {
    stop("Ancillary analysis folder does not exist: ", ancillary_path, call. = FALSE)
  }

  return(ancillary_path)
}

#' Scan Ancillary Folder Contents
#'
#' @description Scan an ancillary analysis folder to determine what outputs are available
#' (delay files, model kinpar files).
#'
#' @param ancillary_path Full path to the ancillary analysis folder
#' @return List with available contents: delay_files, model1_kinpar, model2_kinpar, model3_kinpar
#' @export
scan_ancillary_contents <- function(ancillary_path) {
  result <- list(
    delay_files = character(0),
    model1_kinpar = character(0),
    model2_kinpar = character(0),
    model3_kinpar = character(0),
    model1_type = NULL,
    model2_type = NULL,
    model3_type = NULL
  )

  if (!dir.exists(ancillary_path)) {
    return(result)
  }

  # Scan for delay kinpar files
  delay_files <- list.files(ancillary_path,
                            pattern = "_desc-delayfit_kinpar\\.tsv$",
                            recursive = TRUE, full.names = TRUE)
  result$delay_files <- delay_files

  # Scan for model kinpar files (model1, model2, model3)
  for (model_num in 1:3) {
    model_pattern <- paste0("_desc-model", model_num, "_kinpar\\.tsv$")
    kinpar_files <- list.files(ancillary_path,
                               pattern = model_pattern,
                               recursive = TRUE, full.names = TRUE)
    result[[paste0("model", model_num, "_kinpar")]] <- kinpar_files

    # Try to determine model type from config
    config_path <- file.path(ancillary_path, "desc-petfitoptions_config.json")
    if (file.exists(config_path)) {
      tryCatch({
        config <- jsonlite::fromJSON(config_path)
        model_key <- paste0("Model", model_num)
        if (!is.null(config$Models[[model_key]]$type)) {
          result[[paste0("model", model_num, "_type")]] <- config$Models[[model_key]]$type
        }
      }, error = function(e) {
        # Silently continue if config can't be read
      })
    }
  }

  return(result)
}

#' Print Ancillary Folder Summary
#'
#' @description Print a formatted console message summarising what's available
#' in the ancillary analysis folder.
#'
#' @param ancillary_path Full path to the ancillary analysis folder
#' @param scan_result Result from scan_ancillary_contents()
#' @return Invisible NULL
#' @export
print_ancillary_summary <- function(ancillary_path, scan_result) {
  message("=== Ancillary Analysis Folder ===")
  message("  Path: ", ancillary_path)

  # Delay files
  n_delay <- length(scan_result$delay_files)
  if (n_delay > 0) {
    message("  Delay files: ", n_delay, " PET measurement(s)")
  } else {
    message("  Delay files: none found")
  }

  # Model kinpar files

  for (model_num in 1:3) {
    n_kinpar <- length(scan_result[[paste0("model", model_num, "_kinpar")]])
    model_type <- scan_result[[paste0("model", model_num, "_type")]]
    if (n_kinpar > 0) {
      type_str <- if (!is.null(model_type)) paste0(" (", model_type, ")") else ""
      message("  Model ", model_num, " kinpar files: ", n_kinpar, " PET measurement(s)", type_str)
    }
  }

  message("=================================")
  invisible(NULL)
}

#' Read Ancillary Delay Data
#'
#' @description Read delay kinpar files from the ancillary folder and extract
#' blood_timeshift values for each PET measurement.
#'
#' @param ancillary_path Full path to the ancillary analysis folder
#' @param pet_ids Character vector of PET IDs to look up (from the current analysis)
#' @return A tibble with pet and inpshift columns
#' @export
read_ancillary_delay <- function(ancillary_path, pet_ids = NULL) {
  delay_files <- list.files(ancillary_path,
                            pattern = "_desc-delayfit_kinpar\\.tsv$",
                            recursive = TRUE, full.names = TRUE)

  if (length(delay_files) == 0) {
    warning("No delay kinpar files found in ancillary folder: ", ancillary_path)
    return(tibble::tibble(pet = character(0), inpshift = numeric(0)))
  }

  # Read all delay files and extract PET ID + inpshift
  delay_data <- purrr::map_dfr(delay_files, function(f) {
    tryCatch({
      data <- readr::read_tsv(f, show_col_types = FALSE)
      # Extract PET ID from filename
      pet_id <- extract_pet_id_from_kinpar_filename(basename(f))
      if ("blood_timeshift" %in% names(data)) {
        # Take median blood_timeshift across regions for this PET measurement
        tibble::tibble(
          pet = pet_id,
          inpshift = stats::median(data$blood_timeshift, na.rm = TRUE)
        )
      } else if ("inpshift" %in% names(data)) {
        tibble::tibble(
          pet = pet_id,
          inpshift = stats::median(data$inpshift, na.rm = TRUE)
        )
      } else {
        tibble::tibble(pet = pet_id, inpshift = 0)
      }
    }, error = function(e) {
      warning("Could not read delay file: ", f, " - ", e$message)
      tibble::tibble(pet = character(0), inpshift = numeric(0))
    })
  })

  # If specific PET IDs requested, filter and warn about missing

  if (!is.null(pet_ids)) {
    missing_pets <- setdiff(pet_ids, delay_data$pet)
    if (length(missing_pets) > 0) {
      warning("PET IDs not found in ancillary delay data (will use inpshift=0): ",
              paste(missing_pets, collapse = ", "))
      # Add missing PETs with inpshift=0
      missing_df <- tibble::tibble(pet = missing_pets, inpshift = 0)
      delay_data <- dplyr::bind_rows(delay_data, missing_df)
    }
    delay_data <- dplyr::filter(delay_data, .data$pet %in% pet_ids)
  }

  return(delay_data)
}

#' Read Ancillary k2prime Data
#'
#' @description Read kinpar files from the ancillary folder and compute
#' aggregated k2prime values (mean or median per PET measurement).
#'
#' @param ancillary_path Full path to the ancillary analysis folder
#' @param model_num Model number (1, 2, or 3) to read from
#' @param aggregation Aggregation method: "mean" or "median"
#' @param pet_ids Character vector of PET IDs to look up (optional)
#' @return A tibble with pet and k2prime columns
#' @export
read_ancillary_k2prime <- function(ancillary_path, model_num, aggregation, pet_ids = NULL) {
  model_pattern <- paste0("_desc-model", model_num, "_kinpar\\.tsv$")
  kinpar_files <- list.files(ancillary_path,
                              pattern = model_pattern,
                              recursive = TRUE, full.names = TRUE)

  if (length(kinpar_files) == 0) {
    warning("No Model ", model_num, " kinpar files found in ancillary folder: ", ancillary_path)
    return(tibble::tibble(pet = character(0), k2prime = numeric(0)))
  }

  # Read all kinpar files and extract k2prime
  k2prime_data <- purrr::map_dfr(kinpar_files, function(f) {
    tryCatch({
      data <- readr::read_tsv(f, show_col_types = FALSE)
      pet_id <- extract_pet_id_from_kinpar_filename(basename(f))

      if (!"k2prime" %in% colnames(data)) {
        warning("No k2prime column in: ", f)
        return(tibble::tibble(pet = character(0), k2prime = numeric(0)))
      }

      # Aggregate across regions within this PET measurement
      agg_value <- if (aggregation == "mean") {
        mean(data$k2prime, na.rm = TRUE)
      } else {
        stats::median(data$k2prime, na.rm = TRUE)
      }

      tibble::tibble(pet = pet_id, k2prime = agg_value)
    }, error = function(e) {
      warning("Could not read kinpar file: ", f, " - ", e$message)
      tibble::tibble(pet = character(0), k2prime = numeric(0))
    })
  })

  # Filter to requested PET IDs if specified
  if (!is.null(pet_ids)) {
    missing_pets <- setdiff(pet_ids, k2prime_data$pet)
    if (length(missing_pets) > 0) {
      warning("PET IDs not found in ancillary k2prime data (will use k2prime=0.1): ",
              paste(missing_pets, collapse = ", "))
      missing_df <- tibble::tibble(pet = missing_pets, k2prime = 0.1)
      k2prime_data <- dplyr::bind_rows(k2prime_data, missing_df)
    }
    k2prime_data <- dplyr::filter(k2prime_data, .data$pet %in% pet_ids)
  }

  return(k2prime_data)
}

#' Parse Ancillary k2prime Source String
#'
#' @description Parse a k2prime source string like "ancillary_model1_median" into
#' its components (model number and aggregation method).
#'
#' @param source_string Character string like "ancillary_model1_median"
#' @return List with model_num (integer) and aggregation (character)
#' @export
parse_ancillary_k2prime_source <- function(source_string) {
  if (is.null(source_string) || !grepl("^ancillary_model", source_string)) {
    stop("Invalid ancillary k2prime source string: ", source_string, call. = FALSE)
  }

  match <- regmatches(source_string,
                      regexec("^ancillary_model(\\d+)_(mean|median)$", source_string))[[1]]

  if (length(match) < 3) {
    stop("Could not parse ancillary k2prime source string: ", source_string, call. = FALSE)
  }

  list(
    model_num = as.integer(match[2]),
    aggregation = match[3]
  )
}

#' Get Ancillary Dropdown Options for Delay
#'
#' @description Get the dropdown option for delay inheritance from ancillary folder,
#' only if delay files are available.
#'
#' @param scan_result Result from scan_ancillary_contents()
#' @return Named character vector suitable for selectInput choices, or NULL if not available
#' @export
get_ancillary_delay_options <- function(scan_result) {
  if (length(scan_result$delay_files) > 0) {
    return(c("Inherit from ancillary analysis folder" = "ancillary_estimate"))
  }
  return(NULL)
}

#' Get Ancillary Dropdown Options for k2prime
#'
#' @description Get dropdown options for k2prime inheritance from ancillary folder,
#' based on what model kinpar files are actually available.
#'
#' @param scan_result Result from scan_ancillary_contents()
#' @return Named character vector suitable for selectInput choices, or NULL if none available
#' @export
get_ancillary_k2prime_options <- function(scan_result) {
  options <- c()

  for (model_num in 1:3) {
    n_kinpar <- length(scan_result[[paste0("model", model_num, "_kinpar")]])
    if (n_kinpar > 0) {
      model_type <- scan_result[[paste0("model", model_num, "_type")]]
      type_str <- if (!is.null(model_type)) paste0(" (", model_type, ")") else ""

      mean_label <- paste0("Ancillary: Model ", model_num, type_str, " - Mean")
      median_label <- paste0("Ancillary: Model ", model_num, type_str, " - Median")
      mean_value <- paste0("ancillary_model", model_num, "_mean")
      median_value <- paste0("ancillary_model", model_num, "_median")

      options <- c(options,
                   stats::setNames(mean_value, mean_label),
                   stats::setNames(median_value, median_label))
    }
  }

  if (length(options) == 0) return(NULL)
  return(options)
}

#' Copy Ancillary Delay Files to Current Analysis
#'
#' @description Copy delay kinpar files from the ancillary folder into the current
#' analysis folder, so that model report templates can find them using existing
#' glob patterns.
#'
#' @param ancillary_path Full path to the ancillary analysis folder
#' @param output_dir Full path to the current analysis folder
#' @return List with success status and number of files copied
#' @export
copy_ancillary_delay_files <- function(ancillary_path, output_dir) {
  delay_files <- list.files(ancillary_path,
                            pattern = "_desc-delayfit_kinpar\\.(tsv|json)$",
                            recursive = TRUE, full.names = TRUE)

  if (length(delay_files) == 0) {
    return(list(success = FALSE, files_copied = 0,
                message = "No delay files found in ancillary folder"))
  }

  files_copied <- 0
  for (src_file in delay_files) {
    # Preserve the relative path structure
    rel_path <- sub(paste0("^", normalizePath(ancillary_path, mustWork = FALSE), "/?"), "",
                    normalizePath(src_file, mustWork = FALSE))
    dest_file <- file.path(output_dir, rel_path)

    # Create destination directory if needed
    dest_dir <- dirname(dest_file)
    if (!dir.exists(dest_dir)) {
      dir.create(dest_dir, recursive = TRUE)
    }

    tryCatch({
      file.copy(src_file, dest_file, overwrite = TRUE)
      files_copied <- files_copied + 1
    }, error = function(e) {
      warning("Could not copy delay file: ", src_file, " - ", e$message)
    })
  }

  return(list(
    success = files_copied > 0,
    files_copied = files_copied,
    message = paste("Copied", files_copied, "delay file(s) from ancillary folder")
  ))
}

#' Extract PET ID from Kinpar Filename
#'
#' @description Extract the PET measurement identifier from a kinpar filename.
#' The PET ID is the portion before any _model_ or _desc- prefix.
#'
#' @param filename Basename of a kinpar file
#' @return Character string PET ID
extract_pet_id_from_kinpar_filename <- function(filename) {
  # Remove file extension
  stem <- sub("\\.(tsv|json)$", "", filename)
  # Remove everything from _model_ or _desc- onwards
  pet_id <- sub("_model_.*$", "", stem)
  pet_id <- sub("_desc-.*$", "", pet_id)
  return(pet_id)
}
