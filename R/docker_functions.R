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
    if (!is.null(config[[model_key]]) && !is.null(config[[model_key]]$model)) {
      if (config[[model_key]]$model %in% invasive_models) {
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
      if (!is.null(config[[model_key]]) && !is.null(config[[model_key]]$model)) {
        model_type <- config[[model_key]]$model
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

#' Run Automatic Pipeline
#'
#' @description Execute the petfit analysis pipeline automatically based on a config file
#'
#' @param analysis_folder Character string path to analysis folder containing config
#' @param bids_dir Character string path to BIDS directory (can be NULL)
#' @param derivatives_dir Character string path to derivatives directory (can be NULL)
#' @param blood_dir Character string path to blood directory (can be NULL)
#' @param step Character string specific step to run (NULL for full pipeline)
#' @return List with execution result and messages
#' @export
run_automatic_pipeline <- function(analysis_folder, bids_dir = NULL, derivatives_dir = NULL, blood_dir = NULL, step = NULL) {
  
  result <- list(
    success = FALSE,
    messages = character(),
    reports_generated = character()
  )
  
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
    if (!is.null(config$FitDelay)) steps_to_run <- c(steps_to_run, "delay")
    if (!is.null(config$Model1)) steps_to_run <- c(steps_to_run, "model1")
    if (!is.null(config$Model2)) steps_to_run <- c(steps_to_run, "model2")
    if (!is.null(config$Model3)) steps_to_run <- c(steps_to_run, "model3")
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
      
    } else if (step %in% c("model1", "model2", "model3")) {
      # Generate model report
      model_num <- stringr::str_extract(step, "\\\\d+")
      model_key <- paste0("Model", model_num)
      
      if (!is.null(config[[model_key]]) && !is.null(config[[model_key]]$model)) {
        generate_model_report(
          model_number = model_num,
          model_type = config[[model_key]]$model,
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
