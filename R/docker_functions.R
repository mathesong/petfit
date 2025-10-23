#' Validate Directory Requirements for Docker
#'
#' @description Check that required directories exist for the selected function and mode
#'
#' @param func Character string: "regiondef" or "modelling"
#' @param mode Character string: "interactive" or "automatic"
#' @param bids_dir Character string path to BIDS directory (can be NULL)
#' @param derivatives_dir Character string path to derivatives directory (can be NULL)
#' @return List with validation result and messages
#' @export
validate_directory_requirements <- function(func, mode, bids_dir, derivatives_dir) {
  
  validation <- list(
    valid = TRUE,
    messages = character()
  )
  
  # Basic requirement: at least one directory must exist
  if (is.null(bids_dir) && is.null(derivatives_dir)) {
    validation$valid <- FALSE
    validation$messages <- c(validation$messages, "At least one of bids_dir or derivatives_dir must be provided")
    return(validation)
  }
  
  # Check directory existence
  if (!is.null(bids_dir) && !dir.exists(bids_dir)) {
    validation$valid <- FALSE
    validation$messages <- c(validation$messages, paste("BIDS directory does not exist:", bids_dir))
  }
  
  if (!is.null(derivatives_dir) && !dir.exists(derivatives_dir)) {
    validation$valid <- FALSE
    validation$messages <- c(validation$messages, paste("Derivatives directory does not exist:", derivatives_dir))
  }
  
  # Function-specific validation
  if (func == "regiondef") {
    # Region definition needs at least bids_dir for data access
    if (is.null(bids_dir) && mode == "interactive") {
      validation$messages <- c(validation$messages, "Warning: Region definition works best with BIDS directory access")
    }
  }
  
  if (func == "modelling" && mode == "automatic") {
    # Automatic modelling needs derivatives directory (or bids_dir to create it)
    derivatives_path <- derivatives_dir %||% file.path(bids_dir, "derivatives")
    if (!dir.exists(derivatives_path)) {
      validation$valid <- FALSE
      validation$messages <- c(validation$messages, paste("Derivatives directory required for automatic modelling:", derivatives_path))
    }
  }
  
  return(validation)
}

#' Validate Blood Data Requirements
#'
#' @description Check if blood data is required based on config and step
#'
#' @param config List containing petfit configuration
#' @param step Character string step name (NULL for full pipeline)
#' @param blood_dir Character string path to blood directory (can be NULL)
#' @return List with validation result and messages
#' @export
validate_blood_requirements <- function(config, step = NULL, blood_dir = NULL) {
  
  validation <- list(
    required = FALSE,
    valid = TRUE,
    messages = character()
  )
  
  # Check if delay fitting is enabled and not set to zero
  delay_required <- FALSE
  if (!is.null(config$FitDelay) && !is.null(config$FitDelay$model)) {
    delay_model <- config$FitDelay$model
    if (!delay_model %in% c("none", "zero", "Set to zero (i.e. no delay fitting to be performed)")) {
      delay_required <- TRUE
    }
  }
  
  # Check if any invasive models are configured
  invasive_models <- c("1TCM", "2TCM", "Logan", "MA1")
  invasive_model_present <- FALSE

  for (model_num in c("1", "2", "3")) {
    model_key <- paste0("Model", model_num)
    if (!is.null(config$Models[[model_key]]) && !is.null(config$Models[[model_key]]$type)) {
      if (config$Models[[model_key]]$type %in% invasive_models) {
        invasive_model_present <- TRUE
        break
      }
    }
  }
  
  # Blood data is required if delay fitting AND invasive models
  validation$required <- delay_required && invasive_model_present
  
  # Step-specific requirements
  if (!is.null(step)) {
    if (step == "delay") {
      # Delay step always requires blood data
      validation$required <- TRUE
    } else if (step %in% c("model1", "model2", "model3")) {
      # Check if this specific model is invasive
      model_num <- stringr::str_extract(step, "\\\\d+")
      model_key <- paste0("Model", model_num)
      if (!is.null(config$Models[[model_key]]) && !is.null(config$Models[[model_key]]$type)) {
        model_type <- config$Models[[model_key]]$type
        validation$required <- model_type %in% invasive_models
      }
    }
  }
  
  # Validate blood directory exists if required
  if (validation$required) {
    if (is.null(blood_dir) || !dir.exists(blood_dir)) {
      validation$valid <- FALSE
      if (is.null(step)) {
        validation$messages <- c(validation$messages, "Blood data directory required for delay fitting with invasive models")
      } else {
        validation$messages <- c(validation$messages, paste("Blood data directory required for step:", step))
      }
    } else {
      # Check for blood files
      blood_files <- list.files(blood_dir, pattern = "_(blood|inputfunction)\\\\.tsv$", recursive = TRUE)
      if (length(blood_files) == 0) {
        validation$valid <- FALSE
        validation$messages <- c(validation$messages, "No blood data files found in blood directory")
      } else {
        validation$messages <- c(validation$messages, paste("Found", length(blood_files), "blood data files"))
      }
    }
  }
  
  return(validation)
}

#' Run Automatic Modelling Pipeline
#'
#' @description Execute the petfit modelling analysis pipeline automatically based on a config file
#'
#' @param analysis_subfolder Character string name of analysis subfolder within derivatives/petfit/ (default: "Primary_Analysis")
#' @param bids_dir Character string path to BIDS directory (can be NULL)
#' @param derivatives_dir Character string path to derivatives directory (can be NULL)
#' @param petfit_output_foldername Character string name for petfit output folder within derivatives (default: "petfit")
#' @param blood_dir Character string path to blood directory (can be NULL)
#' @param step Character string specific step to run (NULL for full pipeline)
#' @return List with execution result and messages
#' @export
petfit_modelling_auto <- function(analysis_subfolder = "Primary_Analysis", bids_dir = NULL, derivatives_dir = NULL, petfit_output_foldername = "petfit", blood_dir = NULL, step = NULL) {

  result <- list(
    success = FALSE,
    messages = character(),
    reports_generated = character()
  )

  # Validate that at least one directory is provided
  if (is.null(bids_dir) && is.null(derivatives_dir)) {
    result$messages <- c(result$messages, "At least one of bids_dir or derivatives_dir must be provided")
    return(result)
  }

  # Set derivatives directory logic
  if (is.null(derivatives_dir)) {
    derivatives_dir <- file.path(bids_dir, "derivatives")
  }

  # Validate derivatives directory exists
  if (!dir.exists(derivatives_dir)) {
    result$messages <- c(result$messages, paste("Derivatives directory does not exist:", derivatives_dir))
    return(result)
  }

  # Construct full analysis folder path
  analysis_folder <- file.path(derivatives_dir, petfit_output_foldername, analysis_subfolder)

  if (!dir.exists(analysis_folder)) {
    result$messages <- c(result$messages, paste("Analysis folder does not exist:", analysis_folder))
    return(result)
  }

  result$messages <- c(result$messages, paste("Using analysis folder:", analysis_folder))

  # Load configuration
  config_path <- file.path(analysis_folder, "desc-petfitoptions_config.json")
  if (!file.exists(config_path)) {
    result$messages <- c(result$messages, paste("Config file not found:", config_path))
    return(result)
  }
  
  tryCatch({
    config <- jsonlite::fromJSON(config_path)
    result$messages <- c(result$messages, paste("Loaded config from:", config_path))
  }, error = function(e) {
    result$messages <- c(result$messages, paste("Error loading config:", e$message))
    return(result)
  })
  
  # Validate blood requirements
  blood_validation <- validate_blood_requirements(config, step, blood_dir)
  result$messages <- c(result$messages, blood_validation$messages)
  
  if (!blood_validation$valid) {
    result$messages <- c(result$messages, "Blood data validation failed")
    return(result)
  }
  
  # Determine which steps to run
  steps_to_run <- character()
  if (is.null(step)) {
    # Full pipeline - determine from config
    if (!is.null(config$Subsetting)) steps_to_run <- c(steps_to_run, "datadef")
    if (!is.null(config$Weights)) steps_to_run <- c(steps_to_run, "weights")
    if (!is.null(config$ReferenceTAC)) steps_to_run <- c(steps_to_run, "reference_tac")
    if (!is.null(config$FitDelay)) steps_to_run <- c(steps_to_run, "delay")
    if (!is.null(config$Models$Model1)) steps_to_run <- c(steps_to_run, "model1")
    if (!is.null(config$Models$Model2)) steps_to_run <- c(steps_to_run, "model2")
    if (!is.null(config$Models$Model3)) steps_to_run <- c(steps_to_run, "model3")
  } else {
    steps_to_run <- step
  }
  
  result$messages <- c(result$messages, paste("Steps to run:", paste(steps_to_run, collapse = ", ")))
  
  # Execute each step
  for (current_step in steps_to_run) {
    result$messages <- c(result$messages, paste("Executing step:", current_step))
    
    step_result <- execute_pipeline_step(current_step, analysis_folder, bids_dir, blood_dir, config)
    
    if (step_result$success) {
      result$messages <- c(result$messages, paste("Step", current_step, "completed successfully"))
      result$reports_generated <- c(result$reports_generated, step_result$report_file)
    } else {
      result$messages <- c(result$messages, paste("Step", current_step, "failed:", step_result$message))
      return(result)
    }
  }
  
  result$success <- TRUE
  result$messages <- c(result$messages, "Pipeline execution completed successfully")
  return(result)
}

#' Execute Individual Pipeline Step
#'
#' @description Execute a single step of the petfit pipeline
#'
#' @param step Character string step name
#' @param analysis_folder Character string path to analysis folder
#' @param bids_dir Character string path to BIDS directory (can be NULL)
#' @param blood_dir Character string path to blood directory (can be NULL)
#' @param config List containing petfit configuration
#' @return List with step execution result
execute_pipeline_step <- function(step, analysis_folder, bids_dir, blood_dir, config) {
  
  result <- list(
    success = FALSE,
    message = "",
    report_file = NULL
  )
  
  tryCatch({
    if (step == "datadef") {
      # Generate data definition report
      generate_step_report(
        step = "data_definition",
        analysis_folder = analysis_folder,
        bids_dir = bids_dir,
        blood_dir = blood_dir
      )
      result$report_file <- "data_definition_report.html"
      
    } else if (step == "weights") {
      # Generate weights report
      generate_step_report(
        step = "weights",
        analysis_folder = analysis_folder,
        bids_dir = bids_dir,
        blood_dir = blood_dir
      )
      result$report_file <- "weights_report.html"
      
    } else if (step == "delay") {
      # Generate delay report
      generate_step_report(
        step = "delay",
        analysis_folder = analysis_folder,
        bids_dir = bids_dir,
        blood_dir = blood_dir
      )
      result$report_file <- "delay_report.html"

    } else if (step == "reference_tac") {
      # Generate reference TAC report (no blood_dir needed)
      generate_step_report(
        step = "reference_tac",
        analysis_folder = analysis_folder,
        bids_dir = bids_dir,
        blood_dir = NULL
      )
      result$report_file <- "reference_tac_report.html"

    } else if (step %in% c("model1", "model2", "model3")) {
      # Generate model report
      model_num <- stringr::str_extract(step, "\\\\d+")
      model_key <- paste0("Model", model_num)

      if (!is.null(config$Models[[model_key]]) && !is.null(config$Models[[model_key]]$type)) {
        generate_model_report(
          model_number = model_num,
          model_type = config$Models[[model_key]]$type,
          analysis_folder = analysis_folder,
          bids_dir = bids_dir,
          blood_dir = blood_dir
        )
        result$report_file <- paste0("model", model_num, "_report.html")
      } else {
        result$message <- paste("Model", model_num, "not configured in config file")
        return(result)
      }
      
    } else {
      result$message <- paste("Unknown step:", step)
      return(result)
    }
    
    result$success <- TRUE
    result$message <- "Step completed successfully"
    
  }, error = function(e) {
    result$message <- paste("Error executing step:", e$message)
  })

  return(result)
}

#' Run Automatic Region Definition Pipeline
#'
#' @description Execute the petfit region definition pipeline automatically based on existing petfit_regions.tsv
#'
#' @param bids_dir Character string path to BIDS directory (optional if derivatives_dir provided)
#' @param derivatives_dir Character string path to derivatives directory (default: bids_dir/derivatives if bids_dir provided)
#' @param petfit_output_foldername Character string name for petfit output folder within derivatives (default: "petfit")
#' @return List with execution result and messages
#' @export
petfit_regiondef_auto <- function(bids_dir = NULL, derivatives_dir = NULL, petfit_output_foldername = "petfit") {

  result <- list(
    success = FALSE,
    messages = character(),
    output_file = NULL
  )

  # Validate that at least one directory is provided
  if (is.null(bids_dir) && is.null(derivatives_dir)) {
    result$messages <- c(result$messages, "At least one of bids_dir or derivatives_dir must be provided")
    return(result)
  }

  # Set derivatives directory logic
  if (is.null(derivatives_dir)) {
    if (is.null(bids_dir)) {
      result$messages <- c(result$messages, "Cannot determine derivatives_dir: no bids_dir or derivatives_dir provided")
      return(result)
    }
    derivatives_dir <- file.path(bids_dir, "derivatives")
  }

  # Validate directories that were provided
  if (!is.null(bids_dir) && !dir.exists(bids_dir)) {
    result$messages <- c(result$messages, paste("BIDS directory does not exist:", bids_dir))
    return(result)
  }

  if (!dir.exists(derivatives_dir)) {
    result$messages <- c(result$messages, paste("Derivatives directory does not exist:", derivatives_dir))
    return(result)
  }

  # Determine where to find petfit_regions.tsv (check multiple locations)
  petfit_base_dir <- file.path(derivatives_dir, petfit_output_foldername)
  config_locations <- c(
    file.path(petfit_base_dir, "petfit_regions.tsv")
  )

  # Add bids_dir location only if bids_dir is provided
  if (!is.null(bids_dir)) {
    config_locations <- c(config_locations, file.path(bids_dir, "code", "petfit", "petfit_regions.tsv"))
  }

  petfit_regions_file <- NULL
  for (loc in config_locations) {
    if (file.exists(loc)) {
      petfit_regions_file <- loc
      break
    }
  }

  if (is.null(petfit_regions_file)) {
    result$messages <- c(result$messages,
                        "petfit_regions.tsv not found in expected locations:",
                        paste("  -", config_locations, collapse = "\n"))
    return(result)
  }

  result$messages <- c(result$messages, paste("Found petfit_regions.tsv at:", petfit_regions_file))

  # Load participant data if bids_dir is available
  # NOTE: This is now optional as we'll get metadata from _tacs.json files
  participant_data <- NULL
  if (!is.null(bids_dir)) {
    tryCatch({
      participant_data <- load_participant_data(bids_dir)
      if (!is.null(participant_data)) {
        result$messages <- c(result$messages,
                            paste("Loaded participant data for", nrow(participant_data$data), "participants"))
      }
    }, error = function(e) {
      result$messages <- c(result$messages, paste("Note: Could not load participant data:", e$message))
    })
  } else {
    result$messages <- c(result$messages, "No BIDS directory provided - using metadata from _tacs.json files only")
  }

  # Create petfit_regions_files.tsv mapping
  tryCatch({
    result$messages <- c(result$messages, "Creating tacs-morph mapping...")

    petfit_regions_files_path <- create_petfit_regions_files(petfit_regions_file, derivatives_dir)

    result$messages <- c(result$messages, paste("Created mapping file:", petfit_regions_files_path))

  }, error = function(e) {
    result$messages <- c(result$messages, paste("Error creating mapping:", e$message))
    return(result)
  })

  # Generate combined TACs
  tryCatch({
    result$messages <- c(result$messages, "Generating combined TACs...")

    output_folder <- petfit_base_dir
    if (!dir.exists(output_folder)) {
      dir.create(output_folder, recursive = TRUE)
      result$messages <- c(result$messages, paste("Created output folder:", output_folder))
    }

    combined_data <- create_petfit_combined_tacs(
      petfit_regions_files_path,
      derivatives_dir,
      output_folder,
      bids_dir,
      participant_data
    )

    # Generate summary
    total_rows <- nrow(combined_data)
    total_regions <- length(unique(combined_data$region))
    total_subjects <- length(unique(combined_data$sub))

    output_file <- file.path(output_folder, "desc-combinedregions_tacs.tsv")
    result$output_file <- output_file

    result$messages <- c(result$messages,
                        "Successfully created combined TACs file",
                        paste("  Total rows:", total_rows),
                        paste("  Regions:", total_regions),
                        paste("  Subjects:", total_subjects),
                        paste("  Output:", output_file))

    result$success <- TRUE

  }, error = function(e) {
    result$messages <- c(result$messages, paste("Error generating combined TACs:", e$message))
    return(result)
  })

  return(result)
}
