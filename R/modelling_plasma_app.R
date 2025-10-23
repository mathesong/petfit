#' Run petfit Plasma Input Modelling App
#'
#' @description Launch the petfit modelling configuration interface for setting up kinetic models with plasma input data
#'
#' @param bids_dir Character string path to the BIDS directory (default: NULL)
#' @param derivatives_dir Character string path to the derivatives folder (default: bids_dir/derivatives)
#' @param blood_dir Character string path to the blood data directory (default: NULL)
#' @param subfolder Character string name for analysis subfolder (default: "Primary_Analysis")
#' @param config_file Character string path to existing config file (optional)
#' @export
modelling_plasma_app <- function(bids_dir = NULL, derivatives_dir = NULL, blood_dir = NULL, subfolder = "Primary_Analysis", config_file = NULL) {
  
  # Set derivatives directory logic
  if (is.null(derivatives_dir)) {
    if (is.null(bids_dir)) {
      stop("Either bids_dir or derivatives_dir must be provided", call. = FALSE)
    }
    # Default: bids_dir/derivatives
    derivatives_dir <- file.path(bids_dir, "derivatives")
  }
  
  # Validate directories
  if (!is.null(bids_dir) && !dir.exists(bids_dir)) {
    stop(paste("BIDS directory does not exist:", bids_dir), call. = FALSE)
  }
  
  # Normalize paths
  if (!is.null(bids_dir)) {
    bids_dir <- normalizePath(bids_dir, mustWork = FALSE)
  }
  derivatives_dir <- normalizePath(derivatives_dir, mustWork = FALSE)
  
  # Create derivatives directory if it doesn't exist
  if (!dir.exists(derivatives_dir)) {
    dir.create(derivatives_dir, recursive = TRUE)
    cat("Created derivatives directory:", derivatives_dir, "\n")
  }
  
  # Set petfit directory (within derivatives)
  petfit_dir <- file.path(derivatives_dir, "petfit")
  
  if (!dir.exists(petfit_dir)) {
    dir.create(petfit_dir, recursive = TRUE)
    cat("Created petfit directory:", petfit_dir, "\n")
  }
  
  # Normalize petfit path
  petfit_dir <- normalizePath(petfit_dir, mustWork = FALSE)
  
  # Validate config file if provided
  if (!is.null(config_file) && !file.exists(config_file)) {
    stop(paste("Config file does not exist:", config_file), call. = FALSE)
  }
  
  # Validate blood_dir if provided
  if (!is.null(blood_dir) && !dir.exists(blood_dir)) {
    stop(paste("Blood directory cannot be found:", blood_dir), call. = FALSE)
  }
  
  # Print configuration
  cat("Starting Modelling App:\n")
  if (!is.null(bids_dir)) {
    cat("  BIDS directory:", bids_dir, "\n")
  }
  cat("  Derivatives directory:", derivatives_dir, "\n")
  cat("  petfit directory:", petfit_dir, "\n")
  if (!is.null(blood_dir)) {
    cat("  Blood directory:", blood_dir, "\n")
  }
  if (!is.null(config_file)) {
    cat("  Config file:", config_file, "\n")
  }

  # Validate and resolve analysis folder based on configuration type
  expected_config_type <- "plasma input"

  validate_folder <- function(folder_path) {
    config_path <- file.path(folder_path, "desc-petfitoptions_config.json")

    if (!dir.exists(folder_path)) {
      return(list(exists = FALSE, compatible = TRUE, config_type = NULL))
    }

    if (!file.exists(config_path)) {
      return(list(exists = TRUE, compatible = TRUE, config_type = NULL))
    }

    tryCatch({
      config <- jsonlite::read_json(config_path)
      config_type <- config$modelling_configuration_type

      if (is.null(config_type)) {
        return(list(exists = TRUE, compatible = TRUE, config_type = "unknown"))
      }

      compatible <- (config_type == expected_config_type)
      return(list(exists = TRUE, compatible = compatible, config_type = config_type))
    }, error = function(e) {
      return(list(exists = TRUE, compatible = FALSE, config_type = "corrupted"))
    })
  }

  # Resolve subfolder based on validation
  if (subfolder == "Primary_Analysis") {
    primary_check <- validate_folder(file.path(petfit_dir, "Primary_Analysis"))

    if (primary_check$exists && !primary_check$compatible) {
      # Primary exists with wrong type, try Secondary
      cat("WARNING: Primary_Analysis contains", primary_check$config_type, "configuration.\n")
      cat("Attempting to use Secondary_Analysis instead.\n")

      secondary_check <- validate_folder(file.path(petfit_dir, "Secondary_Analysis"))

      if (secondary_check$exists && !secondary_check$compatible) {
        # Both Primary and Secondary have wrong types
        stop("Both Primary_Analysis and Secondary_Analysis contain incompatible configurations. Please specify a different analysis folder name.", call. = FALSE)
      }

      # Use Secondary_Analysis
      subfolder <- "Secondary_Analysis"
      cat("Using Secondary_Analysis for this analysis.\n")
    }
  } else {
    # User specified custom folder name, validate it
    folder_check <- validate_folder(file.path(petfit_dir, subfolder))

    if (folder_check$exists && !folder_check$compatible) {
      stop(sprintf("Analysis folder '%s' already exists but contains configuration for %s modelling. Please choose a different folder name.",
                   subfolder, folder_check$config_type), call. = FALSE)
    }
  }

  cat("  Analysis subfolder:", subfolder, "\n")

  # Create output directory if it doesn't exist
  output_dir <- file.path(petfit_dir, subfolder)
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    cat("Created output directory:", output_dir, "\n")
  }
  
  # Fixed filename
  out_filename <- "petfit_config.json"
  
  # Check for combined TACs file first
  combined_tacs_file <- file.path(petfit_dir, "desc-combinedregions_tacs.tsv")
  
  if (file.exists(combined_tacs_file)) {
    cat("Found combined TACs file:", combined_tacs_file, "\n")
    tacs_list <- tibble::tibble(
      tacs_filedescription = paste0("Combined TACs: ", basename(combined_tacs_file))
    )
  } else {
    cat("No combined TACs file found. Checking for petfit_regions.tsv...\n")
    
    # Look for petfit_regions.tsv file using read/write logic
    # Always write to petfit_dir (derivatives/petfit)
    write_config_dir <- petfit_dir
    
    # For reading: check derivatives/petfit first, then BIDS code directory
    read_config_dirs <- c(petfit_dir)
    if (!is.null(bids_dir)) {
      read_config_dirs <- c(read_config_dirs, file.path(bids_dir, "code", "petfit"))
    }
    
    # Find existing regions file by checking read directories in order
    existing_regions_file <- NULL
    for (dir in read_config_dirs) {
      potential_file <- file.path(dir, "petfit_regions.tsv")
      if (file.exists(potential_file)) {
        existing_regions_file <- potential_file
        break
      }
    }
    
    if (!is.null(existing_regions_file)) {
      cat("Found petfit_regions.tsv. Generating combined TACs file...\n")
      
      tryCatch({
        # Generate combined TACs using existing functionality
        petfit_regions_files_path <- file.path(write_config_dir, "petfit_regions_files.tsv")
        
        # Load participant data if BIDS directory is provided
        participant_data <- NULL
        if (!is.null(bids_dir)) {
          participant_data <- load_participant_data(bids_dir)
          if (!is.null(participant_data)) {
            cat("Loaded participant data with", nrow(participant_data$data), "participants\n")
          }
        }
        
        # Create file mapping
        regions_files_data <- create_petfit_regions_files(existing_regions_file, derivatives_dir)
        
        # Generate combined TACs with participant data and BIDS directory
        combined_data <- create_petfit_combined_tacs(petfit_regions_files_path, derivatives_dir, petfit_dir, bids_dir, participant_data)
        
        cat("Successfully generated combined TACs file.\n")
        tacs_list <- tibble::tibble(
          tacs_filedescription = paste0("Generated Combined TACs: desc-combinedregions_tacs.tsv")
        )
      }, error = function(e) {
        cat("Error generating combined TACs:", e$message, "\n")
        cat("Please use the region definition app first to create regions.\n")
        tacs_list <- tibble::tibble(tacs_filedescription = character(0))
      })
    } else {
      cat("No petfit_regions.tsv found. Please use the region definition app first.\n")
      tacs_list <- tibble::tibble(tacs_filedescription = character(0))
    }
  }
  
  ui <- fluidPage(theme = shinythemes::shinytheme("flatly"),
    
    # App title ----
    titlePanel("PETFit Kinetic Modelling Configuration (Plasma Input)"),
    
    # Tab panel for all options ----
    tabsetPanel(type = "tabs",
                # Tab panel for data definition ----
                tabPanel("Data Definition",
                         br(),
                         # h4("Data Definition"),
                         # p("Define and create the analysis dataset from the combined TACs file. This step allows you to subset the data and generate individual TACs files for your specific analysis.",
                         #   style = "font-size:14px;"
                         # ),
                         # br(),
                         h3("Subsetting"),
                         p(glue::glue("Use these options to apply this analysis to a subset of the data. ",
                                "Values should be separated by semi-colons (e.g., 01;02). ",
                                "All measurements fulfilling all the conditions will ",
                                "be included. Leave options blank if no subsetting is desired, ",
                                "i.e. leaving sub blank implies that all subjects should ",
                                "be included."),
                           style = "font-size:14px;"
                         ),
                         br(),
                         fluidRow(
                           column(4, textInput(inputId = "subset_sub", label = "sub", value = "")),
                           column(4, textInput(inputId = "subset_ses", label = "ses", value = "")),
                           column(4, textInput(inputId = "subset_task", label = "task", value = ""))
                         ),
                         fluidRow(
                           column(4, textInput(inputId = "subset_trc", label = "trc", value = "")),
                           column(4, textInput(inputId = "subset_rec", label = "rec", value = "")),
                           column(4, textInput(inputId = "subset_run", label = "run", value = ""))
                         ),
                         fluidRow(
                           column(12, textInput(inputId = "subset_regions", label = "Regions", value = ""))
                         ),
                         
                         hr(),
                         h3("Create Data"),
                         p("Generate individual TACs files for each measurement and create a report plotting the selected data.",
                           style = "font-size:14px;"
                         ),
                         br(),
                         actionButton("run_subset", "▶ Create Analysis Data", class = "btn-success btn-lg")
                ),
                # Tab panel for weights ----
                    tabPanel("Weights Definition",
                             br(),
                             h3("Region for Weights Calculation"),
                             p("Select the region to use for calculating weights. Regional means are volume-weighted averages.",
                               style = "font-size:14px;"
                             ),
                             br(),
                             fluidRow(
                               column(8,
                                 div(style = "width: 100%;",
                                   selectInput("weights_region_type", "Region Source:",
                                             choices = c("Single region" = "single",
                                                       "Mean of analysis regions" = "mean_combined", 
                                                       "Mean of external segmentation" = "external"),
                                             selected = "external",
                                             width = "100%")
                                 )
                               ),
                               column(4,
                                 conditionalPanel(
                                   condition = "input.weights_region_type == 'single'",
                                   textInput("weights_region", "Region Name:",
                                           value = "",
                                           placeholder = "e.g., Caudate",
                                           width = "100%")
                                 ),
                                 conditionalPanel(
                                   condition = "input.weights_region_type == 'mean_combined'",
                                   div(
                                     p(strong("All analysis regions will be averaged"), style = "font-size:12px; color:#666;")
                                   )
                                 ),
                                 conditionalPanel(
                                   condition = "input.weights_region_type == 'external'",
                                   selectInput("weights_external_tacs", "Select Segmentation:",
                                             choices = c("Loading..." = ""),
                                             selected = "",
                                             width = "100%")
                                 )
                               )
                             ),
                             
                             hr(),
                             h3("Radioisotope"),
                             p("Select the radioisotope for decay correction. Half-life is used for time-based weighting methods.",
                               style = "font-size:14px;"
                             ),
                             br(),
                             fluidRow(
                               column(8,
                                 radioButtons("weights_radioisotope", "",
                                            choices = c("C11 (20.4 min)" = "C11",
                                                      "O15 (2.05 min)" = "O15", 
                                                      "F18 (109.8 min)" = "F18",
                                                      "Other (specify half-life)" = "Other"),
                                            selected = "C11", inline = TRUE)
                               ),
                               column(4,
                                 conditionalPanel(
                                   condition = "input.weights_radioisotope == 'Other'",
                                   numericInput("weights_halflife", "Half-life (minutes):",
                                              value = 20.4, min = 0.1, max = 1000, step = 0.1)
                                 )
                               )
                             ),
                             
                             hr(),
                             h3("Weighting Method"),
                             p("Choose the mathematical method for calculating frame weights.",
                               style = "font-size:14px;"
                             ),
                             br(),
                             fluidRow(
                               column(8,
                                 div(style = "width: 100%;",
                                   selectInput("weights_method", "Method:",
                                             choices = c("0. Uniform (all weights = 1)" = "0",
                                                       "1. frame_dur / tac_uncor" = "1",
                                                       "2. sqrt(frame_dur * tac_uncor) (default)" = "2",
                                                       "3. sqrt(frame_dur) / tac" = "3", 
                                                       "4. sqrt(frame_dur)" = "4",
                                                       "5. frame_dur * exp(-ln(2)/halflife)" = "5",
                                                       "6. frame_dur / tac" = "6",
                                                       "7. frame_dur" = "7",
                                                       "8. frame_dur^2 / tac_uncor" = "8",
                                                       "9. (frame_dur^2 / (frame_dur * tac)) * corrections^2" = "9",
                                                       "Custom formula" = "custom"),
                                             selected = "2",
                                             width = "100%")
                                 )
                               ),
                               column(4,
                                 numericInput("weights_minweight", "Minimum Weight:",
                                            value = 0.25, min = 0.001, max = 1, step = 0.001)
                               )
                             ),
                             
                             conditionalPanel(
                               condition = "input.weights_method == 'custom'",
                               br(),
                               div(
                                 h4("Custom Formula"),
                                 p("Define a custom weighting formula using available variables:",
                                   style = "font-size:14px; margin-bottom:10px;"),
                                 textAreaInput("weights_custom_formula", "",
                                             value = "",
                                             rows = 2,
                                             placeholder = "e.g., (frame_dur^2) / tac_uncor")
                               )
                             ),
                             
                             br(),
                             div(
                               p(strong("Available variables:"), style = "font-size:13px; margin-bottom:5px;"),
                               div(
                                 p("• ", strong("frame_dur:"), " Frame duration in seconds", style = "font-size:11px; margin:2px 0;"),
                                 p("• ", strong("frame_mid:"), " Frame midpoint time in seconds", style = "font-size:11px; margin:2px 0;"),
                                 p("• ", strong("tac:"), " Time activity curve (decay-corrected)", style = "font-size:11px; margin:2px 0;"),
                                 p("• ", strong("tac_uncor:"), " Time activity curve (decay-uncorrected)", style = "font-size:11px; margin:2px 0;"),
                                 p("• ", strong("corrections:"), " Decay correction factors", style = "font-size:11px; margin:2px 0;"),
                                 style = "background:#f8f9fa; padding:10px; border-left:3px solid #007bff; margin:10px 0;"
                               )
                             ),
                             
                             hr(),
                             h3("Calculate Weights"),
                             p("Calculate weights and generate a report plotting the selected data.",
                               style = "font-size:14px;"
                             ),
                             br(),
                             actionButton("run_weights", "▶ Calculate Weights", class = "btn-success btn-lg")
                    ),
                    # Tab panel for delay ----
                    tabPanel("Fit Delay",
                             
                             # p("Here we estimate the delay between the TAC data and the blood input data.",
                             #   style = "font-size:14px;"),
                             # Blood data status (simple display)
                             div(id = "delay_blood_status",
                                 style = "margin-bottom: 20px; padding: 15px; border: 1px solid #ddd; border-radius: 5px; background-color: #f9f9f9;",
                                 uiOutput("delay_blood_status_display")
                             ),
                             
                             # h3("Delay Fitting Configuration"),
                             # br(),
                             p("The recommended first approach is to fit a simple model (i.e. 1TCM) to the early frames of the acquisition, typically with weights turned off and with vB set to a reasonable fixed value, and to calculate delay from the median for multiple regions. Poor performance is usually resolved by altering the time window, using weights, or using another model.",
                               style = "font-size: 14px; margin-bottom: 15px;"),
                                 
                                 fluidRow(
                                   column(6,
                                     h4("Delay Estimation Approach"),
                                     selectInput("delay_model", "",
                                                choices = c("None (no delay fitting)" = "none",
                                                          # "Linear 2TCM Profile from Single Representative TAC (Very Quick)" = "lin2tcm_singletac",
                                                          "1TCM Delay from Single Representative TAC (Quick)" = "1tcm_singletac",
                                                          "2TCM Delay from Single Representative TAC (Less Quick)" = "2tcm_singletac",
                                                          "1TCM Median Delay from Multiple Regions (Recommended, Slow)" = "1tcm_median",
                                                          "2TCM Median Delay from Multiple Regions (Very Slow)" = "2tcm_median"),
                                                selected = "1tcm_median",
                                                width = "100%"),
                                     conditionalPanel(
                                       condition = "input.delay_model == '1tcm_singletac' || input.delay_model == '2tcm_singletac'",
                                       p("Note: \"Single Representative TAC\" methods use the same TAC that was used for weights calculation.", 
                                         style = "font-size: 12px; color: #666; margin-top: 5px;")
                                     ),
                                     
                                     # Conditional input for Multiple TACs approaches
                                     conditionalPanel(
                                       condition = "input.delay_model == '1tcm_median' || input.delay_model == '2tcm_median'",
                                       br(),
                                       textInput("delay_multiple_regions", "Regions for Multiple Regions Analysis (Optional):",
                                               value = "",
                                               placeholder = "e.g., Frontal;Temporal;Hippocampus;Striatum",
                                               width = "100%"),
                                       p("Optional: Define a subset of regions. Leave blank to estimate delay for all regions.", 
                                         style = "font-size: 12px; color: #666; margin-top: 5px;")
                                     )
                                   ),
                                   column(6,
                                     h4("Time Window"),
                                     numericInput("delay_time_window", "Minutes of TAC data to fit delay over:",
                                                value = 5, min = 1, max = 120, step = 0.5),
                                     # p("It is recommended to restrict the fitting to the early phase of the PET measurement to optimise sensitivity.", 
                                     #   style = "font-size: 12px; color: #666; margin-top: 5px;")
                                   )
                                 ),
                                 
                                 hr(),
                                 h3("Parameter Settings"),
                                 br(),
                                 fluidRow(
                                   column(4,
                                     h4("Blood Volume (vB)"),
                                     numericInput("delay_vB", "vB value:",
                                                value = 0.05, min = 0, max = 1, step = 0.01),
                                     checkboxInput("delay_fit_vB", "Fit vB parameter", value = FALSE)
                                   ),
                                   column(4,
                                     h4("Blood Time Shift Search Range"),
                                     p("Upper and lower limits for range for blood time shift (minutes):", 
                                       style = "font-size: 12px; color: #666; margin-bottom: 10px;"),
                                     numericInput("delay_inpshift_lower", "Lower limit:",
                                                value = -0.5, min = -5, max = 0, step = 0.1),
                                     numericInput("delay_inpshift_upper", "Upper limit:",
                                                value = 0.5, min = 0, max = 5, step = 0.1)
                                   ),
                                   column(4,
                                     h4("Weighting"),
                                     checkboxInput("delay_use_weights", "Use frame weighting", value = FALSE),
                                     br(),
                                   )
                                 ),
                             
                             hr(),
                             actionButton("run_delay", "▶ Estimate Delay", class = "btn-success btn-lg")
                    ),
                    # Tab panel for tstar ----
                    tabPanel("Find t*",
                             br(),
                             # h4("t* Finder"),
                             p("This functionality is coming soon.", 
                               style = "font-size:16px; font-weight:bold; color:#0066cc; margin-bottom:20px;"),
                             p("The t* finder helps determine the optimal start time (t*) for linear kinetic models by analyzing when equilibrium conditions are met.",
                               style = "font-size:14px; margin-bottom:20px;"),
                             
                             selectInput("tstar_model", "Select a model for determining t*:",
                                         choices = c("No Model Selected" = "none",
                                                     "Logan" = "Logan",
                                                     "MA1" = "MA1"),
                                         selected = "none",
                                         width = "60%")
                    ),
                    # Tab panel for Model 1 ----
                    tabPanel("Model 1",
                             h4(""),
                             p(glue::glue("Non-linear models fit full compartment models. ",
                                    "Linear models are faster and tend to be ",
                                    "more robust to measurement error, however they provide fewer outcome parameters ",
                                    "and can be slightly biased.")
                             ),
                             # Model selection drop-down menu
                             selectInput("button", "Select a model:",
                                         choices = c("No Model 1" = "none",
                                                     "1TCM (Non-linear, Reversible binding)" = "1TCM",
                                                     "2TCM (Non-linear, Reversible binding)" = "2TCM",
                                                     "2TCM_irr (Non-linear, Irreversible binding)" = "2TCM_irr",
                                                     "Logan (Linear, Reversible binding)" = "Logan",
                                                     "MA1 (Linear, Reversible binding)" = "MA1",
                                                     "Patlak (Linear, Irreversible binding)" = "Patlak"
                                         ),
                                         selected = "none"),
                             # 1TCM selection panel
                             conditionalPanel(
                               condition = "input.button == '1TCM'",
                               fluidRow(
                                 column(3, offset = 0, numericInput("K1.start", "K1.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("K1.lower", "K1.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("K1.upper", "K1.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("k2.start", "k2.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k2.lower", "k2.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k2.upper", "k2.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("vB.start", "vB.start", value = 0.05, min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("vB.lower", "vB.lower", value = 0.01, min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("vB.upper", "vB.upper", value = 0.1, min = 0, step=.001)),
                               ),
                               checkboxInput("vB.fit", "Fit vB (otherwise use vB.start)", value = TRUE),
                               
                               # Time/Frame Selection
                               h4("TAC Subset Selection"),
                               p("Specify subset of TAC data for fitting (optional). Leave blank to use all frames."),
                               radioButtons("subset_type", "Selection Method:",
                                           choices = list("Frame Numbers" = "frame", 
                                                         "Time Points (minutes)" = "time"),
                                           selected = "time", inline = TRUE),
                               fluidRow(
                                 column(6, numericInput("start_point", "Start Point", value = NULL, min = 0, step = 0.1)),
                                 column(6, numericInput("end_point", "End Point", value = NULL, min = 0, step = 0.1))
                               ),
                               
                               # Multstart Options
                               h4("Multiple Starting Points"),
                               p("Fit model multiple times with different starting parameters to avoid local minima."),
                               numericInput("multstart_iter", "Number of Iterations", value = 1, min = 1, max = 50, step = 1),
                               
                             ),
                             # 2TCM selection panel
                             conditionalPanel(
                               condition = "input.button == '2TCM'",
                               fluidRow(
                                 column(3, offset = 0, numericInput("K1.start", "K1.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("K1.lower", "K1.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("K1.upper", "K1.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("k2.start", "k2.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k2.lower", "k2.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k2.upper", "k2.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("k3.start", "k3.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k3.lower", "k3.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k3.upper", "k3.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("k4.start", "k4.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k4.lower", "k4.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k4.upper", "k4.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("vB.start", "vB.start", value = 0.05, min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("vB.lower", "vB.lower", value = 0.01, min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("vB.upper", "vB.upper", value = 0.1, min = 0, step=.001)),
                               ),
                               checkboxInput("vB.fit", "Fit vB (otherwise use vB.start)", value = TRUE),
                               
                               # Time/Frame Selection
                               h4("TAC Subset Selection"),
                               p("Specify subset of TAC data for fitting (optional). Leave blank to use all frames."),
                               radioButtons("subset_type", "Selection Method:",
                                           choices = list("Frame Numbers" = "frame", 
                                                         "Time Points (minutes)" = "time"),
                                           selected = "time", inline = TRUE),
                               fluidRow(
                                 column(6, numericInput("start_point", "Start Point", value = NULL, min = 0, step = 0.1)),
                                 column(6, numericInput("end_point", "End Point", value = NULL, min = 0, step = 0.1))
                               ),
                               
                               # Multstart Options
                               h4("Multiple Starting Points"),
                               p("Fit model multiple times with different starting parameters to avoid local minima."),
                               numericInput("multstart_iter", "Number of Iterations", value = 1, min = 1, max = 50, step = 1),
                               
                             ),
                             # 2TCM_irr selection panel
                             conditionalPanel(
                               condition = "input.button == '2TCM_irr'",
                               fluidRow(
                                 column(3, offset = 0, numericInput("K1.start", "K1.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("K1.lower", "K1.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("K1.upper", "K1.upper", value = 1,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("k2.start", "k2.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k2.lower", "k2.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k2.upper", "k2.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("k3.start", "k3.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k3.lower", "k3.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k3.upper", "k3.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("vB.start", "vB.start", value = 0.05, min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("vB.lower", "vB.lower", value = 0.01, min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("vB.upper", "vB.upper", value = 0.1, min = 0, step=.001)),
                               ),
                               checkboxInput("vB.fit", "Fit vB (otherwise use vB.start)", value = TRUE),

                               # Time/Frame Selection
                               h4("TAC Subset Selection"),
                               p("Specify subset of TAC data for fitting (optional). Leave blank to use all frames."),
                               radioButtons("subset_type", "Selection Method:",
                                           choices = list("Frame Numbers" = "frame",
                                                         "Time Points (minutes)" = "time"),
                                           selected = "time", inline = TRUE),
                               fluidRow(
                                 column(6, numericInput("start_point", "Start Point", value = NULL, min = 0, step = 0.1)),
                                 column(6, numericInput("end_point", "End Point", value = NULL, min = 0, step = 0.1))
                               ),

                               # Multstart Options
                               h4("Multiple Starting Points"),
                               p("Fit model multiple times with different starting parameters to avoid local minima."),
                               numericInput("multstart_iter", "Number of Iterations", value = 1, min = 1, max = 50, step = 1),

                             ),
                             # Logan selection panel
                             conditionalPanel(
                               condition = "input.button == 'Logan'",
                               h4("t* Definition"),
                               p("Define t* (time point for linear analysis start) using frame numbers or time."),
                               radioButtons("tstar_type", "",
                                           choices = list("Number of Frames (from the end)" = "frame", 
                                                         "Time Point (minutes)" = "time"),
                                           selected = "frame", inline = TRUE),
                               numericInput("tstar", "t* (0 for all frames)", value = 10, min = 0, step = 1),
                               
                               h4("Other Parameters"),
                               selectInput("vB_source", "vB Parameter Source:",
                                          choices = list("Set vB" = "set"),
                                          selected = "set"),
                               conditionalPanel(
                                 condition = "input.vB_source == 'set'",
                                 numericInput("vB_value", "vB Value", value = 0.05, min = 0, max = 1, step = 0.001)
                               ),
                               
                               # TAC Subset Selection
                               h4("TAC Subset Selection"),
                               p("Specify subset of TAC data for fitting (optional). Leave blank to use all frames."),
                               radioButtons("subset_type", "Selection Method:",
                                           choices = list("Frame Numbers" = "frame", 
                                                         "Time Points (minutes)" = "time"),
                                           selected = "time", inline = TRUE),
                               fluidRow(
                                 column(6, numericInput("start_point", "Start Point", value = NULL, min = 0, step = 0.1)),
                                 column(6, numericInput("end_point", "End Point", value = NULL, min = 0, step = 0.1))
                               )
                             ),
                             
                             # MA1 selection panel
                             conditionalPanel(
                               condition = "input.button == 'MA1'",
                               h4("t* Definition"),
                               p("Define t* (time point for linear analysis start) using frame numbers or time."),
                               radioButtons("tstar_type", "",
                                           choices = list("Number of Frames (from the end)" = "frame", 
                                                         "Time Point (minutes)" = "time"),
                                           selected = "frame", inline = TRUE),
                               numericInput("tstar", "t* (0 for all frames)", value = 10, min = 0, step = 1),
                               
                               h4("Other Parameters"),
                               selectInput("vB_source", "vB Parameter Source:",
                                          choices = list("Set vB" = "set"),
                                          selected = "set"),
                               conditionalPanel(
                                 condition = "input.vB_source == 'set'",
                                 numericInput("vB_value", "vB Value", value = 0.05, min = 0, max = 1, step = 0.001)
                               ),
                               
                               # TAC Subset Selection
                               h4("TAC Subset Selection"),
                               p("Specify subset of TAC data for fitting (optional). Leave blank to use all frames."),
                               radioButtons("subset_type", "Selection Method:",
                                           choices = list("Frame Numbers" = "frame", 
                                                         "Time Points (minutes)" = "time"),
                                           selected = "time", inline = TRUE),
                               fluidRow(
                                 column(6, numericInput("start_point", "Start Point", value = NULL, min = 0, step = 0.1)),
                                 column(6, numericInput("end_point", "End Point", value = NULL, min = 0, step = 0.1))
                               )
                             ),

                             # Patlak selection panel
                             conditionalPanel(
                               condition = "input.button == 'Patlak'",
                               h4("t* Definition"),
                               p("Define t* (time point for linear analysis start) using frame numbers or time."),
                               radioButtons("tstar_type", "",
                                           choices = list("Number of Frames (from the end)" = "frame",
                                                         "Time Point (minutes)" = "time"),
                                           selected = "frame", inline = TRUE),
                               numericInput("tstar", "t* (0 for all frames)", value = 10, min = 0, step = 1),

                               h4("Other Parameters"),
                               selectInput("vB_source", "vB Parameter Source:",
                                          choices = list("Set vB" = "set"),
                                          selected = "set"),
                               conditionalPanel(
                                 condition = "input.vB_source == 'set'",
                                 numericInput("vB_value", "vB Value", value = 0.05, min = 0, max = 1, step = 0.001)
                               ),

                               # TAC Subset Selection
                               h4("TAC Subset Selection"),
                               p("Specify subset of TAC data for fitting (optional). Leave blank to use all frames."),
                               radioButtons("subset_type", "Selection Method:",
                                           choices = list("Frame Numbers" = "frame",
                                                         "Time Points (minutes)" = "time"),
                                           selected = "time", inline = TRUE),
                               fluidRow(
                                 column(6, numericInput("start_point", "Start Point", value = NULL, min = 0, step = 0.1)),
                                 column(6, numericInput("end_point", "End Point", value = NULL, min = 0, step = 0.1))
                               )
                             ),

                             hr(),
                             conditionalPanel(
                               condition = "input.button != 'none'",
                               actionButton("run_model1", "▶ Fit Model 1", class = "btn-success btn-lg")
                             )
                    ),
                    # Tab panel for Model 2 ----
                    tabPanel("Model 2",
                             h4("Model 2"),
                             p(glue::glue("Choose a kinetic model for fitting. ",
                                   "Linear models are faster and tend to be ",
                                   "more robust to measurement error, however they provide fewer outcome parameters ",
                                   "and can be slightly biased. Non-linear models fit full compartment models.")
                             ),
                             # Model selection drop-down menu
                             selectInput("button2", "Select a model:",
                                         choices = c("No Model 2" = "none",
                                                     "1TCM (Non-linear, Reversible binding)" = "1TCM",
                                                     "2TCM (Non-linear, Reversible binding)" = "2TCM",
                                                     "2TCM_irr (Non-linear, Irreversible binding)" = "2TCM_irr",
                                                     "Logan (Linear, Reversible binding)" = "Logan",
                                                     "MA1 (Linear, Reversible binding)" = "MA1",
                                                     "Patlak (Linear, Irreversible binding)" = "Patlak"
                                         ),
                                         selected = "none"),
                             # 1TCM selection panel
                             conditionalPanel(
                               condition = "input.button2 == '1TCM'",
                               fluidRow(
                                 column(3, offset = 0, numericInput("K1.start2", "K1.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("K1.lower2", "K1.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("K1.upper2", "K1.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("k2.start2", "k2.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k2.lower2", "k2.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k2.upper2", "k2.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("vB.start2", "vB.start", value = 0.05, min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("vB.lower2", "vB.lower", value = 0.01, min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("vB.upper2", "vB.upper", value = 0.1, min = 0, step=.001)),
                               ),
                               selectInput("vB_source2", "vB Parameter Source:",
                                          choices = list(
                                            "Fit vB" = "fit",
                                            "Set vB (uses vB.start)" = "set",
                                            "Inherit vB from Model 1 (Regional)" = "inherit_model1_regional",
                                            "Inherit vB from Model 1 (Mean Across Regions)" = "inherit_model1_mean",
                                            "Inherit vB from Model 1 (Median Across Regions)" = "inherit_model1_median"
                                          ),
                                          selected = "fit"),
                               
                               # Time/Frame Selection
                               h4("TAC Subset Selection"),
                               p("Specify subset of TAC data for fitting (optional). Leave blank to use all frames."),
                               radioButtons("subset_type2", "Selection Method:",
                                           choices = list("Frame Numbers" = "frame", 
                                                         "Time Points (minutes)" = "time"),
                                           selected = "time", inline = TRUE),
                               fluidRow(
                                 column(6, numericInput("start_point2", "Start Point", value = NULL, min = 0, step = 0.1)),
                                 column(6, numericInput("end_point2", "End Point", value = NULL, min = 0, step = 0.1))
                               ),
                               
                               # Multstart Options
                               h4("Multiple Starting Points"),
                               p("Fit model multiple times with different starting parameters to avoid local minima."),
                               numericInput("multstart_iter2", "Number of Iterations", value = 1, min = 1, max = 50, step = 1),
                               
                             ),
                             # 2TCM selection panel
                             conditionalPanel(
                               condition = "input.button2 == '2TCM'",
                               fluidRow(
                                 column(3, offset = 0, numericInput("K1.start2", "K1.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("K1.lower2", "K1.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("K1.upper2", "K1.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("k2.start2", "k2.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k2.lower2", "k2.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k2.upper2", "k2.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("k3.start2", "k3.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k3.lower2", "k3.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k3.upper2", "k3.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("k4.start2", "k4.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k4.lower2", "k4.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k4.upper2", "k4.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("vB.start2", "vB.start", value = 0.05, min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("vB.lower2", "vB.lower", value = 0.01, min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("vB.upper2", "vB.upper", value = 0.1, min = 0, step=.001)),
                               ),
                               selectInput("vB_source2", "vB Parameter Source:",
                                          choices = list(
                                            "Fit vB" = "fit",
                                            "Set vB (uses vB.start)" = "set",
                                            "Inherit vB from Model 1 (Regional)" = "inherit_model1_regional",
                                            "Inherit vB from Model 1 (Mean Across Regions)" = "inherit_model1_mean",
                                            "Inherit vB from Model 1 (Median Across Regions)" = "inherit_model1_median"
                                          ),
                                          selected = "fit"),
                               
                               # Time/Frame Selection
                               h4("TAC Subset Selection"),
                               p("Specify subset of TAC data for fitting (optional). Leave blank to use all frames."),
                               radioButtons("subset_type2", "Selection Method:",
                                           choices = list("Frame Numbers" = "frame", 
                                                         "Time Points (minutes)" = "time"),
                                           selected = "time", inline = TRUE),
                               fluidRow(
                                 column(6, numericInput("start_point2", "Start Point", value = NULL, min = 0, step = 0.1)),
                                 column(6, numericInput("end_point2", "End Point", value = NULL, min = 0, step = 0.1))
                               ),
                               
                               # Multstart Options
                               h4("Multiple Starting Points"),
                               p("Fit model multiple times with different starting parameters to avoid local minima."),
                               numericInput("multstart_iter2", "Number of Iterations", value = 1, min = 1, max = 50, step = 1),
                               
                             ),
                             # 2TCM_irr selection panel
                             conditionalPanel(
                               condition = "input.button2 == '2TCM_irr'",
                               fluidRow(
                                 column(3, offset = 0, numericInput("K1.start2", "K1.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("K1.lower2", "K1.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("K1.upper2", "K1.upper", value = 1,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("k2.start2", "k2.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k2.lower2", "k2.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k2.upper2", "k2.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("k3.start2", "k3.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k3.lower2", "k3.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k3.upper2", "k3.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("vB.start2", "vB.start", value = 0.05, min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("vB.lower2", "vB.lower", value = 0.01, min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("vB.upper2", "vB.upper", value = 0.1, min = 0, step=.001)),
                               ),
                               checkboxInput("vB.fit2", "Fit vB (otherwise use vB.start)", value = TRUE),

                               # Time/Frame Selection
                               h4("TAC Subset Selection"),
                               p("Specify subset of TAC data for fitting (optional). Leave blank to use all frames."),
                               radioButtons("subset_type2", "Selection Method:",
                                           choices = list("Frame Numbers" = "frame",
                                                         "Time Points (minutes)" = "time"),
                                           selected = "time", inline = TRUE),
                               fluidRow(
                                 column(6, numericInput("start_point2", "Start Point", value = NULL, min = 0, step = 0.1)),
                                 column(6, numericInput("end_point2", "End Point", value = NULL, min = 0, step = 0.1))
                               ),

                               # Multstart Options
                               h4("Multiple Starting Points"),
                               p("Fit model multiple times with different starting parameters to avoid local minima."),
                               numericInput("multstart_iter2", "Number of Iterations", value = 1, min = 1, max = 50, step = 1),

                             ),
                             # Logan selection panel
                             conditionalPanel(
                               condition = "input.button2 == 'Logan'",
                               h4("t* Definition"),
                               p("Define t* (time point for linear analysis start) using frame numbers or time."),
                               radioButtons("tstar_type2", "",
                                           choices = list("Number of Frames (from the end)" = "frame", 
                                                         "Time Point (minutes)" = "time"),
                                           selected = "frame", inline = TRUE),
                               numericInput("tstar2", "t* (0 for all frames)", value = 10, min = 0, step = 1),
                               
                               h4("Other Parameters"),
                               selectInput("vB_source2", "vB Parameter Source:",
                                          choices = list(
                                            "Set vB" = "set",
                                            "Inherit vB from Model 1 (Regional)" = "inherit_model1_regional",
                                            "Inherit vB from Model 1 (Mean Across Regions)" = "inherit_model1_mean",
                                            "Inherit vB from Model 1 (Median Across Regions)" = "inherit_model1_median"
                                          ),
                                          selected = "set"),
                               conditionalPanel(
                                 condition = "input.vB_source2 == 'set'",
                                 numericInput("vB_value2", "vB Value", value = 0.05, min = 0, max = 1, step = 0.001)
                               ),
                               
                               # TAC Subset Selection
                               h4("TAC Subset Selection"),
                               p("Specify subset of TAC data for fitting (optional). Leave blank to use all frames."),
                               radioButtons("subset_type2", "Selection Method:",
                                           choices = list("Frame Numbers" = "frame", 
                                                         "Time Points (minutes)" = "time"),
                                           selected = "time", inline = TRUE),
                               fluidRow(
                                 column(6, numericInput("start_point2", "Start Point", value = NULL, min = 0, step = 0.1)),
                                 column(6, numericInput("end_point2", "End Point", value = NULL, min = 0, step = 0.1))
                               )
                             ),
                             # MA1 selection panel
                             conditionalPanel(
                               condition = "input.button2 == 'MA1'",
                               h4("t* Definition"),
                               p("Define t* (time point for linear analysis start) using frame numbers or time."),
                               radioButtons("tstar_type2", "",
                                           choices = list("Number of Frames (from the end)" = "frame", 
                                                         "Time Point (minutes)" = "time"),
                                           selected = "frame", inline = TRUE),
                               numericInput("tstar2", "t* (0 for all frames)", value = 10, min = 0, step = 1),
                               
                               h4("Other Parameters"),
                               selectInput("vB_source2", "vB Parameter Source:",
                                          choices = list(
                                            "Set vB" = "set",
                                            "Inherit vB from Model 1 (Regional)" = "inherit_model1_regional",
                                            "Inherit vB from Model 1 (Mean Across Regions)" = "inherit_model1_mean",
                                            "Inherit vB from Model 1 (Median Across Regions)" = "inherit_model1_median"
                                          ),
                                          selected = "set"),
                               conditionalPanel(
                                 condition = "input.vB_source2 == 'set'",
                                 numericInput("vB_value2", "vB Value", value = 0.05, min = 0, max = 1, step = 0.001)
                               ),
                               
                               # TAC Subset Selection
                               h4("TAC Subset Selection"),
                               p("Specify subset of TAC data for fitting (optional). Leave blank to use all frames."),
                               radioButtons("subset_type2", "Selection Method:",
                                           choices = list("Frame Numbers" = "frame", 
                                                         "Time Points (minutes)" = "time"),
                                           selected = "time", inline = TRUE),
                               fluidRow(
                                 column(6, numericInput("start_point2", "Start Point", value = NULL, min = 0, step = 0.1)),
                                 column(6, numericInput("end_point2", "End Point", value = NULL, min = 0, step = 0.1))
                               )
                             ),

                             # Patlak selection panel
                             conditionalPanel(
                               condition = "input.button2 == 'Patlak'",
                               h4("t* Definition"),
                               p("Define t* (time point for linear analysis start) using frame numbers or time."),
                               radioButtons("tstar_type2", "",
                                           choices = list("Number of Frames (from the end)" = "frame",
                                                         "Time Point (minutes)" = "time"),
                                           selected = "frame", inline = TRUE),
                               numericInput("tstar2", "t* (0 for all frames)", value = 10, min = 0, step = 1),

                               h4("Other Parameters"),
                               selectInput("vB_source2", "vB Parameter Source:",
                                          choices = list("Set vB" = "set"),
                                          selected = "set"),
                               conditionalPanel(
                                 condition = "input.vB_source2 == 'set'",
                                 numericInput("vB_value2", "vB Value", value = 0.05, min = 0, max = 1, step = 0.001)
                               ),

                               # TAC Subset Selection
                               h4("TAC Subset Selection"),
                               p("Specify subset of TAC data for fitting (optional). Leave blank to use all frames."),
                               radioButtons("subset_type2", "Selection Method:",
                                           choices = list("Frame Numbers" = "frame",
                                                         "Time Points (minutes)" = "time"),
                                           selected = "time", inline = TRUE),
                               fluidRow(
                                 column(6, numericInput("start_point2", "Start Point", value = NULL, min = 0, step = 0.1)),
                                 column(6, numericInput("end_point2", "End Point", value = NULL, min = 0, step = 0.1))
                               )
                             ),

                             hr(),
                             conditionalPanel(
                               condition = "input.button2 != 'none'",
                               actionButton("run_model2", "▶ Fit Model 2", class = "btn-success btn-lg")
                             )
                    ),
                    # Tab panel for Model 3 ----
                    tabPanel("Model 3",
                             h4("Model 3"),
                             p(glue::glue("Choose a kinetic model for fitting. ",
                                   "Linear models are faster and tend to be ",
                                   "more robust to measurement error, however they provide fewer outcome parameters ",
                                   "and can be slightly biased. Non-linear models fit full compartment models.")
                             ),
                             # Model selection drop-down menu
                             selectInput("button3", "Select a model:",
                                         choices = c("No Model 3" = "none",
                                                     "1TCM (Non-linear, Reversible binding)" = "1TCM",
                                                     "2TCM (Non-linear, Reversible binding)" = "2TCM",
                                                     "2TCM_irr (Non-linear, Irreversible binding)" = "2TCM_irr",
                                                     "Logan (Linear, Reversible binding)" = "Logan",
                                                     "MA1 (Linear, Reversible binding)" = "MA1",
                                                     "Patlak (Linear, Irreversible binding)" = "Patlak"
                                         ),
                                         selected = "none"),
                             # 1TCM selection panel
                             conditionalPanel(
                               condition = "input.button3 == '1TCM'",
                               fluidRow(
                                 column(3, offset = 0, numericInput("K1.start3", "K1.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("K1.lower3", "K1.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("K1.upper3", "K1.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("k2.start3", "k2.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k2.lower3", "k2.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k2.upper3", "k2.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("vB.start3", "vB.start", value = 0.05, min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("vB.lower3", "vB.lower", value = 0.01, min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("vB.upper3", "vB.upper", value = 0.1, min = 0, step=.001)),
                               ),
                               selectInput("vB_source3", "vB Parameter Source:",
                                          choices = list(
                                            "Fit vB" = "fit",
                                            "Set vB (uses vB.start)" = "set", 
                                            "Inherit vB from Model 1 (Regional)" = "inherit_model1_regional",
                                            "Inherit vB from Model 1 (Mean Across Regions)" = "inherit_model1_mean",
                                            "Inherit vB from Model 1 (Median Across Regions)" = "inherit_model1_median",
                                            "Inherit vB from Model 2 (Regional)" = "inherit_model2_regional",
                                            "Inherit vB from Model 2 (Mean Across Regions)" = "inherit_model2_mean",
                                            "Inherit vB from Model 2 (Median Across Regions)" = "inherit_model2_median"
                                          ),
                                          selected = "fit"),
                               
                               # Time/Frame Selection
                               h4("TAC Subset Selection"),
                               p("Specify subset of TAC data for fitting (optional). Leave blank to use all frames."),
                               radioButtons("subset_type3", "Selection Method:",
                                           choices = list("Frame Numbers" = "frame", 
                                                         "Time Points (minutes)" = "time"),
                                           selected = "time", inline = TRUE),
                               fluidRow(
                                 column(6, numericInput("start_point3", "Start Point", value = NULL, min = 0, step = 0.1)),
                                 column(6, numericInput("end_point3", "End Point", value = NULL, min = 0, step = 0.1))
                               ),
                               
                               # Multstart Options
                               h4("Multiple Starting Points"),
                               p("Fit model multiple times with different starting parameters to avoid local minima."),
                               numericInput("multstart_iter3", "Number of Iterations", value = 1, min = 1, max = 50, step = 1),
                               
                             ),
                             # 2TCM selection panel
                             conditionalPanel(
                               condition = "input.button3 == '2TCM'",
                               fluidRow(
                                 column(3, offset = 0, numericInput("K1.start3", "K1.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("K1.lower3", "K1.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("K1.upper3", "K1.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("k2.start3", "k2.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k2.lower3", "k2.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k2.upper3", "k2.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("k3.start3", "k3.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k3.lower3", "k3.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k3.upper3", "k3.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("k4.start3", "k4.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k4.lower3", "k4.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k4.upper3", "k4.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("vB.start3", "vB.start", value = 0.05, min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("vB.lower3", "vB.lower", value = 0.01, min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("vB.upper3", "vB.upper", value = 0.1, min = 0, step=.001)),
                               ),
                               selectInput("vB_source3", "vB Parameter Source:",
                                          choices = list(
                                            "Fit vB" = "fit",
                                            "Set vB (uses vB.start)" = "set", 
                                            "Inherit vB from Model 1 (Regional)" = "inherit_model1_regional",
                                            "Inherit vB from Model 1 (Mean Across Regions)" = "inherit_model1_mean",
                                            "Inherit vB from Model 1 (Median Across Regions)" = "inherit_model1_median",
                                            "Inherit vB from Model 2 (Regional)" = "inherit_model2_regional",
                                            "Inherit vB from Model 2 (Mean Across Regions)" = "inherit_model2_mean",
                                            "Inherit vB from Model 2 (Median Across Regions)" = "inherit_model2_median"
                                          ),
                                          selected = "fit"),
                               
                               # Time/Frame Selection
                               h4("TAC Subset Selection"),
                               p("Specify subset of TAC data for fitting (optional). Leave blank to use all frames."),
                               radioButtons("subset_type3", "Selection Method:",
                                           choices = list("Frame Numbers" = "frame", 
                                                         "Time Points (minutes)" = "time"),
                                           selected = "time", inline = TRUE),
                               fluidRow(
                                 column(6, numericInput("start_point3", "Start Point", value = NULL, min = 0, step = 0.1)),
                                 column(6, numericInput("end_point3", "End Point", value = NULL, min = 0, step = 0.1))
                               ),
                               
                               # Multstart Options
                               h4("Multiple Starting Points"),
                               p("Fit model multiple times with different starting parameters to avoid local minima."),
                               numericInput("multstart_iter3", "Number of Iterations", value = 1, min = 1, max = 50, step = 1),
                               
                             ),
                             # 2TCM_irr selection panel
                             conditionalPanel(
                               condition = "input.button3 == '2TCM_irr'",
                               fluidRow(
                                 column(3, offset = 0, numericInput("K1.start3", "K1.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("K1.lower3", "K1.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("K1.upper3", "K1.upper", value = 1,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("k2.start3", "k2.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k2.lower3", "k2.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k2.upper3", "k2.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("k3.start3", "k3.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k3.lower3", "k3.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k3.upper3", "k3.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("vB.start3", "vB.start", value = 0.05, min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("vB.lower3", "vB.lower", value = 0.01, min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("vB.upper3", "vB.upper", value = 0.1, min = 0, step=.001)),
                               ),
                               selectInput("vB_source3", "vB Parameter Source:",
                                          choices = list(
                                            "Fit vB" = "fit",
                                            "Set vB (uses vB.start)" = "set",
                                            "Inherit vB from Model 1 (Regional)" = "inherit_model1_regional",
                                            "Inherit vB from Model 1 (Mean Across Regions)" = "inherit_model1_mean",
                                            "Inherit vB from Model 1 (Median Across Regions)" = "inherit_model1_median",
                                            "Inherit vB from Model 2 (Regional)" = "inherit_model2_regional",
                                            "Inherit vB from Model 2 (Mean Across Regions)" = "inherit_model2_mean",
                                            "Inherit vB from Model 2 (Median Across Regions)" = "inherit_model2_median"
                                          ),
                                          selected = "fit"),

                               # Time/Frame Selection
                               h4("TAC Subset Selection"),
                               p("Specify subset of TAC data for fitting (optional). Leave blank to use all frames."),
                               radioButtons("subset_type3", "Selection Method:",
                                           choices = list("Frame Numbers" = "frame",
                                                         "Time Points (minutes)" = "time"),
                                           selected = "time", inline = TRUE),
                               fluidRow(
                                 column(6, numericInput("start_point3", "Start Point", value = NULL, min = 0, step = 0.1)),
                                 column(6, numericInput("end_point3", "End Point", value = NULL, min = 0, step = 0.1))
                               ),

                               # Multstart Options
                               h4("Multiple Starting Points"),
                               p("Fit model multiple times with different starting parameters to avoid local minima."),
                               numericInput("multstart_iter3", "Number of Iterations", value = 1, min = 1, max = 50, step = 1),

                             ),
                             # Logan selection panel
                             conditionalPanel(
                               condition = "input.button3 == 'Logan'",
                               h4("t* Definition"),
                               p("Define t* (time point for linear analysis start) using frame numbers or time."),
                               radioButtons("tstar_type3", "",
                                           choices = list("Number of Frames (from the end)" = "frame", 
                                                         "Time Point (minutes)" = "time"),
                                           selected = "frame", inline = TRUE),
                               numericInput("tstar3", "t* (0 for all frames)", value = 10, min = 0, step = 1),
                               
                               h4("Other Parameters"),
                               selectInput("vB_source3", "vB Parameter Source:",
                                          choices = list(
                                            "Set vB" = "set",
                                            "Inherit vB from Model 1 (Regional)" = "inherit_model1_regional",
                                            "Inherit vB from Model 1 (Mean Across Regions)" = "inherit_model1_mean",
                                            "Inherit vB from Model 1 (Median Across Regions)" = "inherit_model1_median",
                                            "Inherit vB from Model 2 (Regional)" = "inherit_model2_regional",
                                            "Inherit vB from Model 2 (Mean Across Regions)" = "inherit_model2_mean",
                                            "Inherit vB from Model 2 (Median Across Regions)" = "inherit_model2_median"
                                          ),
                                          selected = "set"),
                               conditionalPanel(
                                 condition = "input.vB_source3 == 'set'",
                                 numericInput("vB_value3", "vB Value", value = 0.05, min = 0, max = 1, step = 0.001)
                               ),
                               
                               # TAC Subset Selection
                               h4("TAC Subset Selection"),
                               p("Specify subset of TAC data for fitting (optional). Leave blank to use all frames."),
                               radioButtons("subset_type3", "Selection Method:",
                                           choices = list("Frame Numbers" = "frame", 
                                                         "Time Points (minutes)" = "time"),
                                           selected = "time", inline = TRUE),
                               fluidRow(
                                 column(6, numericInput("start_point3", "Start Point", value = NULL, min = 0, step = 0.1)),
                                 column(6, numericInput("end_point3", "End Point", value = NULL, min = 0, step = 0.1))
                               )
                             ),
                             # MA1 selection panel
                             conditionalPanel(
                               condition = "input.button3 == 'MA1'",
                               h4("t* Definition"),
                               p("Define t* (time point for linear analysis start) using frame numbers or time."),
                               radioButtons("tstar_type3", "",
                                           choices = list("Number of Frames (from the end)" = "frame", 
                                                         "Time Point (minutes)" = "time"),
                                           selected = "frame", inline = TRUE),
                               numericInput("tstar3", "t* (0 for all frames)", value = 10, min = 0, step = 1),
                               
                               h4("Other Parameters"),
                               selectInput("vB_source3", "vB Parameter Source:",
                                          choices = list(
                                            "Set vB" = "set",
                                            "Inherit vB from Model 1 (Regional)" = "inherit_model1_regional",
                                            "Inherit vB from Model 1 (Mean Across Regions)" = "inherit_model1_mean",
                                            "Inherit vB from Model 1 (Median Across Regions)" = "inherit_model1_median",
                                            "Inherit vB from Model 2 (Regional)" = "inherit_model2_regional",
                                            "Inherit vB from Model 2 (Mean Across Regions)" = "inherit_model2_mean",
                                            "Inherit vB from Model 2 (Median Across Regions)" = "inherit_model2_median"
                                          ),
                                          selected = "set"),
                               conditionalPanel(
                                 condition = "input.vB_source3 == 'set'",
                                 numericInput("vB_value3", "vB Value", value = 0.05, min = 0, max = 1, step = 0.001)
                               ),
                               
                               # TAC Subset Selection
                               h4("TAC Subset Selection"),
                               p("Specify subset of TAC data for fitting (optional). Leave blank to use all frames."),
                               radioButtons("subset_type3", "Selection Method:",
                                           choices = list("Frame Numbers" = "frame", 
                                                         "Time Points (minutes)" = "time"),
                                           selected = "time", inline = TRUE),
                               fluidRow(
                                 column(6, numericInput("start_point3", "Start Point", value = NULL, min = 0, step = 0.1)),
                                 column(6, numericInput("end_point3", "End Point", value = NULL, min = 0, step = 0.1))
                               )
                             ),

                            # Patlak selection panel
                            conditionalPanel(
                              condition = "input.button3 == 'Patlak'",
                              h4("t* Definition"),
                              p("Define t* (time point for linear analysis start) using frame numbers or time."),
                              radioButtons("tstar_type3", "",
                                          choices = list("Number of Frames (from the end)" = "frame",
                                                        "Time Point (minutes)" = "time"),
                                          selected = "frame", inline = TRUE),
                              numericInput("tstar3", "t* (0 for all frames)", value = 10, min = 0, step = 1),

                              h4("Other Parameters"),
                              selectInput("vB_source3", "vB Parameter Source:",
                                         choices = list(
                                           "Set vB" = "set",
                                           "Inherit vB from Model 1 (Regional)" = "inherit_model1_regional",
                                           "Inherit vB from Model 1 (Mean Across Regions)" = "inherit_model1_mean",
                                           "Inherit vB from Model 1 (Median Across Regions)" = "inherit_model1_median",
                                           "Inherit vB from Model 2 (Regional)" = "inherit_model2_regional",
                                           "Inherit vB from Model 2 (Mean Across Regions)" = "inherit_model2_mean",
                                           "Inherit vB from Model 2 (Median Across Regions)" = "inherit_model2_median"
                                         ),
                                         selected = "set"),
                              conditionalPanel(
                                condition = "input.vB_source3 == 'set'",
                                numericInput("vB_value3", "vB Value", value = 0.05, min = 0, max = 1, step = 0.001)
                              ),

                              # TAC Subset Selection
                              h4("TAC Subset Selection"),
                              p("Specify subset of TAC data for fitting (optional). Leave blank to use all frames."),
                              radioButtons("subset_type3", "Selection Method:",
                                          choices = list("Frame Numbers" = "frame",
                                                        "Time Points (minutes)" = "time"),
                                          selected = "time", inline = TRUE),
                              fluidRow(
                                column(6, numericInput("start_point3", "Start Point", value = NULL, min = 0, step = 0.1)),
                                column(6, numericInput("end_point3", "End Point", value = NULL, min = 0, step = 0.1))
                              )
                            ),

                             hr(),
                             conditionalPanel(
                               condition = "input.button3 != 'none'",
                               actionButton("run_model3", "▶ Fit Model 3", class = "btn-success btn-lg")
                             )
                    ),
                    # Tab panel for Config Preview ----
                    tabPanel("Preview Configuration",
                             br(),
                             h4("Configuration Settings"),
                             p("Review and save your analysis configuration. The JSON below shows all current settings."),
                             
                             # Analysis info
                             fluidRow(
                               column(6, 
                                      h5("Analysis Information"),
                                      p(strong("Analysis folder: "), textOutput("analysis_folder", inline = TRUE)),
                                      p(strong("Config file: "), "desc-petfitoptions_config.json")
                               ),
                               column(6,
                                      br(),
                                      actionButton("run_all", "▶ Run All", class = "btn-success btn-lg"),
                                      br(), br(),
                                      actionButton("save_config", "💾 Save Config", class = "btn-primary btn-lg")
                               )
                             ),
                             
                             hr(),
                             
                             # JSON preview
                             h5("Current Configuration (JSON)"),
                             verbatimTextOutput("json_preview"),
                             
                             br()
                    ),
                # Tab panel for Interactive ----
                    tabPanel("Interactive Sandbox",
                             br(),
                             h4("Interactive Data Exploration"),
                             p("Load and visualize individual TAC data for quality control and exploration.",
                               style = "font-size:14px; margin-bottom:20px;"),
                             
                             # Sidebar layout
                             fluidRow(
                               # Left sidebar - Controls
                               column(4,
                                 wellPanel(
                                   h5("Data Selection"),
                                   
                                   actionButton("scan_folder", "🔍 Scan Analysis Folder", class = "btn-info btn-sm", width = "100%"),
                                   p("This populates the menus below with available data files.", 
                                     style = "font-size: 11px; color: #666; margin-top: 5px; margin-bottom: 15px;"),
                                   
                                   selectInput("interactive_pet", "PET Measurement:",
                                             choices = c("Run 'Scan Analysis Folder' first" = "none"),
                                             selected = "none",
                                             width = "100%"),
                                   
                                   selectInput("interactive_region", "Region:",
                                             choices = c("Run 'Scan Analysis Folder' first" = "none"),
                                             selected = "none", 
                                             width = "100%"),
                                   
                                   selectInput("interactive_model", "Model:",
                                             choices = c("None" = "none",
                                                         "Model 1" = "model1",
                                                         "Model 2" = "model2", 
                                                         "Model 3" = "model3"),
                                             selected = "model1",
                                             width = "100%"),
                                   
                                   hr(),
                                   actionButton("load_data", "▶ Load Data", class = "btn-success btn-lg", width = "100%"),
                                   br(), br(),
                                   actionButton("fit_model", "▶ Fit Model", class = "btn-success btn-lg", width = "100%")
                                 )
                               ),
                               
                               # Right main area - Plot
                               column(8,
                                 conditionalPanel(
                                   condition = "input.load_data > 0",
                                   # h5("Time Activity Curve"),
                                   plotOutput("tac_plot", height = "500px")
                                 )
                               )
                             )
                    )
        )
  )
  
  # Define server logic for config file creation ----
  server <- function(input, output, session) {

    # Load existing config on startup and restore UI state
    observe({
      existing_config <- load_existing_config()
      
      if (!is.null(existing_config)) {
        # Show notification that config is being loaded
        showNotification(paste("Loading previous configuration from", basename(output_dir)), 
                        type = "message", duration = 5)
        
        # Restore subsetting parameters
        if (!is.null(existing_config$Subsetting)) {
          updateTextInput(session, "subset_sub", value = existing_config$Subsetting$sub %||% "")
          updateTextInput(session, "subset_ses", value = existing_config$Subsetting$ses %||% "")
          updateTextInput(session, "subset_task", value = existing_config$Subsetting$task %||% "")
          updateTextInput(session, "subset_trc", value = existing_config$Subsetting$trc %||% "")
          updateTextInput(session, "subset_rec", value = existing_config$Subsetting$rec %||% "")
          updateTextInput(session, "subset_run", value = existing_config$Subsetting$run %||% "")
          updateTextInput(session, "subset_regions", value = existing_config$Subsetting$Regions %||% "")
        }
        
        # Helper function to restore model parameters
        restore_model_params <- function(model_config, suffix = "") {
          if (is.null(model_config)) return()
          
          model_type <- model_config$type
          
          # Restore parameters based on model type
          if (!is.null(model_type) && model_type == "1TCM") {
            if (!is.null(model_config$K1)) {
              updateNumericInput(session, paste0("K1.start", suffix), value = model_config$K1$start %||% 0.1)
              updateNumericInput(session, paste0("K1.lower", suffix), value = model_config$K1$lower %||% 0.0001)
              updateNumericInput(session, paste0("K1.upper", suffix), value = model_config$K1$upper %||% 0.5)
            }
            if (!is.null(model_config$k2)) {
              updateNumericInput(session, paste0("k2.start", suffix), value = model_config$k2$start %||% 0.1)
              updateNumericInput(session, paste0("k2.lower", suffix), value = model_config$k2$lower %||% 0.0001)
              updateNumericInput(session, paste0("k2.upper", suffix), value = model_config$k2$upper %||% 0.5)
            }
            if (!is.null(model_config$vB)) {
              updateNumericInput(session, paste0("vB.start", suffix), value = model_config$vB$start %||% 0.05)
              updateNumericInput(session, paste0("vB.lower", suffix), value = model_config$vB$lower %||% 0.01)
              updateNumericInput(session, paste0("vB.upper", suffix), value = model_config$vB$upper %||% 0.1)
              
              # Handle vB parameter restoration based on model number (suffix)
              if (suffix == "") {
                # Model 1 uses old checkbox system
                updateCheckboxInput(session, paste0("vB.fit", suffix), value = model_config$vB$fit %||% TRUE)
              } else {
                # Models 2 and 3 use new inheritance system
                if (!is.null(model_config$vB_source)) {
                  updateSelectInput(session, paste0("vB_source", suffix), selected = model_config$vB_source %||% "fit")
                } else if (!is.null(model_config$vB$fit)) {
                  # Backward compatibility: convert old fit boolean to new vB_source
                  vB_source_value <- if (model_config$vB$fit) "fit" else "set"
                  updateSelectInput(session, paste0("vB_source", suffix), selected = vB_source_value)
                }
              }
            }
          } else if (!is.null(model_type) && model_type == "2TCM") {
            # Similar parameter restoration for 2TCM (K1, k2, k3, k4, vB)
            if (!is.null(model_config$K1)) {
              updateNumericInput(session, paste0("K1.start", suffix), value = model_config$K1$start %||% 0.1)
              updateNumericInput(session, paste0("K1.lower", suffix), value = model_config$K1$lower %||% 0.0001)
              updateNumericInput(session, paste0("K1.upper", suffix), value = model_config$K1$upper %||% 0.5)
            }
            if (!is.null(model_config$k2)) {
              updateNumericInput(session, paste0("k2.start", suffix), value = model_config$k2$start %||% 0.1)
              updateNumericInput(session, paste0("k2.lower", suffix), value = model_config$k2$lower %||% 0.0001)
              updateNumericInput(session, paste0("k2.upper", suffix), value = model_config$k2$upper %||% 0.5)
            }
            if (!is.null(model_config$k3)) {
              updateNumericInput(session, paste0("k3.start", suffix), value = model_config$k3$start %||% 0.1)
              updateNumericInput(session, paste0("k3.lower", suffix), value = model_config$k3$lower %||% 0.0001)
              updateNumericInput(session, paste0("k3.upper", suffix), value = model_config$k3$upper %||% 0.5)
            }
            if (!is.null(model_config$k4)) {
              updateNumericInput(session, paste0("k4.start", suffix), value = model_config$k4$start %||% 0.1)
              updateNumericInput(session, paste0("k4.lower", suffix), value = model_config$k4$lower %||% 0.0001)
              updateNumericInput(session, paste0("k4.upper", suffix), value = model_config$k4$upper %||% 0.5)
            }
            if (!is.null(model_config$vB)) {
              updateNumericInput(session, paste0("vB.start", suffix), value = model_config$vB$start %||% 0.05)
              updateNumericInput(session, paste0("vB.lower", suffix), value = model_config$vB$lower %||% 0.01)
              updateNumericInput(session, paste0("vB.upper", suffix), value = model_config$vB$upper %||% 0.1)
              
              # Handle vB parameter restoration based on model number (suffix)
              if (suffix == "") {
                # Model 1 uses old checkbox system
                updateCheckboxInput(session, paste0("vB.fit", suffix), value = model_config$vB$fit %||% TRUE)
              } else {
                # Models 2 and 3 use new inheritance system
                if (!is.null(model_config$vB_source)) {
                  updateSelectInput(session, paste0("vB_source", suffix), selected = model_config$vB_source %||% "fit")
                } else if (!is.null(model_config$vB$fit)) {
                  # Backward compatibility: convert old fit boolean to new vB_source
                  vB_source_value <- if (model_config$vB$fit) "fit" else "set"
                  updateSelectInput(session, paste0("vB_source", suffix), selected = vB_source_value)
                }
              }
            }
          } else if (!is.null(model_type) && model_type == "2TCM_irr") {
            # Parameter restoration for 2TCM_irr (K1, k2, k3, vB - no k4)
            if (!is.null(model_config$K1)) {
              updateNumericInput(session, paste0("K1.start", suffix), value = model_config$K1$start %||% 0.1)
              updateNumericInput(session, paste0("K1.lower", suffix), value = model_config$K1$lower %||% 0.0001)
              updateNumericInput(session, paste0("K1.upper", suffix), value = model_config$K1$upper %||% 1)
            }
            if (!is.null(model_config$k2)) {
              updateNumericInput(session, paste0("k2.start", suffix), value = model_config$k2$start %||% 0.1)
              updateNumericInput(session, paste0("k2.lower", suffix), value = model_config$k2$lower %||% 0.0001)
              updateNumericInput(session, paste0("k2.upper", suffix), value = model_config$k2$upper %||% 0.5)
            }
            if (!is.null(model_config$k3)) {
              updateNumericInput(session, paste0("k3.start", suffix), value = model_config$k3$start %||% 0.1)
              updateNumericInput(session, paste0("k3.lower", suffix), value = model_config$k3$lower %||% 0.0001)
              updateNumericInput(session, paste0("k3.upper", suffix), value = model_config$k3$upper %||% 0.5)
            }
            if (!is.null(model_config$vB)) {
              updateNumericInput(session, paste0("vB.start", suffix), value = model_config$vB$start %||% 0.05)
              updateNumericInput(session, paste0("vB.lower", suffix), value = model_config$vB$lower %||% 0.01)
              updateNumericInput(session, paste0("vB.upper", suffix), value = model_config$vB$upper %||% 0.1)

              # Handle vB parameter restoration based on model number (suffix)
              if (suffix == "") {
                # Model 1 uses old checkbox system
                updateCheckboxInput(session, paste0("vB.fit", suffix), value = model_config$vB$fit %||% TRUE)
              } else {
                # Models 2 and 3 use new inheritance system
                if (!is.null(model_config$vB_source)) {
                  updateSelectInput(session, paste0("vB_source", suffix), selected = model_config$vB_source %||% "fit")
                } else if (!is.null(model_config$vB$fit)) {
                  # Backward compatibility: convert old fit boolean to new vB_source
                  vB_source_value <- if (model_config$vB$fit) "fit" else "set"
                  updateSelectInput(session, paste0("vB_source", suffix), selected = vB_source_value)
                }
              }
            }
          } else if (!is.null(model_type) && (model_type == "Logan" || model_type == "MA1" || model_type == "Patlak")) {
            if (!is.null(model_config$tstar)) {
              updateNumericInput(session, paste0("tstar", suffix), value = model_config$tstar %||% 10)
            }
            if (!is.null(model_config$tstar_type)) {
              updateRadioButtons(session, paste0("tstar_type", suffix), selected = model_config$tstar_type %||% "frame")
            }
            if (!is.null(model_config$vB_source)) {
              updateSelectInput(session, paste0("vB_source", suffix), selected = model_config$vB_source %||% "set")
            }
            if (!is.null(model_config$vB_value)) {
              updateNumericInput(session, paste0("vB_value", suffix), value = model_config$vB_value %||% 0.05)
            }
            # TAC Subset Selection restoration
            if (!is.null(model_config$subset)) {
              updateRadioButtons(session, paste0("subset_type", suffix), selected = model_config$subset$type %||% "time")
              updateNumericInput(session, paste0("start_point", suffix), value = model_config$subset$start)
              updateNumericInput(session, paste0("end_point", suffix), value = model_config$subset$end)
            }
          } else if (!is.null(model_type) && model_type == "refLogan") {
            if (!is.null(model_config$tstar)) {
              updateNumericInput(session, paste0("tstar", suffix), value = model_config$tstar %||% 10)
            }
            if (!is.null(model_config$tstar_type)) {
              updateRadioButtons(session, paste0("tstar_type", suffix), selected = model_config$tstar_type %||% "frame")
            }
            if (!is.null(model_config$k2prime_source)) {
              updateSelectInput(session, paste0("k2prime_source", suffix), selected = model_config$k2prime_source %||% "set")
            }
            if (!is.null(model_config$k2prime_value)) {
              updateNumericInput(session, paste0("k2prime_value", suffix), value = model_config$k2prime_value %||% 0.1)
            }
            # TAC Subset Selection restoration
            if (!is.null(model_config$subset)) {
              updateRadioButtons(session, paste0("subset_type", suffix), selected = model_config$subset$type %||% "time")
              updateNumericInput(session, paste0("start_point", suffix), value = model_config$subset$start)
              updateNumericInput(session, paste0("end_point", suffix), value = model_config$subset$end)
            }
          } else if (!is.null(model_type) && model_type == "SRTM") {
            if (!is.null(model_config$R1)) {
              updateNumericInput(session, paste0("R1.start", suffix), value = model_config$R1$start %||% 1)
              updateNumericInput(session, paste0("R1.lower", suffix), value = model_config$R1$lower %||% 0.0001)
              updateNumericInput(session, paste0("R1.upper", suffix), value = model_config$R1$upper %||% 5)
            }
            if (!is.null(model_config$k2)) {
              updateNumericInput(session, paste0("k2.start", suffix), value = model_config$k2$start %||% 0.1)
              updateNumericInput(session, paste0("k2.lower", suffix), value = model_config$k2$lower %||% 0.0001)
              updateNumericInput(session, paste0("k2.upper", suffix), value = model_config$k2$upper %||% 0.5)
            }
            if (!is.null(model_config$k2a)) {
              updateNumericInput(session, paste0("k2a.start", suffix), value = model_config$k2a$start %||% 0.1)
              updateNumericInput(session, paste0("k2a.lower", suffix), value = model_config$k2a$lower %||% 0.0001)
              updateNumericInput(session, paste0("k2a.upper", suffix), value = model_config$k2a$upper %||% 0.5)
            }
          } else if (!is.null(model_type) && model_type == "MRTM1") {
            if (!is.null(model_config$tstar)) {
              updateNumericInput(session, paste0("tstar", suffix), value = model_config$tstar %||% 10)
            }
            if (!is.null(model_config$tstar_type)) {
              updateRadioButtons(session, paste0("tstar_type", suffix), selected = model_config$tstar_type %||% "frame")
            }
            # TAC Subset Selection restoration
            if (!is.null(model_config$subset)) {
              updateRadioButtons(session, paste0("subset_type", suffix), selected = model_config$subset$type %||% "time")
              updateNumericInput(session, paste0("start_point", suffix), value = model_config$subset$start)
              updateNumericInput(session, paste0("end_point", suffix), value = model_config$subset$end)
            }
          } else if (!is.null(model_type) && model_type == "MRTM2") {
            if (!is.null(model_config$tstar)) {
              updateNumericInput(session, paste0("tstar", suffix), value = model_config$tstar %||% 10)
            }
            if (!is.null(model_config$tstar_type)) {
              updateRadioButtons(session, paste0("tstar_type", suffix), selected = model_config$tstar_type %||% "frame")
            }
            if (!is.null(model_config$k2prime_source)) {
              updateSelectInput(session, paste0("k2prime_source", suffix), selected = model_config$k2prime_source %||% "set")
            }
            if (!is.null(model_config$k2prime_value)) {
              updateNumericInput(session, paste0("k2prime_value", suffix), value = model_config$k2prime_value %||% 0.1)
            }
            # TAC Subset Selection restoration
            if (!is.null(model_config$subset)) {
              updateRadioButtons(session, paste0("subset_type", suffix), selected = model_config$subset$type %||% "time")
              updateNumericInput(session, paste0("start_point", suffix), value = model_config$subset$start)
              updateNumericInput(session, paste0("end_point", suffix), value = model_config$subset$end)
            }
          }
          
          # Restore common parameters for all model types
          if (!is.null(model_config$subset)) {
            updateRadioButtons(session, paste0("subset_type", suffix), selected = model_config$subset$type %||% "time")
            updateNumericInput(session, paste0("start_point", suffix), value = model_config$subset$start)
            updateNumericInput(session, paste0("end_point", suffix), value = model_config$subset$end)
          }
          
          if (!is.null(model_config$multstart_iter)) {
            updateNumericInput(session, paste0("multstart_iter", suffix), value = model_config$multstart_iter %||% 1)
          }
        }
        
        # Restore Model 1 settings
        if (!is.null(existing_config$Models$Model1)) {
          updateSelectInput(session, "button", selected = existing_config$Models$Model1$type %||% "none")
          restore_model_params(existing_config$Models$Model1, "")
        }
        
        # Restore Model 2 settings
        if (!is.null(existing_config$Models$Model2)) {
          updateSelectInput(session, "button2", selected = existing_config$Models$Model2$type %||% "none")
          restore_model_params(existing_config$Models$Model2, "2")
        }
        
        # Restore Model 3 settings
        if (!is.null(existing_config$Models$Model3)) {
          updateSelectInput(session, "button3", selected = existing_config$Models$Model3$type %||% "none")
          restore_model_params(existing_config$Models$Model3, "3")
        }
        
        # Restore Weights settings
        if (!is.null(existing_config$Weights)) {
          updateSelectInput(session, "weights_region_type", 
                           selected = existing_config$Weights$region_type %||% "external")
          updateTextInput(session, "weights_region", 
                         value = existing_config$Weights$region %||% "")
          updateSelectInput(session, "weights_external_tacs", 
                           selected = existing_config$Weights$external_tacs %||% "")
          updateRadioButtons(session, "weights_radioisotope", 
                           selected = existing_config$Weights$radioisotope %||% "C11")
          if (!is.null(existing_config$Weights$halflife)) {
            updateNumericInput(session, "weights_halflife", 
                             value = existing_config$Weights$halflife)
          }
          updateSelectInput(session, "weights_method", 
                           selected = existing_config$Weights$method %||% "2")
          # Handle both new 'formula' field and legacy 'custom_formula' field
          custom_formula_value <- existing_config$Weights$formula %||% existing_config$Weights$custom_formula %||% ""
          if (custom_formula_value != "" && existing_config$Weights$method == "custom") {
            updateTextAreaInput(session, "weights_custom_formula", 
                              value = custom_formula_value)
          }
          updateNumericInput(session, "weights_minweight", 
                           value = existing_config$Weights$minweight %||% 0.25)
        }
        # Restore FitDelay settings
        if (!is.null(existing_config$FitDelay)) {
          updateSelectInput(session, "delay_model", 
                           selected = existing_config$FitDelay$model %||% "1tcm_median")
          updateNumericInput(session, "delay_time_window", 
                           value = existing_config$FitDelay$time_window %||% 5)
          updateTextInput(session, "delay_regions", 
                         value = existing_config$FitDelay$regions %||% "")
          updateTextInput(session, "delay_multiple_regions", 
                         value = existing_config$FitDelay$multiple_regions %||% "")
          updateNumericInput(session, "delay_vB", 
                           value = existing_config$FitDelay$vB_value %||% 0.05)
          updateCheckboxInput(session, "delay_fit_vB", 
                            value = existing_config$FitDelay$fit_vB %||% FALSE)
          updateCheckboxInput(session, "delay_use_weights", 
                            value = existing_config$FitDelay$use_weights %||% FALSE)
          updateNumericInput(session, "delay_inpshift_lower", 
                           value = existing_config$FitDelay$inpshift_lower %||% -0.5)
          updateNumericInput(session, "delay_inpshift_upper", 
                           value = existing_config$FitDelay$inpshift_upper %||% 0.5)
        }
      }
    })
    
    # Blood data status display ----
    output$delay_blood_status_display <- renderUI({
      # Helper function to check for blood data files in a directory
      check_blood_files <- function(dir_path) {
        if (is.null(dir_path) || !dir.exists(dir_path)) {
          return(list(found = FALSE, files = character(0)))
        }
        
        blood_files <- list.files(dir_path, pattern = "_(blood|inputfunction)\\.tsv$", recursive = TRUE)
        return(list(found = length(blood_files) > 0, files = blood_files))
      }
      
      if (!is.null(blood_dir)) {
        # User provided blood_dir - check for blood data files
        blood_status <- check_blood_files(blood_dir)
        
        if (blood_status$found) {
          div(
            p(strong("✓ Blood data found"), 
              style = "color: #1b7837; font-size: 16px; margin-bottom: 5px;")
          )
        } else {
          div(
            p(strong("✗ No blood data found in blood_dir"), 
              style = "color: #d73027; font-size: 16px; margin-bottom: 5px;"),
            p("No _blood.tsv or _inputfunction.tsv files detected in the specified blood directory", 
              style = "color: #d73027; font-size: 14px;")
          )
        }
      } else if (!is.null(bids_dir)) {
        # Check for blood files in analysis folder first, then BIDS directory
        blood_status_analysis <- check_blood_files(output_dir)
        blood_status_bids <- check_blood_files(bids_dir)
        
        if (blood_status_analysis$found) {
          # Prioritize analysis folder data
          div(
            p(strong("✓ Blood data found in petfit analysis folder"), 
              style = "color: #1b7837; font-size: 16px; margin-bottom: 10px;")
          )
        } else if (blood_status_bids$found) {
          # Fall back to raw BIDS data
          div(
            p(strong("✓ Blood data found in raw BIDS data directory"), 
              style = "color: #1b7837; font-size: 16px; margin-bottom: 10px;"),
            div(
              style = "background-color: #e8f4f8; border-left: 4px solid #3182bd; padding: 10px; margin-top: 10px;",
              p(strong("💡 Recommendation:"), "Consider using bloodstream for blood processing.", 
                style = "color: #3182bd; font-size: 13px; margin: 0;")
            )
          )
        } else {
          div(
            p(strong("✗ No blood data found"), 
              style = "color: #d73027; font-size: 16px; margin-bottom: 10px;"),
            p("No _blood.tsv or _inputfunction.tsv files detected in BIDS directory or analysis folder", 
              style = "color: #d73027; font-size: 14px; margin-bottom: 10px;"),
            p("If your analysis does not involve blood data, then delay estimation is unnecessary.", 
              style = "color: #666; font-size: 14px;")
          )
        }
      } else {
        # Neither blood_dir nor bids_dir provided
        div(
          p(strong("⚠️ No blood data available"), 
            style = "color: #d73027; font-size: 16px; margin-bottom: 10px;"),
          p("Delay estimation requires blood data. Please provide a blood_dir parameter or bids_dir parameter when starting the app.", 
            style = "color: #d73027; font-size: 14px;")
        )
      }
    })
    
    # Reactive function to populate external segmentation options from combined regions file ----
    observe({
      tryCatch({
        # Read desc values from combined regions file (in petfit folder)
        combined_regions_file <- file.path(petfit_dir, "desc-combinedregions_tacs.tsv")
        
        cat("Looking for combined regions file at:", combined_regions_file, "\n")
        
        if (file.exists(combined_regions_file)) {
          cat("Combined regions file found, reading segmentation values...\n")
          combined_regions <- readr::read_tsv(combined_regions_file, show_col_types = FALSE)

          if (nrow(combined_regions) > 0 && "segmentation" %in% colnames(combined_regions)) {
            # Get unique segmentation values for segmentation options
            unique_segmentations <- sort(unique(combined_regions$segmentation))
            unique_segmentations <- unique_segmentations[!is.na(unique_segmentations)]

            cat("Found", length(unique_segmentations), "unique segmentation values:", paste(unique_segmentations, collapse = ", "), "\n")

            if (length(unique_segmentations) > 0) {
              # Create choices for segmentation selection
              choices <- setNames(unique_segmentations, unique_segmentations)

              # Prioritize seg- segmentations over label- for default selection
              default_selection <- if (any(stringr::str_detect(unique_segmentations, "seg-"))) {
                unique_segmentations[stringr::str_detect(unique_segmentations, "seg-")][1]
              } else {
                unique_segmentations[1]
              }

              updateSelectInput(session, "weights_external_tacs",
                               choices = choices,
                               selected = default_selection)

              cat("Successfully updated external segmentation dropdown\n")
            } else {
              updateSelectInput(session, "weights_external_tacs",
                               choices = c("No segmentations found" = ""),
                               selected = "")
            }
          } else {
            updateSelectInput(session, "weights_external_tacs",
                             choices = c("No segmentation column found" = ""),
                             selected = "")
          }
        } else {
          updateSelectInput(session, "weights_external_tacs",
                           choices = c("Combined regions file not found" = ""),
                           selected = "")
        }
      }, error = function(e) {
        # If there's an error, provide default choice
        updateSelectInput(session, "weights_external_tacs",
                         choices = c("Error loading segmentations" = ""),
                         selected = "")
      })
    })
    
    # Reactive expression to generate the config file ----
    config_json <- reactive({
      
      # Data Subset
      Subsetting <- list(
        sub = input$subset_sub,
        ses = input$subset_ses,
        task = input$subset_task,
        trc = input$subset_trc,
        rec = input$subset_rec,
        run = input$subset_run,
        Regions = input$subset_regions
      )
      
      # Weights Definition  
      # Define method formulas mapping
      method_formulas <- c(
        "1" = "frame_dur / tac_uncor",
        "2" = "sqrt(frame_dur * tac_uncor)",
        "3" = "sqrt(frame_dur) / tac", 
        "4" = "sqrt(frame_dur)",
        "5" = "frame_dur * exp(-ln(2)/halflife)",
        "6" = "frame_dur / tac",
        "7" = "frame_dur",
        "8" = "frame_dur^2 / tac_uncor",
        "9" = "(frame_dur^2 / (frame_dur * tac)) * corrections^2"
      )
      
      # Determine formula to store
      selected_method <- input$weights_method %||% "2"
      if (selected_method == "custom") {
        weights_formula <- input$weights_custom_formula %||% ""
      } else {
        weights_formula <- method_formulas[selected_method] %||% ""
      }
      
      Weights <- list(
        region_type = input$weights_region_type %||% "external",
        region = if(input$weights_region_type == "single") input$weights_region %||% "" else "",
        external_tacs = if(input$weights_region_type == "external") input$weights_external_tacs %||% "" else "",
        radioisotope = input$weights_radioisotope %||% "C11",
        halflife = if(input$weights_radioisotope == "Other") as.character(input$weights_halflife %||% 20.4) else "",
        method = selected_method,
        formula = weights_formula,
        minweight = input$weights_minweight %||% 0.25
      )
      
      # Fit Delay
      FitDelay <- list(
        model = input$delay_model %||% "1tcm_median",
        time_window = input$delay_time_window %||% 5,
        regions = input$delay_regions %||% "",
        multiple_regions = input$delay_multiple_regions %||% "",
        vB_value = input$delay_vB %||% 0.05,
        fit_vB = input$delay_fit_vB %||% FALSE,
        use_weights = input$delay_use_weights %||% FALSE,
        inpshift_lower = input$delay_inpshift_lower %||% -0.5,
        inpshift_upper = input$delay_inpshift_upper %||% 0.5
      )
      
      # Models (capture actual model inputs and parameters)
      
      # Helper function to capture model parameters
      capture_model_params <- function(model_type, suffix = "") {
        model_params <- list(type = model_type)
        
        if (model_type == "none" || is.null(model_type)) {
          return(model_params)
        }
        
        # Capture parameters based on model type
        if (model_type == "1TCM") {
          model_params$K1 = list(
            start = input[[paste0("K1.start", suffix)]] %||% 0.1,
            lower = input[[paste0("K1.lower", suffix)]] %||% 0.0001,
            upper = input[[paste0("K1.upper", suffix)]] %||% 0.5
          )
          model_params$k2 = list(
            start = input[[paste0("k2.start", suffix)]] %||% 0.1,
            lower = input[[paste0("k2.lower", suffix)]] %||% 0.0001,
            upper = input[[paste0("k2.upper", suffix)]] %||% 0.5
          )
          
          # Handle vB parameter based on model number (suffix)
          if (suffix == "") {
            # Model 1 uses old checkbox system
            model_params$vB = list(
              start = input[[paste0("vB.start", suffix)]] %||% 0.05,
              lower = input[[paste0("vB.lower", suffix)]] %||% 0.01,
              upper = input[[paste0("vB.upper", suffix)]] %||% 0.1,
              fit = input[[paste0("vB.fit", suffix)]] %||% TRUE
            )
          } else {
            # Models 2 and 3 use new inheritance system
            model_params$vB = list(
              start = input[[paste0("vB.start", suffix)]] %||% 0.05,
              lower = input[[paste0("vB.lower", suffix)]] %||% 0.01,
              upper = input[[paste0("vB.upper", suffix)]] %||% 0.1
            )
            model_params$vB_source = input[[paste0("vB_source", suffix)]] %||% "fit"
          }
          
        } else if (model_type == "2TCM") {
          model_params$K1 = list(
            start = input[[paste0("K1.start", suffix)]] %||% 0.1,
            lower = input[[paste0("K1.lower", suffix)]] %||% 0.0001,
            upper = input[[paste0("K1.upper", suffix)]] %||% 0.5
          )
          model_params$k2 = list(
            start = input[[paste0("k2.start", suffix)]] %||% 0.1,
            lower = input[[paste0("k2.lower", suffix)]] %||% 0.0001,
            upper = input[[paste0("k2.upper", suffix)]] %||% 0.5
          )
          model_params$k3 = list(
            start = input[[paste0("k3.start", suffix)]] %||% 0.1,
            lower = input[[paste0("k3.lower", suffix)]] %||% 0.0001,
            upper = input[[paste0("k3.upper", suffix)]] %||% 0.5
          )
          model_params$k4 = list(
            start = input[[paste0("k4.start", suffix)]] %||% 0.1,
            lower = input[[paste0("k4.lower", suffix)]] %||% 0.0001,
            upper = input[[paste0("k4.upper", suffix)]] %||% 0.5
          )
          
          # Handle vB parameter based on model number (suffix)
          if (suffix == "") {
            # Model 1 uses old checkbox system
            model_params$vB = list(
              start = input[[paste0("vB.start", suffix)]] %||% 0.05,
              lower = input[[paste0("vB.lower", suffix)]] %||% 0.01,
              upper = input[[paste0("vB.upper", suffix)]] %||% 0.1,
              fit = input[[paste0("vB.fit", suffix)]] %||% TRUE
            )
          } else {
            # Models 2 and 3 use new inheritance system
            model_params$vB = list(
              start = input[[paste0("vB.start", suffix)]] %||% 0.05,
              lower = input[[paste0("vB.lower", suffix)]] %||% 0.01,
              upper = input[[paste0("vB.upper", suffix)]] %||% 0.1
            )
            model_params$vB_source = input[[paste0("vB_source", suffix)]] %||% "fit"
          }
        } else if (model_type == "2TCM_irr") {
          model_params$K1 = list(
            start = input[[paste0("K1.start", suffix)]] %||% 0.1,
            lower = input[[paste0("K1.lower", suffix)]] %||% 0.0001,
            upper = input[[paste0("K1.upper", suffix)]] %||% 1
          )
          model_params$k2 = list(
            start = input[[paste0("k2.start", suffix)]] %||% 0.1,
            lower = input[[paste0("k2.lower", suffix)]] %||% 0.0001,
            upper = input[[paste0("k2.upper", suffix)]] %||% 0.5
          )
          model_params$k3 = list(
            start = input[[paste0("k3.start", suffix)]] %||% 0.1,
            lower = input[[paste0("k3.lower", suffix)]] %||% 0.0001,
            upper = input[[paste0("k3.upper", suffix)]] %||% 0.5
          )

          # Handle vB parameter based on model number (suffix)
          if (suffix == "") {
            # Model 1 uses old checkbox system
            model_params$vB = list(
              start = input[[paste0("vB.start", suffix)]] %||% 0.05,
              lower = input[[paste0("vB.lower", suffix)]] %||% 0.01,
              upper = input[[paste0("vB.upper", suffix)]] %||% 0.1,
              fit = input[[paste0("vB.fit", suffix)]] %||% TRUE
            )
          } else {
            # Models 2 and 3 use new inheritance system
            model_params$vB = list(
              start = input[[paste0("vB.start", suffix)]] %||% 0.05,
              lower = input[[paste0("vB.lower", suffix)]] %||% 0.01,
              upper = input[[paste0("vB.upper", suffix)]] %||% 0.1
            )
            model_params$vB_source = input[[paste0("vB_source", suffix)]] %||% "fit"
          }
        } else if (model_type == "Logan" || model_type == "MA1" || model_type == "Patlak") {
          model_params$tstar = input[[paste0("tstar", suffix)]] %||% 10
          model_params$tstar_type = input[[paste0("tstar_type", suffix)]] %||% "frame"
          model_params$vB_source = input[[paste0("vB_source", suffix)]] %||% "set"
          if (input[[paste0("vB_source", suffix)]] == "set" || is.null(input[[paste0("vB_source", suffix)]])) {
            model_params$vB_value = input[[paste0("vB_value", suffix)]] %||% 0.05
          }
          
          # TAC Subset Selection
          subset_type <- input[[paste0("subset_type", suffix)]] %||% "time"
          start_point <- input[[paste0("start_point", suffix)]]
          end_point <- input[[paste0("end_point", suffix)]]
          
          if (!is.null(start_point) || !is.null(end_point)) {
            model_params$subset = list(
              type = subset_type,
              start = start_point,
              end = end_point
            )
          }
        } else if (model_type == "refLogan") {
          model_params$tstar = input[[paste0("tstar", suffix)]] %||% 10
          model_params$tstar_type = input[[paste0("tstar_type", suffix)]] %||% "frame"
          model_params$k2prime_source = input[[paste0("k2prime_source", suffix)]] %||% "set"
          if (input[[paste0("k2prime_source", suffix)]] == "set" || is.null(input[[paste0("k2prime_source", suffix)]])) {
            model_params$k2prime_value = input[[paste0("k2prime_value", suffix)]] %||% 0.1
          }
          
          # TAC Subset Selection
          subset_type <- input[[paste0("subset_type", suffix)]] %||% "time"
          start_point <- input[[paste0("start_point", suffix)]]
          end_point <- input[[paste0("end_point", suffix)]]
          
          if (!is.null(start_point) || !is.null(end_point)) {
            model_params$subset = list(
              type = subset_type,
              start = start_point,
              end = end_point
            )
          }
        } else if (model_type == "SRTM") {
          model_params$R1 = list(
            start = input[[paste0("R1.start", suffix)]] %||% 1,
            lower = input[[paste0("R1.lower", suffix)]] %||% 0.0001,
            upper = input[[paste0("R1.upper", suffix)]] %||% 5
          )
          model_params$k2 = list(
            start = input[[paste0("k2.start", suffix)]] %||% 0.1,
            lower = input[[paste0("k2.lower", suffix)]] %||% 0.0001,
            upper = input[[paste0("k2.upper", suffix)]] %||% 0.5
          )
          model_params$k2a = list(
            start = input[[paste0("k2a.start", suffix)]] %||% 0.1,
            lower = input[[paste0("k2a.lower", suffix)]] %||% 0.0001,
            upper = input[[paste0("k2a.upper", suffix)]] %||% 0.5
          )
        } else if (model_type == "MRTM1") {
          model_params$tstar = input[[paste0("tstar", suffix)]] %||% 10
          model_params$tstar_type = input[[paste0("tstar_type", suffix)]] %||% "frame"
          
          # TAC Subset Selection
          subset_type <- input[[paste0("subset_type", suffix)]] %||% "time"
          start_point <- input[[paste0("start_point", suffix)]]
          end_point <- input[[paste0("end_point", suffix)]]
          
          if (!is.null(start_point) || !is.null(end_point)) {
            model_params$subset = list(
              type = subset_type,
              start = start_point,
              end = end_point
            )
          }
        } else if (model_type == "MRTM2") {
          model_params$tstar = input[[paste0("tstar", suffix)]] %||% 10
          model_params$tstar_type = input[[paste0("tstar_type", suffix)]] %||% "frame"
          model_params$k2prime_source = input[[paste0("k2prime_source", suffix)]] %||% "set"
          if (input[[paste0("k2prime_source", suffix)]] == "set" || is.null(input[[paste0("k2prime_source", suffix)]])) {
            model_params$k2prime_value = input[[paste0("k2prime_value", suffix)]] %||% 0.1
          }
          
          # TAC Subset Selection
          subset_type <- input[[paste0("subset_type", suffix)]] %||% "time"
          start_point <- input[[paste0("start_point", suffix)]]
          end_point <- input[[paste0("end_point", suffix)]]
          
          if (!is.null(start_point) || !is.null(end_point)) {
            model_params$subset = list(
              type = subset_type,
              start = start_point,
              end = end_point
            )
          }
        }
        
        # Add common parameters for all models
        if (model_type != "none" && !is.null(model_type)) {
          # TAC subset selection
          subset_type <- input[[paste0("subset_type", suffix)]] %||% "time"
          start_point <- input[[paste0("start_point", suffix)]]
          end_point <- input[[paste0("end_point", suffix)]]
          
          if (!is.null(start_point) || !is.null(end_point)) {
            model_params$subset = list(
              type = subset_type,
              start = start_point,
              end = end_point
            )
          }
          
          # Multstart iterations
          model_params$multstart_iter = input[[paste0("multstart_iter", suffix)]] %||% 1
        }
        
        return(model_params)
      }
      
      Models <- list(
        Model1 = capture_model_params(input$button %||% "none", ""),
        Model2 = capture_model_params(input$button2 %||% "none", "2"),
        Model3 = capture_model_params(input$button3 %||% "none", "3")
      )
      
      config_list <- list(
        modelling_configuration_type = "plasma input",
        analysis_folder = subfolder,
        config_created = format(Sys.time(), "%Y-%m-%d %H:%M"),
        blood_dir = blood_dir,
        Subsetting = Subsetting,
        Weights = Weights,
        FitDelay = FitDelay,
        Models = Models
      )
      
      jsonlite::toJSON(config_list, pretty = TRUE, auto_unbox = TRUE)
    })
    
    # Save config function
    save_config <- function() {
      config_file_path <- file.path(output_dir, "desc-petfitoptions_config.json")
      
      tryCatch({
        writeLines(config_json(), config_file_path)
        showNotification(paste("Configuration saved to", basename(config_file_path)), 
                        type = "message", duration = 3)
        cat("Config saved to:", config_file_path, "\n")
      }, error = function(e) {
        showNotification(paste("Error saving config:", e$message), 
                        type = "error", duration = 5)
        cat("Error saving config:", e$message, "\n")
      })
    }
    
    # Load existing config function
    load_existing_config <- function() {
      config_file_path <- file.path(output_dir, "desc-petfitoptions_config.json")
      
      if (!file.exists(config_file_path)) {
        return(NULL)
      }
      
      tryCatch({
        config_json <- readLines(config_file_path, warn = FALSE)
        config_data <- jsonlite::fromJSON(paste(config_json, collapse = ""))

        # Validate configuration type
        config_type <- config_data$modelling_configuration_type
        expected_type <- "plasma input"

        if (!is.null(config_type) && config_type != expected_type) {
          showNotification(
            paste0("Configuration file is for ", config_type, " modelling. Starting with default settings."),
            type = "warning",
            duration = 5
          )
          cat("Config type mismatch: found", config_type, "expected", expected_type, "\n")
          return(NULL)
        }

        cat("Loaded existing config from:", config_file_path, "\n")
        return(config_data)
      }, error = function(e) {
        showNotification("Unable to read existing config file. Using default settings.",
                        type = "error", duration = 5)
        cat("Error loading config:", e$message, "\n")
        return(NULL)
      })
    }
    
    # Save config button handler
    observeEvent(input$save_config, {
      save_config()
    })
    
    # Run button handlers - each saves config then executes step
    observeEvent(input$run_subset, {
      save_config()
      
      # Check if combined TACs file exists in petfit folder
      petfit_folder <- petfit_dir  # derivatives/petfit - contains combined TACs file
      analysis_folder <- output_dir  # derivatives/petfit/{subfolder} - for individual files
      combined_tacs_file <- file.path(petfit_folder, "desc-combinedregions_tacs.tsv")
      
      if (!file.exists(combined_tacs_file)) {
        showNotification("Combined TACs file not found. Please run the region definition app first.", 
                        type = "error", duration = 5)
        return()
      }
      
      tryCatch({
        # Read combined TACs data from petfit folder
        combined_data <- readr::read_tsv(combined_tacs_file, show_col_types = FALSE)
        
        if (nrow(combined_data) == 0) {
          showNotification("Combined TACs file is empty", type = "error", duration = 5)
          return()
        }
        
        # Parse subsetting parameters
        subset_params <- list(
          sub = parse_semicolon_values(input$subset_sub),
          ses = parse_semicolon_values(input$subset_ses),
          task = parse_semicolon_values(input$subset_task),
          trc = parse_semicolon_values(input$subset_trc),
          rec = parse_semicolon_values(input$subset_rec),
          run = parse_semicolon_values(input$subset_run),
          regions = parse_semicolon_values(input$subset_regions)
        )
        
        # Apply subsetting
        filtered_data <- subset_combined_tacs(combined_data, subset_params)
        
        if (nrow(filtered_data) == 0) {
          showNotification("No data matches the subsetting criteria", type = "warning", duration = 5)
          return()
        }
        
        # Create individual TACs files in analysis folder
        result <- create_individual_tacs_files(filtered_data, analysis_folder)
        
        # Show generating report notification
        showNotification("Generating report...", type = "message", duration = NULL, id = "generating_report")
        
        cat("=== Data Subsetting Complete ===\n")
        cat("Files created:", result$files_created, "\n")
        cat("Analysis folder:", analysis_folder, "\n")
        cat("Total measurements:", nrow(filtered_data), "\n")  
        cat("Unique subjects:", length(unique(filtered_data$sub)), "\n")
        cat("Unique regions:", length(unique(filtered_data$region)), "\n")
        
        # Generate data definition report
        tryCatch({
          report_file <- generate_step_report(
            step_name = "data_definition",
            analysis_folder = analysis_folder,
            bids_dir = bids_dir,
            blood_dir = blood_dir
          )
          
          # Remove generating notification and show completion
          removeNotification(id = "generating_report")
          
          if (!is.null(report_file)) {
            showNotification("Data definition report generated successfully", type = "message", duration = 5)
          } else {
            showNotification("Report generation completed", type = "message", duration = 5)
          }
          
        }, error = function(e) {
          # Remove generating notification and show error
          removeNotification(id = "generating_report")
          showNotification("Error generating report", type = "error", duration = 5)
          cat("Warning: Could not generate data definition report:", e$message, "\n")
        })
        
      }, error = function(e) {
        error_msg <- paste("Error during data subsetting:", e$message)
        showNotification(error_msg, type = "error", duration = 10)
        cat("Error:", e$message, "\n")
      })
    })
    
    observeEvent(input$run_weights, {
      # Check for combined regions TACs files first
      tacs_files <- list.files(output_dir, 
                              pattern = "*_desc-combinedregions_tacs.tsv", 
                              recursive = TRUE)
      
      if (length(tacs_files) == 0) {
        showNotification("No combined regions TACs files found. Please run Data Definition first to create individual TACs files.", 
                        type = "error", duration = 8)
        return()
      }
      
      save_config()
      # TODO: Add actual weights calculation logic
      
      # Generate weights report
      showNotification("Generating weights report...", type = "message", duration = NULL, id = "generating_weights_report")
      
      tryCatch({
        report_file <- generate_step_report(
          step_name = "weights",
          analysis_folder = output_dir,
          bids_dir = bids_dir,
          blood_dir = blood_dir
        )
        
        removeNotification(id = "generating_weights_report")
        
        if (!is.null(report_file)) {
          showNotification("Weights report generated", type = "message", duration = 3)
        } else {
          showNotification("Weights report generation failed - check console for details", type = "error", duration = 5)
        }
        
      }, error = function(e) {
        removeNotification(id = "generating_weights_report")
        error_msg <- paste("Could not generate weights report:", e$message)
        showNotification(error_msg, type = "error", duration = 8)
        cat("Error generating weights report:", e$message, "\n")
      })
    })
    
    observeEvent(input$run_delay, {
      # Check if blood data is available using same logic as status display
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
        # Check analysis folder first, then BIDS directory
        has_blood_data <- check_blood_files(output_dir) || check_blood_files(bids_dir)
      }
      
      # Check if delay method is "none" - no report needed
      if (input$delay_model == "none") {
        save_config()
        showNotification("No delay report necessary when delay fitting is disabled", type = "message", duration = 4)
        return()
      }
      
      if (!has_blood_data) {
        # Don't show notification - the status display already indicates no blood data
        return()
      }
      
      # Save configuration
      save_config()
      showNotification("Delay configuration saved", type = "message", duration = 3)
      
      # Show generating report notification
      showNotification("Estimating delays...", type = "message", duration = NULL, id = "generating_delay_report")
      
      # Generate delay report
      tryCatch({
        report_file <- generate_step_report(
          step_name = "delay",
          analysis_folder = output_dir,
          bids_dir = bids_dir,
          blood_dir = blood_dir
        )
        
        # Remove generating notification and show completion
        removeNotification(id = "generating_delay_report")
        
        if (!is.null(report_file)) {
          showNotification("Delay report generated successfully", type = "message", duration = 5)
        } else {
          showNotification("Report generation completed", type = "message", duration = 5)
        }
        
      }, error = function(e) {
        # Remove generating notification and show error
        removeNotification(id = "generating_delay_report")
        showNotification("Error generating report", type = "error", duration = 5)
        cat("Warning: Could not generate delay report:", e$message, "\n")
      })
    })
    
    observeEvent(input$run_model1, {
      # Save configuration
      save_config()
      
      # Show fitting notification
      model_type <- input$button %||% "1TCM"
      showNotification(paste("Fitting Model 1 (", model_type, ")..."), type = "message", duration = NULL, id = "fitting_model1")
      
      # Generate model 1 report
      tryCatch({
        report_file <- generate_model_report(
          model_type = model_type,
          model_number = "Model 1",
          analysis_folder = output_dir,
          bids_dir = bids_dir,
          blood_dir = blood_dir
        )

        # Remove fitting notification and show completion
        removeNotification(id = "fitting_model1")

        # Check if report was actually generated
        if (!is.null(report_file)) {
          showNotification("Model 1 fitting report generated successfully", type = "message", duration = 5)
        } else {
          showNotification("Error fitting Model 1: report generation failed", type = "error", duration = 5)
        }

      }, error = function(e) {
        # Remove fitting notification and show error
        removeNotification(id = "fitting_model1")
        showNotification("Error fitting Model 1", type = "error", duration = 5)
        cat("Warning: Could not generate Model 1 report:", e$message, "\n")
      })
    })
    
    observeEvent(input$run_model2, {
      # Save configuration
      save_config()
      
      # Show fitting notification
      model_type <- input$button2 %||% "1TCM"
      showNotification(paste("Fitting Model 2 (", model_type, ")..."), type = "message", duration = NULL, id = "fitting_model2")
      
      # Generate model 2 report
      tryCatch({
        report_file <- generate_model_report(
          model_type = model_type,
          model_number = "Model 2",
          analysis_folder = output_dir,
          bids_dir = bids_dir,
          blood_dir = blood_dir
        )

        # Remove fitting notification and show completion
        removeNotification(id = "fitting_model2")

        # Check if report was actually generated
        if (!is.null(report_file)) {
          showNotification("Model 2 fitting report generated successfully", type = "message", duration = 5)
        } else {
          showNotification("Error fitting Model 2: report generation failed", type = "error", duration = 5)
        }

      }, error = function(e) {
        # Remove fitting notification and show error
        removeNotification(id = "fitting_model2")
        showNotification("Error fitting Model 2", type = "error", duration = 5)
        cat("Warning: Could not generate Model 2 report:", e$message, "\n")
      })
    })
    
    observeEvent(input$run_model3, {
      # Save configuration
      save_config()
      
      # Show fitting notification
      model_type <- input$button3 %||% "1TCM"
      showNotification(paste("Fitting Model 3 (", model_type, ")..."), type = "message", duration = NULL, id = "fitting_model3")
      
      # Generate model 3 report
      tryCatch({
        report_file <- generate_model_report(
          model_type = model_type,
          model_number = "Model 3",
          analysis_folder = output_dir,
          bids_dir = bids_dir,
          blood_dir = blood_dir
        )

        # Remove fitting notification and show completion
        removeNotification(id = "fitting_model3")

        # Check if report was actually generated
        if (!is.null(report_file)) {
          showNotification("Model 3 fitting report generated successfully", type = "message", duration = 5)
        } else {
          showNotification("Error fitting Model 3: report generation failed", type = "error", duration = 5)
        }

      }, error = function(e) {
        # Remove fitting notification and show error
        removeNotification(id = "fitting_model3")
        showNotification("Error fitting Model 3", type = "error", duration = 5)
        cat("Warning: Could not generate Model 3 report:", e$message, "\n")
      })
    })
    
    observeEvent(input$run_interactive, {
      save_config()
      showNotification("Interactive mode launched", type = "message", duration = 3)
      # TODO: Add actual interactive mode logic
    })
    
    # Run All button handler
    observeEvent(input$run_all, {
      save_config()
      
      # Show initial notification
      showNotification("Starting automatic pipeline execution...", type = "message", duration = 3, id = "run_all_start")
      
      # Run the automatic pipeline
      tryCatch({
        result <- petfit_modelling_auto(
          analysis_folder = output_dir,
          bids_dir = bids_dir,
          derivatives_dir = derivatives_dir,
          blood_dir = blood_dir,
          step = NULL  # NULL means full pipeline
        )
        
        if (result$success) {
          # Show success message with reports generated
          success_msg <- "All pipeline steps completed successfully!"
          if (length(result$reports_generated) > 0) {
            success_msg <- paste0(success_msg, " Reports generated: ", 
                                 paste(result$reports_generated, collapse = ", "))
          }
          showNotification(success_msg, type = "message", duration = 10)
          
          # Log all messages to console
          for (msg in result$messages) {
            cat("[Run All]", msg, "\n")
          }
        } else {
          # Show error message
          error_msg <- paste("Pipeline execution failed:", 
                           paste(result$messages, collapse = "; "))
          showNotification(error_msg, type = "error", duration = 10)
          
          # Log error messages to console
          cat("[Run All] Error:\n")
          for (msg in result$messages) {
            cat("  ", msg, "\n")
          }
        }
        
      }, error = function(e) {
        error_msg <- paste("Error executing pipeline:", e$message)
        showNotification(error_msg, type = "error", duration = 10)
        cat("[Run All] Exception:", e$message, "\n")
      })
    })
    
    # Output for analysis folder display
    output$analysis_folder <- renderText({
      subfolder
    })
    
    # JSON preview output
    output$json_preview <- renderText({
      config_json()
    })
    
    # Interactive tab server logic ----
    
    # Create reactive tibble to store PET files and their info
    pet_files_data <- reactive({
      tryCatch({
        # Look for TACs files in output directory
        tacs_pattern <- "*_desc-combinedregions_tacs.tsv"
        tacs_files <- list.files(output_dir, pattern = gsub("\\*", ".*", tacs_pattern), 
                                recursive = TRUE, full.names = TRUE)
        
        if (length(tacs_files) > 0) {
          # Use unified BIDS parsing to extract PET identifiers
          pet_names <- get_pet_identifiers(tacs_files, output_dir)
          
          # Create tibble with pet names and file paths
          tibble::tibble(
            pet = pet_names,
            filename = tacs_files
          )
        } else {
          # Return empty tibble if no files found
          tibble::tibble(pet = character(0), filename = character(0))
        }
      }, error = function(e) {
        cat("Error loading TACs files for interactive mode:", e$message, "\n")
        tibble::tibble(pet = character(0), filename = character(0))
      })
    })
    
    # Handle Scan Analysis Folder button
    observeEvent(input$scan_folder, {
      showNotification("Scanning analysis folder...", type = "message", duration = 2)
      
      tryCatch({
        pet_data <- pet_files_data()
        
        if (nrow(pet_data) > 0) {
          # Update PET measurement dropdown
          pet_choices <- c("None" = "none", setNames(pet_data$pet, pet_data$pet))
          updateSelectInput(session, "interactive_pet",
                           choices = pet_choices,
                           selected = "none")
          
          # Update region dropdown using first TACs file
          first_tacs_file <- pet_data$filename[1]
          tacs_data <- readr::read_tsv(first_tacs_file, show_col_types = FALSE)
          
          if ("region" %in% colnames(tacs_data)) {
            unique_regions <- sort(unique(tacs_data$region))
            unique_regions <- unique_regions[!is.na(unique_regions)]
            
            if (length(unique_regions) > 0) {
              region_choices <- c("None" = "none", setNames(unique_regions, unique_regions))
              updateSelectInput(session, "interactive_region",
                               choices = region_choices,
                               selected = "none")
              
              showNotification(paste("Found", nrow(pet_data), "PET measurements and", length(unique_regions), "regions"), 
                              type = "message", duration = 4)
              cat("Scanned:", nrow(pet_data), "TACs files,", length(unique_regions), "regions\n")
            } else {
              updateSelectInput(session, "interactive_region",
                               choices = c("No regions found" = "none"),
                               selected = "none")
              showNotification("Found files but no regions detected", type = "warning", duration = 4)
            }
          } else {
            updateSelectInput(session, "interactive_region",
                             choices = c("No region column found" = "none"),
                             selected = "none")
            showNotification("Found files but no region column detected", type = "warning", duration = 4)
          }
        } else {
          # No TACs files found
          updateSelectInput(session, "interactive_pet",
                           choices = c("No TACs files found" = "none"),
                           selected = "none")
          updateSelectInput(session, "interactive_region",
                           choices = c("No TACs files found" = "none"),
                           selected = "none")
          showNotification("No TACs files found. Run 'Data Definition' first to create analysis data.", 
                          type = "warning", duration = 6)
        }
        
      }, error = function(e) {
        showNotification(paste("Error scanning folder:", e$message), type = "error", duration = 5)
        cat("Error in scan_folder:", e$message, "\n")
      })
    })
    
    # Create reactive value to store plot data (only updates on button press)
    plot_data <- reactiveVal(NULL)
    
    # Handle Load Data button
    observeEvent(input$load_data, {
      # Check if PET and Region are selected
      if (input$interactive_pet == "none" || input$interactive_region == "none") {
        showNotification("PET and Region must be specified before loading data", 
                        type = "error", duration = 5)
        return()
      }
      
      tryCatch({
        # Get the correct filename from our tibble
        pet_data <- pet_files_data()
        pet_file_info <- pet_data[pet_data$pet == input$interactive_pet, ]
        
        if (nrow(pet_file_info) == 0) {
          showNotification("Selected PET measurement not found", type = "error", duration = 5)
          return()
        }
        
        # Load and check data
        tacs_data <- readr::read_tsv(pet_file_info$filename[1], show_col_types = FALSE)
        region_data <- tacs_data[tacs_data$region == input$interactive_region, ]
        
        # Get model information
        model_display <- switch(input$interactive_model,
                               "none" = "TAC Data Only",
                               "model1" = "Model 1",
                               "model2" = "Model 2", 
                               "model3" = "Model 3")
        
        if (nrow(region_data) > 0) {
          # Store the plot data with metadata
          plot_data(list(
            data = region_data,
            pet = input$interactive_pet,
            region = input$interactive_region,
            model = input$interactive_model,
            model_display = model_display
          ))
          
          showNotification(paste("Loaded TAC data for", input$interactive_region, "in", input$interactive_pet, "| View:", model_display), 
                          type = "message", duration = 3)
        } else {
          showNotification("No data found for selected region", type = "warning", duration = 3)
        }
        
      }, error = function(e) {
        showNotification(paste("Error loading data:", e$message), type = "error", duration = 5)
        cat("Error in load_data:", e$message, "\n")
      })
    })
    
    # Handle Fit Model button (placeholder for now)
    observeEvent(input$fit_model, {
      req(input$load_data > 0)
      
      showNotification("Model fitting functionality coming soon", 
                      type = "message", duration = 3)
    })
    
    # Generate TAC plot (only uses data stored by Load Data button)
    output$tac_plot <- renderPlot({
      # Only react to the stored plot data, not the input values
      plot_info <- plot_data()
      req(plot_info)
      
      tryCatch({
        region_data <- plot_info$data
        
        if (nrow(region_data) == 0) {
          # Create empty plot with message
          plot.new()
          text(0.5, 0.5, "No data available for selected region", 
               cex = 1.2, col = "red")
          return()
        }
        
        # Create the plot using stored data and metadata
        # library(ggplot2)
        
        p <- ggplot(region_data, aes(x = frame_mid/60, y = TAC)) +
          geom_line(color = "#4DAF4A", linewidth = 0.25) +
          geom_point(color = "#377EB8") +
          labs(
            title = paste0(plot_info$pet, " : ", plot_info$region ),
            x = "Time (min)",
            y = "Radioactivity"
          ) +
          theme_light()
        
        # Future: Add model fitting and overlay when model1/model2/model3 selected
        # For now, all options show the same TAC plot
        
        print(p)
        
      }, error = function(e) {
        # Create error plot
        plot.new()
        text(0.5, 0.5, paste("Error generating plot:", e$message), 
             cex = 1, col = "red", adj = 0.5)
        cat("Error in tac_plot:", e$message, "\n")
      })
    }, width = 800, height = 500, res = 96)
    
  }
  
  # Create the application
  app <- shiny::shinyApp(ui = ui, server = server)
  
  # Run with Docker-compatible settings
  cat("If running from within a docker container, open one of the following addresses in your web browser.\n")
  cat("http://localhost:3838\n")
  shiny::runApp(app, host = "0.0.0.0", port = 3838)
}