#' Run petfit Modelling App for Reference Tissue Models
#'
#' @description Launch the petfit modelling configuration interface for setting up reference tissue kinetic models
#'
#' @param bids_dir Character string path to the BIDS directory (default: NULL)
#' @param derivatives_dir Character string path to the derivatives folder (default: bids_dir/derivatives)
#' @param blood_dir Character string path to the blood data directory (default: NULL)
#' @param subfolder Character string name for analysis subfolder (default: "Primary_Analysis")
#' @param config_file Character string path to existing config file (optional)
#' @export
modelling_ref_app <- function(bids_dir = NULL, derivatives_dir = NULL, blood_dir = NULL, subfolder = "Primary_Analysis", config_file = NULL) {
  
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
  if (!is.null(blood_dir)) {
    blood_dir <- normalizePath(blood_dir, mustWork = FALSE)
  }
  
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
  expected_config_type <- "reference tissue"

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
    titlePanel("PETFit Modelling App for Reference Tissue Models"),
    
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

                         br(),
                         h4("TAC Time Range Selection"),
                         p("Optionally subset TAC data by frame number or time range. This will apply to all models unless overridden by a further reduced subset in individual model configurations.",
                           style = "font-size:14px;"
                         ),
                         fluidRow(
                           column(4,
                                  selectInput(inputId = "subset_tac_type",
                                            label = "Selection Method",
                                            choices = c("None" = "none",
                                                      "Frame Number" = "frame",
                                                      "Time (minutes)" = "time"),
                                            selected = "none")
                           ),
                           column(4,
                                  conditionalPanel(
                                    condition = "input.subset_tac_type != 'none'",
                                    numericInput(inputId = "subset_tac_start",
                                                label = "Start Point",
                                                value = NULL,
                                                min = 0)
                                  )
                           ),
                           column(4,
                                  conditionalPanel(
                                    condition = "input.subset_tac_type != 'none'",
                                    numericInput(inputId = "subset_tac_end",
                                                label = "End Point",
                                                value = NULL,
                                                min = 0)
                                  )
                           )
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
                    # Tab panel for Reference TAC ----
                    tabPanel("Reference TAC",
                             br(),
                             h3("Reference Region Selection"),
                             p("Select the reference region to use for all reference tissue models. The same reference region will be used for Model 1, Model 2, and Model 3.",
                               style = "font-size:14px; margin-bottom:20px;"
                             ),

                             fluidRow(
                               column(6,
                                 selectInput("ref_region", "Reference Region:",
                                           choices = c("Loading..." = ""),
                                           selected = "",
                                           width = "100%")
                               )
                             ),

                             hr(),
                             h3("Reference TAC Fitting"),
                             p(strong("Note:"), " Fitting the reference TAC is generally not necessary for most analyses. However, it can be beneficial when dealing with very noisy reference region time activity curves, as it can help smooth the data and improve model stability.",
                               style = "font-size:14px; margin-bottom:20px;"
                             ),

                             fluidRow(
                               column(4,
                                 selectInput("ref_fitting_method", "Reference TAC Method:",
                                           choices = c("Raw Reference TAC" = "raw",
                                                     "Fit the Reference TAC with Feng+1TC Reference Model" = "feng1tc",
                                                     "Fit the Reference TAC with a Spline Model" = "spline"),
                                           selected = "raw",
                                           width = "100%")
                               ),
                               column(3,
                                 conditionalPanel(
                                   condition = "input.ref_fitting_method == 'spline'",
                                   numericInput("ref_spline_df", "Degrees of Freedom:",
                                              value = 10, min = 2, max = 20, step = 1)
                                 )
                               ),
                              column(5,
                                conditionalPanel(
                                  condition = "input.ref_fitting_method == 'raw'",
                                  div(
                                    checkboxInput("ref_noise_approximation",
                                                "Approximate noise in reference region using splines",
                                                value = FALSE),
                                    p("If selected, the noise level in the reference region will be compared to target regions. This can help identify if the reference region is particularly noisy.",
                                      style = "font-size:11px; color:#6c757d; margin-top:0px;")
                                  )
                                )
                              )
                             ),

                             # Reference TAC Weighting Method section - only shown when fitting is enabled
                             conditionalPanel(
                               condition = "input.ref_fitting_method != 'raw'",
                               hr(),
                               h3("Reference TAC Weighting Method"),
                               p("Configure weighting for the reference TAC when fitting is applied. By default, the same weights as the target TACs will be used, but you can specify different weights if the reference region is particularly noisy.",
                                 style = "font-size:14px; margin-bottom:20px;"
                               ),

                               fluidRow(
                                 column(8,
                                   selectInput("ref_weights_method", "Reference Weighting Method:",
                                             choices = c("Same weights as Target TAC" = "same_as_target",
                                                       "0. Uniform (all weights = 1)" = "0",
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
                                             selected = "same_as_target",
                                             width = "100%")
                                 )
                               ),

                               # Minimum weight input - only shown when not using same_as_target
                               conditionalPanel(
                                 condition = "input.ref_weights_method != 'same_as_target'",
                                 br(),
                                 fluidRow(
                                   column(4,
                                     numericInput("ref_weights_minweight", "Minimum Weight:",
                                                value = 0.25, min = 0.001, max = 1, step = 0.001)
                                   )
                                 )
                               ),

                               # Custom formula panel
                               conditionalPanel(
                                 condition = "input.ref_weights_method == 'custom'",
                                 br(),
                                 div(
                                   h4("Custom Formula"),
                                   p("Define a custom weighting formula using available variables:",
                                     style = "font-size:14px; margin-bottom:10px;"),
                                   textAreaInput("ref_weights_custom_formula", "",
                                               value = "",
                                               rows = 2,
                                               placeholder = "e.g., (frame_dur^2) / tac_uncor")
                                 )
                               ),

                               # Available variables documentation - shown for custom or non-same_as_target
                               conditionalPanel(
                                 condition = "input.ref_weights_method != 'same_as_target'",
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
                                 )
                               )
                             ),

                             hr(),
                             actionButton("run_reference_tac", "▶ Prepare Reference TACs", class = "btn-success btn-lg")
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
                                                     "refLogan" = "refLogan",
                                                     "MRTM1" = "MRTM1",
                                                     "MRTM2" = "MRTM2"),
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
                                                     "SRTM (Non-linear)" = "SRTM",
                                                     "SRTM2 (Non-linear)" = "SRTM2",
                                                     "refLogan (Linear)" = "refLogan",
                                                     "MRTM1 (Linear)" = "MRTM1",
                                                     "MRTM2 (Linear)" = "MRTM2"
                                         ),
                                         selected = "none"),
                             # SRTM selection panel
                             conditionalPanel(
                               condition = "input.button == 'SRTM'",
                               fluidRow(
                                 column(3, offset = 0, numericInput("R1.start", "R1.start", value = 1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("R1.lower", "R1.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("R1.upper", "R1.upper", value = 5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("k2.start", "k2.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k2.lower", "k2.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k2.upper", "k2.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("BPnd.start", "BPnd.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("BPnd.lower", "BPnd.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("BPnd.upper", "BPnd.upper", value = 0.5,min = 0, step=.001)),
                               ),

                               # TAC Subset Selection
                               h4("TAC Subset Selection"),
                               p("Specify subset of TAC data for fitting (optional). This can further reduce the data defined at the data definition step."),
                               fluidRow(
                                 column(4,
                                        selectInput("subset_type", "Selection Method:",
                                                  choices = list("None" = "none",
                                                               "Frame Numbers" = "frame",
                                                               "Time Points (minutes)" = "time"),
                                                  selected = "none")
                                 ),
                                 column(4,
                                        conditionalPanel(
                                          condition = "input.subset_type != 'none'",
                                          numericInput("start_point", "Start Point", value = NULL, min = 0, step = 0.1)
                                        )
                                 ),
                                 column(4,
                                        conditionalPanel(
                                          condition = "input.subset_type != 'none'",
                                          numericInput("end_point", "End Point", value = NULL, min = 0, step = 0.1)
                                        )
                                 )
                               ),
                               uiOutput("subset_validation_error")
                             ),

                            # SRTM2 selection panel
                            conditionalPanel(
                              condition = "input.button == 'SRTM2'",
                              h4("Model Parameters"),
                              fluidRow(
                                column(3, offset = 0, numericInput("R1.start", "R1.start", value = 1,min = 0, step=.001)),
                                column(3, offset = 0, numericInput("R1.lower", "R1.lower", value = 0.0001,min = 0, step=.001)),
                                column(3, offset = 0, numericInput("R1.upper", "R1.upper", value = 5,min = 0, step=.001)),
                              ),
                              fluidRow(
                                column(3, offset = 0, numericInput("BPnd.start", "BPnd.start", value = 0.1,min = 0, step=.001)),
                                column(3, offset = 0, numericInput("BPnd.lower", "BPnd.lower", value = 0.0001,min = 0, step=.001)),
                                column(3, offset = 0, numericInput("BPnd.upper", "BPnd.upper", value = 5,min = 0, step=.001)),
                              ),

                              h4("Other Parameters"),
                              selectInput("k2prime_source", "k2' Parameter Source:",
                                         choices = list("Set k2'" = "set"),
                                         selected = "set"),
                              conditionalPanel(
                                condition = "input.k2prime_source == 'set'",
                                numericInput("k2prime_value", "k2' Value", value = 0.1, min = 0, step = 0.001)
                              ),

                              # TAC Subset Selection
                              h4("TAC Subset Selection"),
                              p("Specify subset of TAC data for fitting (optional). This can further reduce the data defined at the data definition step."),
                              fluidRow(
                                column(4,
                                       selectInput("subset_type", "Selection Method:",
                                                 choices = list("None" = "none",
                                                              "Frame Numbers" = "frame",
                                                              "Time Points (minutes)" = "time"),
                                                 selected = "none")
                                ),
                                column(4,
                                       conditionalPanel(
                                         condition = "input.subset_type != 'none'",
                                         numericInput("start_point", "Start Point", value = NULL, min = 0, step = 0.1)
                                       )
                                ),
                                column(4,
                                       conditionalPanel(
                                         condition = "input.subset_type != 'none'",
                                         numericInput("end_point", "End Point", value = NULL, min = 0, step = 0.1)
                                       )
                                )
                              ),
                              uiOutput("subset_validation_error")
                            ),

                             # refLogan selection panel  
                             conditionalPanel(
                               condition = "input.button == 'refLogan'",
                               h4("t* Definition"),
                               p("Define t* (time point for linear analysis start) using frame numbers or time."),
                               radioButtons("tstar_type", "",
                                           choices = list("Number of Frames (from the end)" = "frame", 
                                                         "Time Point (minutes)" = "time"),
                                           selected = "frame", inline = TRUE),
                               numericInput("tstar", "t* (0 for all frames)", value = 10, min = 0, step = 1),
                               
                               h4("Other Parameters"),
                               selectInput("k2prime_source", "k2' Parameter Source:",
                                          choices = list("Set k2'" = "set"),
                                          selected = "set"),
                               numericInput("k2prime_value", "k2' Value", value = 0.1, min = 0, step = 0.001),
                               
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
                             
                             # MRTM1 selection panel
                             conditionalPanel(
                               condition = "input.button == 'MRTM1'",
                               h4("t* Definition"),
                               p("Define t* (time point for linear analysis start) using frame numbers or time."),
                               radioButtons("tstar_type", "",
                                           choices = list("Number of Frames (from the end)" = "frame", 
                                                         "Time Point (minutes)" = "time"),
                                           selected = "frame", inline = TRUE),
                               numericInput("tstar", "t* (0 for all frames)", value = 10, min = 0, step = 1),
                               
                               h4("Other Parameters"),
                               
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
                             
                             # MRTM2 selection panel
                             conditionalPanel(
                               condition = "input.button == 'MRTM2'",
                               h4("t* Definition"),
                               p("Define t* (time point for linear analysis start) using frame numbers or time."),
                               radioButtons("tstar_type", "",
                                           choices = list("Number of Frames (from the end)" = "frame", 
                                                         "Time Point (minutes)" = "time"),
                                           selected = "frame", inline = TRUE),
                               numericInput("tstar", "t* (0 for all frames)", value = 10, min = 0, step = 1),
                               
                               h4("Other Parameters"),
                               selectInput("k2prime_source", "k2' Parameter Source:",
                                          choices = list("Set k2'" = "set"),
                                          selected = "set"),
                               numericInput("k2prime_value", "k2' Value (k2a prior)", value = 0.1, min = 0, step = 0.001),
                               
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
                             uiOutput("subset_validation_error"),
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
                                                     "SRTM (Non-linear)" = "SRTM",
                                                     "SRTM2 (Non-linear)" = "SRTM2",
                                                     "refLogan (Linear)" = "refLogan",
                                                     "MRTM1 (Linear)" = "MRTM1",
                                                     "MRTM2 (Linear)" = "MRTM2"
                                         ),
                                         selected = "none"),
                             # SRTM selection panel
                             conditionalPanel(
                               condition = "input.button2 == 'SRTM'",
                               fluidRow(
                                 column(3, offset = 0, numericInput("R1.start2", "R1.start", value = 1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("R1.lower2", "R1.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("R1.upper2", "R1.upper", value = 5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("k2.start2", "k2.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k2.lower2", "k2.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k2.upper2", "k2.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("BPnd.start2", "BPnd.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("BPnd.lower2", "BPnd.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("BPnd.upper2", "BPnd.upper", value = 0.5,min = 0, step=.001)),
                               ),

                               # TAC Subset Selection
                               h4("TAC Subset Selection"),
                               p("Specify subset of TAC data for fitting (optional). This can further reduce the data defined at the data definition step."),
                               fluidRow(
                                 column(4,
                                        selectInput("subset_type2", "Selection Method:",
                                                  choices = list("None" = "none",
                                                               "Frame Numbers" = "frame",
                                                               "Time Points (minutes)" = "time"),
                                                  selected = "none")
                                 ),
                                 column(4,
                                        conditionalPanel(
                                          condition = "input.subset_type2 != 'none'",
                                          numericInput("start_point2", "Start Point", value = NULL, min = 0, step = 0.1)
                                        )
                                 ),
                                 column(4,
                                        conditionalPanel(
                                          condition = "input.subset_type2 != 'none'",
                                          numericInput("end_point2", "End Point", value = NULL, min = 0, step = 0.1)
                                        )
                                 )
                               ),
                               uiOutput("subset_validation_error2")
                             ),

                            # SRTM2 selection panel
                            conditionalPanel(
                              condition = "input.button2 == 'SRTM2'",
                              h4("Model Parameters"),
                              fluidRow(
                                column(3, offset = 0, numericInput("R1.start2", "R1.start", value = 1,min = 0, step=.001)),
                                column(3, offset = 0, numericInput("R1.lower2", "R1.lower", value = 0.0001,min = 0, step=.001)),
                                column(3, offset = 0, numericInput("R1.upper2", "R1.upper", value = 5,min = 0, step=.001)),
                              ),
                              fluidRow(
                                column(3, offset = 0, numericInput("BPnd.start2", "BPnd.start", value = 0.1,min = 0, step=.001)),
                                column(3, offset = 0, numericInput("BPnd.lower2", "BPnd.lower", value = 0.0001,min = 0, step=.001)),
                                column(3, offset = 0, numericInput("BPnd.upper2", "BPnd.upper", value = 5,min = 0, step=.001)),
                              ),

                              h4("Other Parameters"),
                              selectInput("k2prime_source2", "k2' Parameter Source:",
                                         choices = list(
                                           "Set k2'" = "set",
                                           "Inherit k2' from Model 1 (Regional)" = "inherit_model1_regional",
                                           "Inherit k2' from Model 1 (Mean Across Regions)" = "inherit_model1_mean",
                                           "Inherit k2' from Model 1 (Median Across Regions)" = "inherit_model1_median"
                                         ),
                                         selected = "set"),
                              conditionalPanel(
                                condition = "input.k2prime_source2 == 'set'",
                                numericInput("k2prime_value2", "k2' Value", value = 0.1, min = 0, step = 0.001)
                              ),

                              # TAC Subset Selection
                              h4("TAC Subset Selection"),
                              p("Specify subset of TAC data for fitting (optional). This can further reduce the data defined at the data definition step."),
                              fluidRow(
                                column(4,
                                       selectInput("subset_type2", "Selection Method:",
                                                 choices = list("None" = "none",
                                                              "Frame Numbers" = "frame",
                                                              "Time Points (minutes)" = "time"),
                                                 selected = "none")
                                ),
                                column(4,
                                       conditionalPanel(
                                         condition = "input.subset_type2 != 'none'",
                                         numericInput("start_point2", "Start Point", value = NULL, min = 0, step = 0.1)
                                       )
                                ),
                                column(4,
                                       conditionalPanel(
                                         condition = "input.subset_type2 != 'none'",
                                         numericInput("end_point2", "End Point", value = NULL, min = 0, step = 0.1)
                                       )
                                )
                              ),
                              uiOutput("subset_validation_error2")
                            ),

                             # refLogan selection panel
                             conditionalPanel(
                               condition = "input.button2 == 'refLogan'",
                               h4("t* Definition"),
                               p("Define t* (time point for linear analysis start) using frame numbers or time."),
                               radioButtons("tstar_type2", "",
                                           choices = list("Number of Frames (from the end)" = "frame", 
                                                         "Time Point (minutes)" = "time"),
                                           selected = "frame", inline = TRUE),
                               numericInput("tstar2", "t* (0 for all frames)", value = 10, min = 0, step = 1),
                               
                               h4("Other Parameters"),
                               selectInput("k2prime_source2", "k2' Parameter Source:",
                                          choices = list(
                                            "Set k2'" = "set",
                                            "Inherit k2' from Model 1 (Regional)" = "inherit_model1_regional",
                                            "Inherit k2' from Model 1 (Mean Across Regions)" = "inherit_model1_mean",
                                            "Inherit k2' from Model 1 (Median Across Regions)" = "inherit_model1_median"
                                          ),
                                          selected = "set"),
                               conditionalPanel(
                                 condition = "input.k2prime_source2 == 'set'",
                                 numericInput("k2prime_value2", "k2' Value", value = 0.1, min = 0, step = 0.001)
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
                             
                             # MRTM1 selection panel
                             conditionalPanel(
                               condition = "input.button2 == 'MRTM1'",
                               h4("t* Definition"),
                               p("Define t* (time point for linear analysis start) using frame numbers or time."),
                               radioButtons("tstar_type2", "",
                                           choices = list("Number of Frames (from the end)" = "frame", 
                                                         "Time Point (minutes)" = "time"),
                                           selected = "frame", inline = TRUE),
                               numericInput("tstar2", "t* (0 for all frames)", value = 10, min = 0, step = 1),
                               
                               h4("Other Parameters"),
                               
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
                             
                             # MRTM2 selection panel
                             conditionalPanel(
                               condition = "input.button2 == 'MRTM2'",
                               h4("t* Definition"),
                               p("Define t* (time point for linear analysis start) using frame numbers or time."),
                               radioButtons("tstar_type2", "",
                                           choices = list("Number of Frames (from the end)" = "frame", 
                                                         "Time Point (minutes)" = "time"),
                                           selected = "frame", inline = TRUE),
                               numericInput("tstar2", "t* (0 for all frames)", value = 10, min = 0, step = 1),
                               
                               h4("Other Parameters"),
                               selectInput("k2prime_source2", "k2' Parameter Source:",
                                          choices = list(
                                            "Set k2'" = "set",
                                            "Inherit k2' from Model 1 (Regional)" = "inherit_model1_regional",
                                            "Inherit k2' from Model 1 (Mean Across Regions)" = "inherit_model1_mean",
                                            "Inherit k2' from Model 1 (Median Across Regions)" = "inherit_model1_median"
                                          ),
                                          selected = "set"),
                               conditionalPanel(
                                 condition = "input.k2prime_source2 == 'set'",
                                 numericInput("k2prime_value2", "k2' Value (k2a prior)", value = 0.1, min = 0, step = 0.001)
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
                             uiOutput("subset_validation_error2"),
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
                                                     "SRTM (Non-linear)" = "SRTM",
                                                     "SRTM2 (Non-linear)" = "SRTM2",
                                                     "refLogan (Linear)" = "refLogan",
                                                     "MRTM1 (Linear)" = "MRTM1",
                                                     "MRTM2 (Linear)" = "MRTM2"
                                         ),
                                         selected = "none"),
                             # SRTM selection panel
                             conditionalPanel(
                               condition = "input.button3 == 'SRTM'",
                               fluidRow(
                                 column(3, offset = 0, numericInput("R1.start3", "R1.start", value = 1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("R1.lower3", "R1.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("R1.upper3", "R1.upper", value = 5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("k2.start3", "k2.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k2.lower3", "k2.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("k2.upper3", "k2.upper", value = 0.5,min = 0, step=.001)),
                               ),
                               fluidRow(
                                 column(3, offset = 0, numericInput("BPnd.start3", "BPnd.start", value = 0.1,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("BPnd.lower3", "BPnd.lower", value = 0.0001,min = 0, step=.001)),
                                 column(3, offset = 0, numericInput("BPnd.upper3", "BPnd.upper", value = 0.5,min = 0, step=.001)),
                               ),

                               # TAC Subset Selection
                               h4("TAC Subset Selection"),
                               p("Specify subset of TAC data for fitting (optional). This can further reduce the data defined at the data definition step."),
                               fluidRow(
                                 column(4,
                                        selectInput("subset_type3", "Selection Method:",
                                                  choices = list("None" = "none",
                                                               "Frame Numbers" = "frame",
                                                               "Time Points (minutes)" = "time"),
                                                  selected = "none")
                                 ),
                                 column(4,
                                        conditionalPanel(
                                          condition = "input.subset_type3 != 'none'",
                                          numericInput("start_point3", "Start Point", value = NULL, min = 0, step = 0.1)
                                        )
                                 ),
                                 column(4,
                                        conditionalPanel(
                                          condition = "input.subset_type3 != 'none'",
                                          numericInput("end_point3", "End Point", value = NULL, min = 0, step = 0.1)
                                        )
                                 )
                               ),
                               uiOutput("subset_validation_error3")
                             ),

                            # SRTM2 selection panel
                            conditionalPanel(
                              condition = "input.button3 == 'SRTM2'",
                              h4("Model Parameters"),
                              fluidRow(
                                column(3, offset = 0, numericInput("R1.start3", "R1.start", value = 1,min = 0, step=.001)),
                                column(3, offset = 0, numericInput("R1.lower3", "R1.lower", value = 0.0001,min = 0, step=.001)),
                                column(3, offset = 0, numericInput("R1.upper3", "R1.upper", value = 5,min = 0, step=.001)),
                              ),
                              fluidRow(
                                column(3, offset = 0, numericInput("BPnd.start3", "BPnd.start", value = 0.1,min = 0, step=.001)),
                                column(3, offset = 0, numericInput("BPnd.lower3", "BPnd.lower", value = 0.0001,min = 0, step=.001)),
                                column(3, offset = 0, numericInput("BPnd.upper3", "BPnd.upper", value = 5,min = 0, step=.001)),
                              ),

                              h4("Other Parameters"),
                              selectInput("k2prime_source3", "k2' Parameter Source:",
                                         choices = list(
                                           "Set k2'" = "set",
                                           "Inherit k2' from Model 1 (Regional)" = "inherit_model1_regional",
                                           "Inherit k2' from Model 1 (Mean Across Regions)" = "inherit_model1_mean",
                                           "Inherit k2' from Model 1 (Median Across Regions)" = "inherit_model1_median",
                                           "Inherit k2' from Model 2 (Regional)" = "inherit_model2_regional",
                                           "Inherit k2' from Model 2 (Mean Across Regions)" = "inherit_model2_mean",
                                           "Inherit k2' from Model 2 (Median Across Regions)" = "inherit_model2_median"
                                         ),
                                         selected = "set"),
                              conditionalPanel(
                                condition = "input.k2prime_source3 == 'set'",
                                numericInput("k2prime_value3", "k2' Value", value = 0.1, min = 0, step = 0.001)
                              ),

                              # TAC Subset Selection
                              h4("TAC Subset Selection"),
                              p("Specify subset of TAC data for fitting (optional). This can further reduce the data defined at the data definition step."),
                              fluidRow(
                                column(4,
                                       selectInput("subset_type3", "Selection Method:",
                                                 choices = list("None" = "none",
                                                              "Frame Numbers" = "frame",
                                                              "Time Points (minutes)" = "time"),
                                                 selected = "none")
                                ),
                                column(4,
                                       conditionalPanel(
                                         condition = "input.subset_type3 != 'none'",
                                         numericInput("start_point3", "Start Point", value = NULL, min = 0, step = 0.1)
                                       )
                                ),
                                column(4,
                                       conditionalPanel(
                                         condition = "input.subset_type3 != 'none'",
                                         numericInput("end_point3", "End Point", value = NULL, min = 0, step = 0.1)
                                       )
                                )
                              ),
                              uiOutput("subset_validation_error3")
                            ),

                             # refLogan selection panel  
                             conditionalPanel(
                               condition = "input.button3 == 'refLogan'",
                               h4("t* Definition"),
                               p("Define t* (time point for linear analysis start) using frame numbers or time."),
                               radioButtons("tstar_type3", "",
                                           choices = list("Number of Frames (from the end)" = "frame", 
                                                         "Time Point (minutes)" = "time"),
                                           selected = "frame", inline = TRUE),
                               numericInput("tstar3", "t* (0 for all frames)", value = 10, min = 0, step = 1),
                               
                               h4("Other Parameters"),
                               selectInput("k2prime_source3", "k2' Parameter Source:",
                                          choices = list(
                                            "Set k2'" = "set",
                                            "Inherit k2' from Model 1 (Regional)" = "inherit_model1_regional",
                                            "Inherit k2' from Model 1 (Mean Across Regions)" = "inherit_model1_mean",
                                            "Inherit k2' from Model 1 (Median Across Regions)" = "inherit_model1_median",
                                            "Inherit k2' from Model 2 (Regional)" = "inherit_model2_regional",
                                            "Inherit k2' from Model 2 (Mean Across Regions)" = "inherit_model2_mean",
                                            "Inherit k2' from Model 2 (Median Across Regions)" = "inherit_model2_median"
                                          ),
                                          selected = "set"),
                               conditionalPanel(
                                 condition = "input.k2prime_source3 == 'set'",
                                 numericInput("k2prime_value3", "k2' Value", value = 0.1, min = 0, step = 0.001)
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
                             
                             # MRTM1 selection panel
                             conditionalPanel(
                               condition = "input.button3 == 'MRTM1'",
                               h4("t* Definition"),
                               p("Define t* (time point for linear analysis start) using frame numbers or time."),
                               radioButtons("tstar_type3", "",
                                           choices = list("Number of Frames (from the end)" = "frame", 
                                                         "Time Point (minutes)" = "time"),
                                           selected = "frame", inline = TRUE),
                               numericInput("tstar3", "t* (0 for all frames)", value = 10, min = 0, step = 1),
                               
                               h4("Other Parameters"),
                               
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
                             
                             # MRTM2 selection panel
                             conditionalPanel(
                               condition = "input.button3 == 'MRTM2'",
                               h4("t* Definition"),
                               p("Define t* (time point for linear analysis start) using frame numbers or time."),
                               radioButtons("tstar_type3", "",
                                           choices = list("Number of Frames (from the end)" = "frame", 
                                                         "Time Point (minutes)" = "time"),
                                           selected = "frame", inline = TRUE),
                               numericInput("tstar3", "t* (0 for all frames)", value = 10, min = 0, step = 1),
                               
                               h4("Other Parameters"),
                               selectInput("k2prime_source3", "k2' Parameter Source:",
                                          choices = list(
                                            "Set k2'" = "set",
                                            "Inherit k2' from Model 1 (Regional)" = "inherit_model1_regional",
                                            "Inherit k2' from Model 1 (Mean Across Regions)" = "inherit_model1_mean",
                                            "Inherit k2' from Model 1 (Median Across Regions)" = "inherit_model1_median",
                                            "Inherit k2' from Model 2 (Regional)" = "inherit_model2_regional",
                                            "Inherit k2' from Model 2 (Mean Across Regions)" = "inherit_model2_mean",
                                            "Inherit k2' from Model 2 (Median Across Regions)" = "inherit_model2_median"
                                          ),
                                          selected = "set"),
                               conditionalPanel(
                                 condition = "input.k2prime_source3 == 'set'",
                                 numericInput("k2prime_value3", "k2' Value (k2a prior)", value = 0.1, min = 0, step = 0.001)
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
                             uiOutput("subset_validation_error3"),
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
                                      actionButton("save_config", "💾 Save Config", class = "btn-primary btn-lg"),
                                      br(), br(),
                                      actionButton("close_app", "✖ Close App", class = "btn-danger btn-lg")
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

          # Restore TAC subset parameters
          if (!is.null(existing_config$Subsetting$tac_subset)) {
            updateSelectInput(session, "subset_tac_type",
                            selected = existing_config$Subsetting$tac_subset$type %||% "none")
            updateNumericInput(session, "subset_tac_start",
                             value = existing_config$Subsetting$tac_subset$start)
            updateNumericInput(session, "subset_tac_end",
                             value = existing_config$Subsetting$tac_subset$end)
          } else {
            updateSelectInput(session, "subset_tac_type", selected = "none")
            updateNumericInput(session, "subset_tac_start", value = NULL)
            updateNumericInput(session, "subset_tac_end", value = NULL)
          }
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
          } else if (!is.null(model_type) && (model_type == "Logan" || model_type == "MA1")) {
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
              updateSelectInput(session, paste0("subset_type", suffix), selected = model_config$subset$type %||% "none")
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
              updateSelectInput(session, paste0("subset_type", suffix), selected = model_config$subset$type %||% "none")
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
            # Support both new BPnd configs and old k2a configs (backward compatibility)
            if (!is.null(model_config$BPnd)) {
              updateNumericInput(session, paste0("BPnd.start", suffix), value = model_config$BPnd$start %||% 0.1)
              updateNumericInput(session, paste0("BPnd.lower", suffix), value = model_config$BPnd$lower %||% 0.0001)
              updateNumericInput(session, paste0("BPnd.upper", suffix), value = model_config$BPnd$upper %||% 0.5)
            } else if (!is.null(model_config$k2a)) {
              updateNumericInput(session, paste0("BPnd.start", suffix), value = model_config$k2a$start %||% 0.1)
              updateNumericInput(session, paste0("BPnd.lower", suffix), value = model_config$k2a$lower %||% 0.0001)
              updateNumericInput(session, paste0("BPnd.upper", suffix), value = model_config$k2a$upper %||% 0.5)
            }
            # TAC Subset Selection restoration
            if (!is.null(model_config$subset)) {
              updateSelectInput(session, paste0("subset_type", suffix), selected = model_config$subset$type %||% "none")
              updateNumericInput(session, paste0("start_point", suffix), value = model_config$subset$start)
              updateNumericInput(session, paste0("end_point", suffix), value = model_config$subset$end)
            }
          } else if (!is.null(model_type) && model_type == "SRTM2") {
            if (!is.null(model_config$R1)) {
              updateNumericInput(session, paste0("R1.start", suffix), value = model_config$R1$start %||% 1)
              updateNumericInput(session, paste0("R1.lower", suffix), value = model_config$R1$lower %||% 0.0001)
              updateNumericInput(session, paste0("R1.upper", suffix), value = model_config$R1$upper %||% 5)
            }
            if (!is.null(model_config$BPnd)) {
              updateNumericInput(session, paste0("BPnd.start", suffix), value = model_config$BPnd$start %||% 0.1)
              updateNumericInput(session, paste0("BPnd.lower", suffix), value = model_config$BPnd$lower %||% 0.0001)
              updateNumericInput(session, paste0("BPnd.upper", suffix), value = model_config$BPnd$upper %||% 0.5)
            }
            if (!is.null(model_config$k2prime_source)) {
              updateSelectInput(session, paste0("k2prime_source", suffix), selected = model_config$k2prime_source %||% "set")
            }
            if (!is.null(model_config$k2prime_value)) {
              updateNumericInput(session, paste0("k2prime_value", suffix), value = model_config$k2prime_value %||% 0.1)
            }
            # TAC Subset Selection restoration
            if (!is.null(model_config$subset)) {
              updateSelectInput(session, paste0("subset_type", suffix), selected = model_config$subset$type %||% "none")
              updateNumericInput(session, paste0("start_point", suffix), value = model_config$subset$start)
              updateNumericInput(session, paste0("end_point", suffix), value = model_config$subset$end)
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
              updateSelectInput(session, paste0("subset_type", suffix), selected = model_config$subset$type %||% "none")
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
              updateSelectInput(session, paste0("subset_type", suffix), selected = model_config$subset$type %||% "none")
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
        # Restore ReferenceTAC settings
        if (!is.null(existing_config$ReferenceTAC)) {
          updateSelectInput(session, "ref_region",
                           selected = existing_config$ReferenceTAC$region %||% "")
          updateSelectInput(session, "ref_fitting_method",
                           selected = existing_config$ReferenceTAC$fitting_method %||% "raw")
          # Restore spline parameters (backward compatible)
          if (!is.null(existing_config$ReferenceTAC$spline_df)) {
            if (existing_config$ReferenceTAC$spline_df != "") {
              updateNumericInput(session, "ref_spline_df",
                               value = as.numeric(existing_config$ReferenceTAC$spline_df) %||% 10)
            }
          }
          # Restore noise approximation setting (backward compatible)
          if (!is.null(existing_config$ReferenceTAC$noise_approximation)) {
            if (existing_config$ReferenceTAC$noise_approximation != "") {
              updateCheckboxInput(session, "ref_noise_approximation",
                                value = existing_config$ReferenceTAC$noise_approximation %||% FALSE)
            }
          }
          # Restore reference weighting settings (backward compatible)
          if (!is.null(existing_config$ReferenceTAC$weights_method)) {
            updateSelectInput(session, "ref_weights_method",
                             selected = existing_config$ReferenceTAC$weights_method %||% "same_as_target")
          }
          if (!is.null(existing_config$ReferenceTAC$weights_minweight)) {
            # Only update if not empty string
            if (existing_config$ReferenceTAC$weights_minweight != "") {
              updateNumericInput(session, "ref_weights_minweight",
                               value = existing_config$ReferenceTAC$weights_minweight %||% 0.25)
            }
          }
          if (!is.null(existing_config$ReferenceTAC$weights_custom_formula)) {
            if (existing_config$ReferenceTAC$weights_custom_formula != "") {
              updateTextAreaInput(session, "ref_weights_custom_formula",
                                value = existing_config$ReferenceTAC$weights_custom_formula)
            }
          }
        }
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

    # Reactive function to populate reference region options from combined regions file ----
    observe({
      tryCatch({
        # Read region values from combined regions file (in petfit folder)
        combined_regions_file <- file.path(petfit_dir, "desc-combinedregions_tacs.tsv")

        cat("Looking for combined regions file for reference region population at:", combined_regions_file, "\n")

        if (file.exists(combined_regions_file)) {
          cat("Combined regions file found, reading region values...\n")
          combined_regions <- readr::read_tsv(combined_regions_file, show_col_types = FALSE)

          if (nrow(combined_regions) > 0 && "region" %in% colnames(combined_regions)) {
            # Get unique region values for reference region selection
            unique_regions <- sort(unique(combined_regions$region))
            unique_regions <- unique_regions[!is.na(unique_regions)]

            cat("Found", length(unique_regions), "unique regions:", paste(head(unique_regions, 10), collapse = ", "), "...\n")

            if (length(unique_regions) > 0) {
              # Create choices for region selection
              choices <- setNames(unique_regions, unique_regions)

              updateSelectInput(session, "ref_region",
                               choices = choices,
                               selected = unique_regions[1])

              cat("Successfully updated reference region dropdown\n")
            } else {
              updateSelectInput(session, "ref_region",
                               choices = c("No regions found" = ""),
                               selected = "")
            }
          } else {
            updateSelectInput(session, "ref_region",
                             choices = c("No region column found" = ""),
                             selected = "")
          }
        } else {
          updateSelectInput(session, "ref_region",
                           choices = c("Combined regions file not found" = ""),
                           selected = "")
        }
      }, error = function(e) {
        # If there's an error, provide default choice
        updateSelectInput(session, "ref_region",
                         choices = c("Error loading regions" = ""),
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

      # Add TAC subset if configured
      if (!is.null(input$subset_tac_type) && input$subset_tac_type != "none") {
        Subsetting$tac_subset <- list(
          type = input$subset_tac_type,
          start = input$subset_tac_start,
          end = input$subset_tac_end
        )
      }
      
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
      
      # Reference TAC Configuration
      # Calculate reference weights formula
      ref_weights_method_selected <- input$ref_weights_method %||% "same_as_target"
      if (ref_weights_method_selected == "same_as_target") {
        ref_weights_formula <- ""
      } else if (ref_weights_method_selected == "custom") {
        ref_weights_formula <- input$ref_weights_custom_formula %||% ""
      } else {
        ref_weights_formula <- method_formulas[ref_weights_method_selected] %||% ""
      }

      ReferenceTAC <- list(
        region = input$ref_region %||% "",
        fitting_method = input$ref_fitting_method %||% "raw",
        noise_approximation = if(input$ref_fitting_method == "raw") input$ref_noise_approximation %||% FALSE else "",
        spline_df = if(input$ref_fitting_method == "spline") as.character(input$ref_spline_df %||% 10) else "",
        weights_method = ref_weights_method_selected,
        weights_formula = ref_weights_formula,
        weights_minweight = if(ref_weights_method_selected != "same_as_target") input$ref_weights_minweight %||% 0.25 else "",
        weights_custom_formula = if(ref_weights_method_selected == "custom") input$ref_weights_custom_formula %||% "" else ""
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
        } else if (model_type == "Logan" || model_type == "MA1") {
          model_params$tstar = input[[paste0("tstar", suffix)]] %||% 10
          model_params$tstar_type = input[[paste0("tstar_type", suffix)]] %||% "frame"
          model_params$vB_source = input[[paste0("vB_source", suffix)]] %||% "set"
          if (input[[paste0("vB_source", suffix)]] == "set" || is.null(input[[paste0("vB_source", suffix)]])) {
            model_params$vB_value = input[[paste0("vB_value", suffix)]] %||% 0.05
          }
          
          # TAC Subset Selection
          subset_type <- input[[paste0("subset_type", suffix)]] %||% "none"
          start_point <- input[[paste0("start_point", suffix)]]
          end_point <- input[[paste0("end_point", suffix)]]

          if (!is.null(subset_type) && subset_type != "none" && (!is.null(start_point) || !is.null(end_point))) {
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
          subset_type <- input[[paste0("subset_type", suffix)]] %||% "none"
          start_point <- input[[paste0("start_point", suffix)]]
          end_point <- input[[paste0("end_point", suffix)]]

          if (!is.null(subset_type) && subset_type != "none" && (!is.null(start_point) || !is.null(end_point))) {
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
          model_params$BPnd = list(
            start = input[[paste0("BPnd.start", suffix)]] %||% 0.1,
            lower = input[[paste0("BPnd.lower", suffix)]] %||% 0.0001,
            upper = input[[paste0("BPnd.upper", suffix)]] %||% 0.5
          )

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
        } else if (model_type == "SRTM2") {
          model_params$R1 = list(
            start = input[[paste0("R1.start", suffix)]] %||% 1,
            lower = input[[paste0("R1.lower", suffix)]] %||% 0.0001,
            upper = input[[paste0("R1.upper", suffix)]] %||% 5
          )
          model_params$BPnd = list(
            start = input[[paste0("BPnd.start", suffix)]] %||% 0.1,
            lower = input[[paste0("BPnd.lower", suffix)]] %||% 0.0001,
            upper = input[[paste0("BPnd.upper", suffix)]] %||% 5
          )

          # k2prime parameter
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
        } else if (model_type == "MRTM1") {
          model_params$tstar = input[[paste0("tstar", suffix)]] %||% 10
          model_params$tstar_type = input[[paste0("tstar_type", suffix)]] %||% "frame"
          
          # TAC Subset Selection
          subset_type <- input[[paste0("subset_type", suffix)]] %||% "none"
          start_point <- input[[paste0("start_point", suffix)]]
          end_point <- input[[paste0("end_point", suffix)]]

          if (!is.null(subset_type) && subset_type != "none" && (!is.null(start_point) || !is.null(end_point))) {
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
          subset_type <- input[[paste0("subset_type", suffix)]] %||% "none"
          start_point <- input[[paste0("start_point", suffix)]]
          end_point <- input[[paste0("end_point", suffix)]]

          if (!is.null(subset_type) && subset_type != "none" && (!is.null(start_point) || !is.null(end_point))) {
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
        modelling_configuration_type = "reference tissue",
        analysis_folder = subfolder,
        config_created = format(Sys.time(), "%Y-%m-%d %H:%M"),
        blood_dir = blood_dir,
        Subsetting = Subsetting,
        Weights = Weights,
        ReferenceTAC = ReferenceTAC,
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
        expected_type <- "reference tissue"

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

    # Close app button handler
    observeEvent(input$close_app, {
      showNotification("Closing app...", type = "message", duration = 2)
      stopApp()
    })

    # ===========================================================================
    # Shared Step Execution Functions
    # ===========================================================================
    # These thin wrappers save config then delegate to core functions in pipeline_core.R
    # This allows both interactive (Shiny) and non-interactive (automatic) execution
    # to use the same business logic

    run_datadef_step <- function() {
      # Save config first
      save_config()

      # Config path
      config_path <- file.path(output_dir, "desc-petfitoptions_config.json")

      # Notification callback for Shiny
      notify <- function(msg, type) {
        showNotification(msg, type = type, duration = 5)
      }

      # Call core function
      result <- execute_datadef_step(
        config_path = config_path,
        output_dir = output_dir,
        petfit_dir = petfit_dir,
        bids_dir = bids_dir,
        blood_dir = NULL,  # Reference tissue models don't use blood data
        notify = notify
      )

      return(result$success)
    }

    run_weights_step <- function() {
      # Save config first
      save_config()

      # Config path
      config_path <- file.path(output_dir, "desc-petfitoptions_config.json")

      # Notification callback for Shiny
      notify <- function(msg, type) {
        showNotification(msg, type = type, duration = 5)
      }

      # Call core function
      result <- execute_weights_step(
        config_path = config_path,
        output_dir = output_dir,
        bids_dir = bids_dir,
        blood_dir = NULL,  # Reference tissue models don't use blood data
        notify = notify
      )

      return(result$success)
    }

    run_reference_tac_step <- function() {
      # Save config first
      save_config()

      # Config path
      config_path <- file.path(output_dir, "desc-petfitoptions_config.json")

      # Notification callback for Shiny
      notify <- function(msg, type) {
        showNotification(msg, type = type, duration = 5)
      }

      # Call core function
      result <- execute_reference_tac_step(
        config_path = config_path,
        output_dir = output_dir,
        bids_dir = bids_dir,
        notify = notify
      )

      return(result$success)
    }

    run_model_step <- function(model_num, subset_error_reactive = NULL) {
      # Validate TAC subset selection
      start_input <- switch(as.character(model_num),
                           "1" = input$start_point,
                           "2" = input$start_point2,
                           "3" = input$start_point3)

      end_input <- switch(as.character(model_num),
                         "1" = input$end_point,
                         "2" = input$end_point2,
                         "3" = input$end_point3)

      type_input <- switch(as.character(model_num),
                          "1" = input$subset_type,
                          "2" = input$subset_type2,
                          "3" = input$subset_type3)

      # Helper function to check if value is empty
      is_empty <- function(x) {
        is.null(x) || length(x) == 0 || (length(x) == 1 && is.na(x))
      }

      # Check if only one endpoint is provided
      start_empty <- is_empty(start_input)
      end_empty <- is_empty(end_input)

      if ((!start_empty && end_empty) || (start_empty && !end_empty)) {
        error_msg <- if (type_input == "frame") {
          "Please enter both start and end frames, or leave both blank"
        } else {
          "Please enter both start and end time points, or leave both blank"
        }

        if (!is.null(subset_error_reactive)) {
          subset_error_reactive(error_msg)
        }

        showNotification(error_msg, type = "error", duration = 5)
        return(FALSE)
      }

      # Clear error if validation passes
      if (!is.null(subset_error_reactive)) {
        subset_error_reactive(NULL)
      }

      # Save config first
      save_config()

      # Config path
      config_path <- file.path(output_dir, "desc-petfitoptions_config.json")

      # Notification callback for Shiny
      notify <- function(msg, type) {
        showNotification(msg, type = type, duration = 5)
      }

      # Call core function
      result <- execute_model_step(
        config_path = config_path,
        model_num = model_num,
        output_dir = output_dir,
        bids_dir = bids_dir,
        blood_dir = NULL,  # Reference tissue models don't use blood data
        notify = notify
      )

      return(result$success)
    }

    # ===========================================================================
    # Manual Button Handlers
    # ===========================================================================
    # Run button handlers - each saves config then executes step
    observeEvent(input$run_subset, {
      run_datadef_step()
    })
    
    observeEvent(input$run_weights, {
      run_weights_step()
    })

    observeEvent(input$run_reference_tac, {
      run_reference_tac_step()
    })

    # Reactive values for TAC subset validation errors
    subset_error <- reactiveVal(NULL)
    subset_error2 <- reactiveVal(NULL)
    subset_error3 <- reactiveVal(NULL)

    observeEvent(input$run_model1, {
      run_model_step(1, subset_error)
    })

    observeEvent(input$run_model2, {
      run_model_step(2, subset_error2)
    })

    observeEvent(input$run_model3, {
      run_model_step(3, subset_error3)
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
      showNotification("Starting automatic pipeline execution...", type = "message", duration = 3)
      cat("[Run All] Starting automatic pipeline execution...\n")

      # Run the automatic pipeline by calling each step function sequentially
      tryCatch({
        all_success <- TRUE

        # Step 1: Data Definition
        cat("[Run All] Executing step: datadef\n")
        if (run_datadef_step()) {
          cat("[Run All] Step datadef completed successfully\n")
        } else {
          cat("[Run All] Step datadef failed\n")
          all_success <- FALSE
        }

        # Step 2: Weights (only if previous step succeeded)
        if (all_success) {
          cat("[Run All] Executing step: weights\n")
          if (run_weights_step()) {
            cat("[Run All] Step weights completed successfully\n")
          } else {
            cat("[Run All] Step weights failed\n")
            all_success <- FALSE
          }
        }

        # Step 3: Reference TAC (only if previous steps succeeded)
        if (all_success) {
          cat("[Run All] Executing step: reference_tac\n")
          if (run_reference_tac_step()) {
            cat("[Run All] Step reference_tac completed successfully\n")
          } else {
            cat("[Run All] Step reference_tac failed\n")
            all_success <- FALSE
          }
        }

        # Step 4: Model 1 (only if previous steps succeeded)
        if (all_success && !is.null(input$button) && input$button != "No Model") {
          cat("[Run All] Executing step: model1\n")
          if (run_model_step(1, subset_error)) {
            cat("[Run All] Step model1 completed successfully\n")
          } else {
            cat("[Run All] Step model1 failed\n")
            all_success <- FALSE
          }
        }

        # Step 5: Model 2 (only if previous steps succeeded)
        if (all_success && !is.null(input$button2) && input$button2 != "No Model") {
          cat("[Run All] Executing step: model2\n")
          if (run_model_step(2, subset_error2)) {
            cat("[Run All] Step model2 completed successfully\n")
          } else {
            cat("[Run All] Step model2 failed\n")
            all_success <- FALSE
          }
        }

        # Step 6: Model 3 (only if previous steps succeeded)
        if (all_success && !is.null(input$button3) && input$button3 != "No Model") {
          cat("[Run All] Executing step: model3\n")
          if (run_model_step(3, subset_error3)) {
            cat("[Run All] Step model3 completed successfully\n")
          } else {
            cat("[Run All] Step model3 failed\n")
            all_success <- FALSE
          }
        }

        # Final status
        if (all_success) {
          cat("[Run All] Pipeline execution completed successfully\n")
          showNotification("All pipeline steps completed successfully! Closing app...",
                          type = "message", duration = 3)

          # Close app after brief delay to show success message
          later::later(function() {
            stopApp()
          }, delay = 3)
        } else {
          cat("[Run All] Pipeline execution failed\n")
          showNotification("Pipeline execution failed - check console for details",
                          type = "error", duration = 10)
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

    # TAC subset validation error messages
    output$subset_validation_error <- renderUI({
      error_msg <- subset_error()
      if (!is.null(error_msg)) {
        tags$p(error_msg, style = "color: red; margin-top: 5px;")
      }
    })

    output$subset_validation_error2 <- renderUI({
      error_msg <- subset_error2()
      if (!is.null(error_msg)) {
        tags$p(error_msg, style = "color: red; margin-top: 5px;")
      }
    })

    output$subset_validation_error3 <- renderUI({
      error_msg <- subset_error3()
      if (!is.null(error_msg)) {
        tags$p(error_msg, style = "color: red; margin-top: 5px;")
      }
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