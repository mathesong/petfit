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
      model_num <- stringr::str_extract(step, "\\d+")
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
      blood_files <- list.files(blood_dir, pattern = "_(blood|inputfunction)\\.tsv$", recursive = TRUE)
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

#' Run petfit Automatic Pipeline
#'
#' @description Unified interface for running petfit automatic pipelines. Dispatches to the
#'   appropriate pipeline function based on the \code{app} parameter.
#'
#' @param app Character string specifying which pipeline to run: "regiondef", "modelling_plasma",
#'   or "modelling_ref" (required)
#' @param bids_dir Character string path to the BIDS directory (default: NULL)
#' @param derivatives_dir Character string path to derivatives directory (default: bids_dir/derivatives if bids_dir provided)
#' @param blood_dir Character string path to blood data directory (default: NULL, for plasma input models)
#' @param petfit_output_foldername Character string name for petfit output folder within derivatives (default: "petfit")
#' @param analysis_foldername Character string name for analysis folder (default: "Primary_Analysis", for modelling apps)
#' @param step Character string specifying which step to run (NULL = all steps, or "datadef", "weights",
#'   "delay", "reference_tac", "model1", "model2", "model3"). Only used for modelling apps.
#' @param cores Integer number of cores for parallel processing (default: 1)
#' @param ancillary_analysis_folder Character string name of a sibling analysis folder to inherit
#'   delay or k2prime estimates from (optional, for modelling apps). Must be a folder name, not a full path.
#' @return List with execution result and messages
#'
#' @details
#' This function provides a unified interface to run petfit automatic pipelines:
#' - "regiondef": Runs the region definition pipeline (uses \code{\link{petfit_regiondef_auto}})
#' - "modelling_plasma" or "modelling_ref": Runs the modelling pipeline (uses \code{\link{petfit_modelling_auto}}).
#'   Pipeline type (plasma vs reference) is auto-detected from the configuration file.
#'
#' @examples
#' \dontrun{
#' # Run region definition
#' petfit_auto(app = "regiondef", derivatives_dir = "/path/to/derivatives")
#'
#' # Run modelling pipeline (auto-detects plasma vs reference from config)
#' petfit_auto(app = "modelling_plasma", derivatives_dir = "/path/to/derivatives")
#'
#' # Run specific modelling step
#' petfit_auto(app = "modelling_ref", derivatives_dir = "/path/to/derivatives", step = "weights")
#' }
#'
#' @export
petfit_auto <- function(app = c("regiondef", "modelling_plasma", "modelling_ref"),
                        bids_dir = NULL,
                        derivatives_dir = NULL,
                        blood_dir = NULL,
                        petfit_output_foldername = "petfit",
                        analysis_foldername = "Primary_Analysis",
                        step = NULL,
                        cores = 1L,
                        save_logs = FALSE,
                        ancillary_analysis_folder = NULL) {

  app <- match.arg(app, choices = c("regiondef", "modelling_plasma", "modelling_ref"))

  if (app == "regiondef") {
    petfit_regiondef_auto(
      bids_dir = bids_dir,
      derivatives_dir = derivatives_dir,
      petfit_output_foldername = petfit_output_foldername,
      cores = cores
    )
  } else {
    petfit_modelling_auto(
      bids_dir = bids_dir,
      derivatives_dir = derivatives_dir,
      petfit_output_foldername = petfit_output_foldername,
      analysis_foldername = analysis_foldername,
      blood_dir = blood_dir,
      step = step,
      cores = cores,
      save_logs = save_logs,
      ancillary_analysis_folder = ancillary_analysis_folder
    )
  }
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
petfit_regiondef_auto <- function(bids_dir = NULL, derivatives_dir = NULL, petfit_output_foldername = "petfit", cores = 1L) {

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

    create_petfit_regions_files(petfit_regions_file, derivatives_dir)

    petfit_regions_files_path <- file.path(petfit_base_dir, "petfit_regions_files.tsv")

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
      participant_data,
      cores = cores
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

#' Determine Pipeline Type from Config
#'
#' @description Determine whether a config represents a plasma input or reference tissue pipeline
#'
#' @param config List containing petfit configuration (parsed JSON)
#' @param pipeline_type Optional explicit pipeline type ("plasma" or "reference") as override
#' @return Character string: "plasma" or "reference", or NULL if cannot be determined
#' @export
determine_pipeline_type <- function(config, pipeline_type = NULL) {
  # 1. Explicit parameter takes priority
  if (!is.null(pipeline_type)) {
    if (pipeline_type %in% c("plasma", "reference")) {
      return(pipeline_type)
    }
  }

  # 2. Check modelling_configuration_type in config
  config_type <- config$modelling_configuration_type
  if (!is.null(config_type)) {
    if (config_type == "plasma input") return("plasma")
    if (config_type == "reference tissue") return("reference")
  }

  # 3. Fallback: inspect config sections
  if (!is.null(config$FitDelay)) return("plasma")
  if (!is.null(config$ReferenceTAC)) return("reference")

  # 4. Final fallback: inspect model types
  invasive_models <- c("1TCM", "2TCM", "Logan", "MA1")
  reference_models <- c("SRTM", "refLogan", "MRTM1", "MRTM2")
  for (model_num in c("1", "2", "3")) {
    model_key <- paste0("Model", model_num)
    if (!is.null(config$Models[[model_key]]$type)) {
      if (config$Models[[model_key]]$type %in% invasive_models) {
        return("plasma")
      }
      if (config$Models[[model_key]]$type %in% reference_models) {
        return("reference")
      }
    }
  }

  # Cannot determine
  return(NULL)
}

#' Run Automatic Modelling Pipeline
#'
#' @description Execute the petfit modelling pipeline automatically based on existing config file
#'
#' @param bids_dir Character string path to BIDS directory (optional if derivatives_dir provided)
#' @param derivatives_dir Character string path to derivatives directory (default: bids_dir/derivatives if bids_dir provided)
#' @param petfit_output_foldername Character string name for petfit output folder within derivatives (default: "petfit")
#' @param analysis_foldername Character string name for analysis folder (default: "Primary_Analysis")
#' @param blood_dir Character string path to blood data directory (optional, for invasive models)
#' @param step Character string specifying which step to run (NULL = all steps, or "datadef", "weights", "delay", "reference_tac", "model1", "model2", "model3")
#' @param pipeline_type Character string specifying pipeline type: "plasma" or "reference" (optional, auto-detected from config if not provided)
#' @param ancillary_analysis_folder Character string name of a sibling analysis subfolder to inherit
#'   delay or k2prime estimates from (optional). Must be a subfolder name, not a full path.
#' @return List with execution result and messages
#' @export
petfit_modelling_auto <- function(bids_dir = NULL,
                                   derivatives_dir = NULL,
                                   petfit_output_foldername = "petfit",
                                   analysis_foldername = "Primary_Analysis",
                                   blood_dir = NULL,
                                   step = NULL,
                                   pipeline_type = NULL,
                                   cores = 1L,
                                   save_logs = FALSE,
                                   ancillary_analysis_folder = NULL) {

  result <- list(
    success = FALSE,
    messages = character(),
    step_results = list()
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

  # Normalize paths to absolute paths
  if (!is.null(bids_dir)) {
    bids_dir <- normalizePath(bids_dir, mustWork = FALSE)
  }
  derivatives_dir <- normalizePath(derivatives_dir, mustWork = FALSE)
  if (!is.null(blood_dir)) {
    blood_dir <- normalizePath(blood_dir, mustWork = FALSE)
  }

  # Determine analysis folder path
  petfit_base_dir <- file.path(derivatives_dir, petfit_output_foldername)
  analysis_folder <- file.path(petfit_base_dir, analysis_foldername)

  if (!dir.exists(analysis_folder)) {
    result$messages <- c(result$messages, paste("Analysis folder does not exist:", analysis_folder))
    return(result)
  }

  # Find config file
  config_path <- file.path(analysis_folder, "desc-petfitoptions_config.json")

  if (!file.exists(config_path)) {
    result$messages <- c(result$messages, paste("Config file not found:", config_path))
    result$messages <- c(result$messages, "Please run the modelling app interactively first to create the configuration")
    return(result)
  }

  result$messages <- c(result$messages, paste("Found config file:", config_path))

  # Load config to check what type of analysis this is
  config <- tryCatch({
    jsonlite::fromJSON(config_path)
  }, error = function(e) {
    result$messages <- c(result$messages, paste("Error reading config file:", e$message))
    return(NULL)
  })

  if (is.null(config)) {
    return(result)
  }

  # Validate and resolve ancillary analysis folder if provided
  ancillary_path <- NULL
  if (!is.null(ancillary_analysis_folder)) {
    ancillary_validation_error <- tryCatch({
      ancillary_path <- validate_ancillary_folder(petfit_base_dir, ancillary_analysis_folder)
      ancillary_scan <- scan_ancillary_contents(ancillary_path)
      print_ancillary_summary(ancillary_path, ancillary_scan)
      NULL
    }, error = function(e) {
      e$message
    })

    if (!is.null(ancillary_validation_error)) {
      result$messages <- c(result$messages,
                          paste("Ancillary folder error:", ancillary_validation_error))
      return(result)
    }
  }

  # Check if config references ancillary but no ancillary folder provided
  if (is.null(ancillary_path)) {
    delay_model <- config$FitDelay$model
    if (!is.null(delay_model) && delay_model == "ancillary_estimate") {
      result$messages <- c(result$messages,
                          "Config references ancillary delay (ancillary_estimate) but no ancillary_analysis_folder provided")
      return(result)
    }
    for (model_num in c("1", "2", "3")) {
      model_key <- paste0("Model", model_num)
      k2prime_src <- config$Models[[model_key]]$k2prime_source
      if (!is.null(k2prime_src) && grepl("^ancillary_", k2prime_src)) {
        result$messages <- c(result$messages,
                            paste0("Config references ancillary k2prime (", k2prime_src,
                                   ") for ", model_key, " but no ancillary_analysis_folder provided"))
        return(result)
      }
    }
  }

  # Console-only notification callback (no Shiny in automatic mode)
  notify <- function(msg, type) {
    cat(paste0("[", toupper(type), "] ", msg, "\n"))
  }

  # Determine which steps to run
  if (is.null(step)) {
    # Running full pipeline - determine step list based on pipeline type
    detected_type <- determine_pipeline_type(config, pipeline_type)

    if (is.null(detected_type)) {
      result$messages <- c(result$messages, "Cannot determine pipeline type from config or parameters")
      result$messages <- c(result$messages, "Please specify pipeline_type or ensure config has modelling_configuration_type")
      return(result)
    }

    result$messages <- c(result$messages, paste("Pipeline type:", detected_type))

    if (detected_type == "plasma") {
      steps_to_run <- c("datadef", "weights", "delay", "model1", "model2", "model3")
    } else {
      steps_to_run <- c("datadef", "weights", "reference_tac", "model1", "model2", "model3")
    }
  } else {
    # Running a specific step - no filtering needed
    steps_to_run <- step
  }

  # Execute steps sequentially
  for (current_step in steps_to_run) {

    step_result <- NULL

    if (current_step == "datadef") {
      result$messages <- c(result$messages, "\n=== Running Data Definition ===")
      step_result <- execute_datadef_step(
        config_path = config_path,
        output_dir = analysis_folder,
        petfit_dir = petfit_base_dir,
        bids_dir = bids_dir,
        blood_dir = blood_dir,
        cores = cores,
        save_logs = save_logs,
        notify = notify
      )

    } else if (current_step == "weights") {
      result$messages <- c(result$messages, "\n=== Running Weights Calculation ===")
      step_result <- execute_weights_step(
        config_path = config_path,
        output_dir = analysis_folder,
        bids_dir = bids_dir,
        blood_dir = blood_dir,
        cores = cores,
        save_logs = save_logs,
        notify = notify
      )

    } else if (current_step == "delay") {
      result$messages <- c(result$messages, "\n=== Running Delay Estimation ===")
      step_result <- execute_delay_step(
        config_path = config_path,
        output_dir = analysis_folder,
        bids_dir = bids_dir,
        blood_dir = blood_dir,
        cores = cores,
        save_logs = save_logs,
        notify = notify,
        ancillary_path = ancillary_path
      )

    } else if (current_step == "reference_tac") {
      result$messages <- c(result$messages, "\n=== Running Reference TAC ===")
      step_result <- execute_reference_tac_step(
        config_path = config_path,
        output_dir = analysis_folder,
        bids_dir = bids_dir,
        cores = cores,
        save_logs = save_logs,
        notify = notify
      )

    } else if (current_step %in% c("model1", "model2", "model3")) {
      model_num <- stringr::str_extract(current_step, "\\d+")
      result$messages <- c(result$messages, paste0("\n=== Running Model ", model_num, " ==="))
      step_result <- execute_model_step(
        config_path = config_path,
        model_num = model_num,
        output_dir = analysis_folder,
        bids_dir = bids_dir,
        blood_dir = blood_dir,
        cores = cores,
        save_logs = save_logs,
        notify = notify,
        ancillary_path = ancillary_path
      )
    }

    # Store step result
    if (!is.null(step_result)) {
      result$step_results[[current_step]] <- step_result
      result$messages <- c(result$messages, step_result$message)

      # If any step fails and we're running all steps, stop execution
      if (!step_result$success && is.null(step)) {
        result$messages <- c(result$messages, paste("Step", current_step, "failed. Stopping pipeline execution."))
        return(result)
      }
    }
  }

  # Check if all requested steps succeeded
  all_succeeded <- all(sapply(result$step_results, function(x) x$success))

  if (all_succeeded) {
    result$success <- TRUE
    result$messages <- c(result$messages, "\n=== Pipeline Completed Successfully ===")
  } else {
    result$messages <- c(result$messages, "\n=== Pipeline Completed with Errors ===")
  }

  return(result)
}
