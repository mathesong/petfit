#' Core Pipeline Execution Functions
#'
#' @description
#' These functions contain the core business logic for each pipeline step.
#' They read configuration from JSON files and are used by both:
#' - Interactive Shiny apps (after saving config)
#' - Non-interactive automatic execution (using existing config)
#'
#' This ensures perfect consistency between execution modes.

#' Execute Data Definition Step
#'
#' @description Create individual TACs files from combined TACs with subsetting
#'
#' @param config_path Path to JSON configuration file
#' @param output_dir Path to analysis output directory
#' @param petfit_dir Path to petfit directory containing combined TACs
#' @param bids_dir Optional BIDS directory path
#' @param blood_dir Optional blood data directory path
#' @param notify Notification callback function(msg, type)
#' @return List with success status, message, and files_created count
#' @export
execute_datadef_step <- function(config_path, output_dir, petfit_dir,
                                  bids_dir = NULL, blood_dir = NULL,
                                  notify = function(msg, type) {}) {

  result <- list(success = FALSE, message = "", files_created = 0)

  tryCatch({
    # Load configuration
    config <- jsonlite::fromJSON(config_path)

    if (is.null(config$Subsetting)) {
      result$message <- "Subsetting configuration not found in config file"
      notify(result$message, "error")
      return(result)
    }

    # Check combined TACs file
    combined_tacs_file <- file.path(petfit_dir, "desc-combinedregions_tacs.tsv")

    if (!file.exists(combined_tacs_file)) {
      result$message <- "Combined TACs file not found. Please run the region definition app first."
      notify(result$message, "error")
      return(result)
    }

    # Read combined TACs data
    combined_data <- readr::read_tsv(combined_tacs_file, show_col_types = FALSE)

    if (nrow(combined_data) == 0) {
      result$message <- "Combined TACs file is empty"
      notify(result$message, "error")
      return(result)
    }

    # Extract subsetting parameters from config
    # Need to parse semicolon-separated values (empty strings -> NULL)
    subset_params <- list(
      sub = parse_semicolon_values(config$Subsetting$sub),
      ses = parse_semicolon_values(config$Subsetting$ses),
      task = parse_semicolon_values(config$Subsetting$task),
      trc = parse_semicolon_values(config$Subsetting$trc),
      rec = parse_semicolon_values(config$Subsetting$rec),
      run = parse_semicolon_values(config$Subsetting$run),
      regions = parse_semicolon_values(config$Subsetting$Regions)
    )

    # Apply subsetting
    filtered_data <- subset_combined_tacs(combined_data, subset_params)

    if (nrow(filtered_data) == 0) {
      result$message <- "No data matches the subsetting criteria"
      notify(result$message, "warning")
      return(result)
    }

    # Apply TAC frame/time subsetting if configured
    if (!is.null(config$Subsetting$tac_subset)) {
      tac_subset <- config$Subsetting$tac_subset
      filtered_data <- subset_tacs_by_frames(
        filtered_data,
        subset_type = tac_subset$type,
        start_point = tac_subset$start,
        end_point = tac_subset$end
      )

      if (nrow(filtered_data) == 0) {
        result$message <- "No data remains after TAC frame/time subsetting"
        notify(result$message, "warning")
        return(result)
      }
    }

    # Cleanup previous TACs files before creating new ones
    notify("Cleaning up previous TACs files...", "message")
    cleanup_result <- cleanup_individual_tacs_files(output_dir)

    # Create individual TACs files
    file_result <- create_individual_tacs_files(filtered_data, output_dir)

    # Show report generation notification
    notify("Generating report...", "message")

    cat("=== Data Subsetting Complete ===\n")
    cat("Files created:", file_result$files_created, "\n")
    cat("Analysis folder:", output_dir, "\n")
    cat("Total measurements:", nrow(filtered_data), "\n")
    cat("Unique subjects:", length(unique(filtered_data$sub)), "\n")
    cat("Unique regions:", length(unique(filtered_data$region)), "\n")

    # Generate data definition report
    report_file <- tryCatch({
      generate_step_report(
        step_name = "data_definition",
        analysis_folder = output_dir,
        bids_dir = bids_dir,
        blood_dir = blood_dir
      )
    }, error = function(e) {
      cat("Warning: Could not generate data definition report:", e$message, "\n")
      NULL
    })

    if (!is.null(report_file)) {
      notify("Data definition report generated successfully", "message")
    }

    result$success <- TRUE
    result$message <- paste("Removed", cleanup_result$files_removed, "old files. Created", file_result$files_created, "new files successfully")
    result$files_created <- file_result$files_created
    result$files_removed <- cleanup_result$files_removed
    result$report_path <- report_file

  }, error = function(e) {
    result$message <- paste("Error during data subsetting:", e$message)
    notify(result$message, "error")
    cat("Error:", e$message, "\n")
  })

  return(result)
}

#' Execute Weights Calculation Step
#'
#' @description Calculate weights for kinetic modeling
#'
#' @param config_path Path to JSON configuration file
#' @param output_dir Path to analysis output directory
#' @param bids_dir Optional BIDS directory path
#' @param blood_dir Optional blood data directory path
#' @param notify Notification callback function(msg, type)
#' @return List with success status and message
#' @export
execute_weights_step <- function(config_path, output_dir,
                                  bids_dir = NULL, blood_dir = NULL,
                                  notify = function(msg, type) {}) {

  result <- list(success = FALSE, message = "")

  tryCatch({
    # Check for combined regions TACs files
    tacs_files <- list.files(output_dir,
                            pattern = "*_desc-combinedregions_tacs.tsv",
                            recursive = TRUE)

    if (length(tacs_files) == 0) {
      result$message <- "No combined regions TACs files found. Please run Data Definition first."
      notify(result$message, "error")
      return(result)
    }

    # Generate weights report
    notify("Generating weights report...", "message")

    report_file <- tryCatch({
      generate_step_report(
        step_name = "weights",
        analysis_folder = output_dir,
        bids_dir = bids_dir,
        blood_dir = blood_dir
      )
    }, error = function(e) {
      cat("Error generating weights report:", e$message, "\n")
      NULL
    })

    if (!is.null(report_file)) {
      result$success <- TRUE
      result$message <- "Weights report generated successfully"
      result$report_path <- report_file
      notify("Weights report generated", "message")
    } else {
      result$message <- "Weights report generation failed - check console for details"
      notify(result$message, "error")
    }

  }, error = function(e) {
    result$message <- paste("Could not generate weights report:", e$message)
    notify(result$message, "error")
    cat("Error generating weights report:", e$message, "\n")
  })

  return(result)
}

#' Execute Delay Estimation Step
#'
#' @description Estimate delay between blood and tissue curves
#'
#' @param config_path Path to JSON configuration file
#' @param output_dir Path to analysis output directory
#' @param bids_dir Optional BIDS directory path
#' @param blood_dir Optional blood data directory path
#' @param notify Notification callback function(msg, type)
#' @return List with success status and message
#' @export
execute_delay_step <- function(config_path, output_dir,
                               bids_dir = NULL, blood_dir = NULL,
                               notify = function(msg, type) {}) {

  result <- list(success = FALSE, message = "")

  tryCatch({
    # Load configuration
    config <- jsonlite::fromJSON(config_path)

    # Check if delay method is "none"
    if (!is.null(config$FitDelay$model)) {
      if (config$FitDelay$model == "none" ||
          config$FitDelay$model == "Set to zero (i.e. no delay fitting to be performed)") {
        result$success <- TRUE
        result$message <- "No delay report necessary when delay fitting is disabled"
        notify(result$message, "message")
        return(result)
      }
    }

    # Check if blood data is available
    check_blood_files <- function(dir_path) {
      if (is.null(dir_path) || !dir.exists(dir_path)) {
        return(FALSE)
      }
      blood_files <- list.files(dir_path, pattern = "_(blood|inputfunction)\\.tsv$", recursive = TRUE)
      return(length(blood_files) > 0)
    }

    has_blood_data <- FALSE
    if (!is.null(blood_dir)) {
      has_blood_data <- check_blood_files(blood_dir)
    } else if (!is.null(bids_dir)) {
      has_blood_data <- check_blood_files(output_dir) || check_blood_files(bids_dir)
    }

    if (!has_blood_data) {
      result$message <- "No blood data found for delay estimation"
      notify(result$message, "error")
      return(result)
    }

    # Generate delay report
    notify("Estimating delays...", "message")

    report_file <- tryCatch({
      generate_step_report(
        step_name = "delay",
        analysis_folder = output_dir,
        bids_dir = bids_dir,
        blood_dir = blood_dir
      )
    }, error = function(e) {
      cat("Warning: Could not generate delay report:", e$message, "\n")
      NULL
    })

    if (!is.null(report_file)) {
      result$success <- TRUE
      result$message <- "Delay report generated successfully"
      result$report_path <- report_file
      notify("Delay report generated successfully", "message")
    } else {
      result$message <- "Report generation failed"
      notify(result$message, "error")
    }

  }, error = function(e) {
    result$message <- paste("Error generating delay report:", e$message)
    notify(result$message, "error")
    cat("Warning: Could not generate delay report:", e$message, "\n")
  })

  return(result)
}

#' Execute Reference TAC Step
#'
#' @description Process reference tissue TACs for non-invasive modeling
#'
#' @param config_path Path to JSON configuration file
#' @param output_dir Path to analysis output directory
#' @param bids_dir Optional BIDS directory path
#' @param notify Notification callback function(msg, type)
#' @return List with success status and message
#' @export
execute_reference_tac_step <- function(config_path, output_dir,
                                       bids_dir = NULL,
                                       notify = function(msg, type) {}) {

  result <- list(success = FALSE, message = "")

  tryCatch({
    # Check for combined regions TACs files
    tacs_files <- list.files(output_dir,
                            pattern = "*_desc-combinedregions_tacs.tsv",
                            recursive = TRUE)

    if (length(tacs_files) == 0) {
      result$message <- "No combined regions TACs files found. Please run Data Definition first."
      notify(result$message, "error")
      return(result)
    }

    # Generate reference TAC report
    notify("Generating reference TAC report...", "message")

    report_file <- tryCatch({
      generate_step_report(
        step_name = "reference_tac",
        analysis_folder = output_dir,
        bids_dir = bids_dir,
        blood_dir = NULL
      )
    }, error = function(e) {
      cat("Error generating reference TAC report:", e$message, "\n")
      NULL
    })

    if (!is.null(report_file)) {
      result$success <- TRUE
      result$message <- "Reference TAC report generated successfully"
      result$report_path <- report_file
      notify("Reference TAC report generated", "message")
    } else {
      result$message <- "Reference TAC report generation failed - check console for details"
      notify(result$message, "error")
    }

  }, error = function(e) {
    result$message <- paste("Could not generate reference TAC report:", e$message)
    notify(result$message, "error")
    cat("Error generating reference TAC report:", e$message, "\n")
  })

  return(result)
}

#' Execute Model Fitting Step
#'
#' @description Fit kinetic model to TAC data
#'
#' @param config_path Path to JSON configuration file
#' @param model_num Model number (1, 2, or 3)
#' @param output_dir Path to analysis output directory
#' @param bids_dir Optional BIDS directory path
#' @param blood_dir Optional blood data directory path
#' @param notify Notification callback function(msg, type)
#' @return List with success status and message
#' @export
execute_model_step <- function(config_path, model_num, output_dir,
                               bids_dir = NULL, blood_dir = NULL,
                               notify = function(msg, type) {}) {

  result <- list(success = FALSE, message = "")

  tryCatch({
    # Load configuration
    config <- jsonlite::fromJSON(config_path)

    # Get model configuration
    model_key <- paste0("Model", model_num)

    if (is.null(config$Models[[model_key]]) || is.null(config$Models[[model_key]]$type)) {
      result$message <- paste("Model", model_num, "not configured in config file")
      notify(result$message, "error")
      return(result)
    }

    model_type <- config$Models[[model_key]]$type

    # Show fitting notification
    notify(paste("Fitting Model", model_num, "(", model_type, ")..."), "message")

    # Generate model report
    report_file <- tryCatch({
      generate_model_report(
        model_type = model_type,
        model_number = paste("Model", model_num),
        analysis_folder = output_dir,
        bids_dir = bids_dir,
        blood_dir = blood_dir
      )
    }, error = function(e) {
      cat("Warning: Could not generate Model", model_num, "report:", e$message, "\n")
      NULL
    })

    if (!is.null(report_file)) {
      result$success <- TRUE
      result$message <- paste("Model", model_num, "fitting report generated successfully")
      result$report_path <- report_file
      notify(result$message, "message")
    } else {
      result$message <- paste("Error fitting Model", model_num, ": report generation failed")
      notify(result$message, "error")
    }

  }, error = function(e) {
    result$message <- paste("Error fitting Model", model_num, ":", e$message)
    notify(result$message, "error")
    cat("Warning: Could not generate Model", model_num, "report:", e$message, "\n")
  })

  return(result)
}
