#!/usr/bin/env Rscript

# Docker entry script for petfit apps
# Supports both interactive and automatic modes with flexible directory mounting

library(optparse)

# Define command line options
option_list <- list(
  make_option(c("--func"), type="character", default=NULL,
              help="App function to run: 'regiondef', 'modelling_plasma', or 'modelling_ref' [required]"),
  make_option(c("--mode"), type="character", default="interactive", 
              help="Execution mode: 'interactive' or 'automatic' [default: interactive]"),
  make_option(c("--step"), type="character", default=NULL, 
              help="Step to run in automatic mode: 'datadef', 'weights', 'delay', 'model1', 'model2', 'model3' [optional]"),
  make_option(c("--petfit_output_foldername"), type="character", default="petfit", 
              help="Name for petfit output folder within derivatives [default: petfit]"),
  make_option(c("--analysis_foldername"), type="character", default="Primary_Analysis", 
              help="Name for analysis subfolder [default: Primary_Analysis]")
)

# Parse arguments
opt_parser <- OptionParser(option_list=option_list, 
                          description="Docker entry point for petfit apps")
opt <- parse_args(opt_parser)

# Validate required arguments
if (is.null(opt$func)) {
  print_help(opt_parser)
  stop("--func is required: specify 'regiondef', 'modelling_plasma', or 'modelling_ref'", call.=FALSE)
}

if (!opt$func %in% c("regiondef", "modelling_plasma", "modelling_ref")) {
  stop("--func must be 'regiondef', 'modelling_plasma', or 'modelling_ref'", call.=FALSE)
}

if (!opt$mode %in% c("interactive", "automatic")) {
  stop("--mode must be 'interactive' or 'automatic'", call.=FALSE)
}

if (!is.null(opt$step) && !opt$step %in% c("datadef", "weights", "delay", "model1", "model2", "model3")) {
  stop("--step must be one of: 'datadef', 'weights', 'delay', 'model1', 'model2', 'model3'", call.=FALSE)
}

# Ignore step argument if in interactive mode
if (opt$mode == "interactive" && !is.null(opt$step)) {
  cat("Note: --step argument ignored in interactive mode\n")
  opt$step <- NULL
}

cat("=== petfit Docker Container ===\n")
cat("Function:", opt$func, "\n")
cat("Mode:", opt$mode, "\n")
if (!is.null(opt$step)) {
  cat("Step:", opt$step, "\n")
}
cat("petfit output folder:", opt$petfit_output_foldername, "\n")
cat("Analysis folder:", opt$analysis_foldername, "\n")
cat("\n")

# Detect mounted directories
detect_mounted_directories <- function() {
  bids_available <- dir.exists("/data/bids_dir")
  derivatives_available <- dir.exists("/data/derivatives_dir")
  blood_available <- dir.exists("/data/blood_dir")
  
  cat("=== Directory Detection ===\n")
  cat("BIDS directory mounted:", bids_available, "\n")
  cat("Derivatives directory mounted:", derivatives_available, "\n")
  cat("Blood directory mounted:", blood_available, "\n")
  cat("\n")
  
  # Validate at least one primary directory exists
  if (!bids_available && !derivatives_available) {
    stop("At least one of bids_dir or derivatives_dir must be mounted", call.=FALSE)
  }
  
  # Set directory paths based on what's available
  bids_dir <- if(bids_available) "/data/bids_dir" else NULL
  derivatives_dir <- if(derivatives_available) "/data/derivatives_dir" else NULL
  blood_dir <- if(blood_available) "/data/blood_dir" else NULL
  
  return(list(
    bids_dir = bids_dir,
    derivatives_dir = derivatives_dir,
    blood_dir = blood_dir
  ))
}

# Load petfit app package
library(petfit)

# Detect available directories
dirs <- detect_mounted_directories()

cat("=== Directory Configuration ===\n")
if (!is.null(dirs$bids_dir)) {
  cat("Using BIDS directory:", dirs$bids_dir, "\n")
}
if (!is.null(dirs$derivatives_dir)) {
  cat("Using derivatives directory:", dirs$derivatives_dir, "\n")
} else if (!is.null(dirs$bids_dir)) {
  cat("Derivatives directory will default to:", file.path(dirs$bids_dir, "derivatives"), "\n")
}
if (!is.null(dirs$blood_dir)) {
  cat("Using blood directory:", dirs$blood_dir, "\n")
}
cat("\n")

# Execute based on mode
if (opt$mode == "interactive") {
  cat("=== Starting Interactive Mode ===\n")
  cat("Shiny app will be available at http://localhost:3838\n")
  cat("Container will exit when app is closed\n")
  cat("\n")
  
  # Launch apps interactively
  if (opt$func == "regiondef") {
    region_definition_app(
      bids_dir = dirs$bids_dir,
      derivatives_dir = dirs$derivatives_dir,
      petfit_output_foldername = opt$petfit_output_foldername
    )
  } else if (opt$func == "modelling_plasma") {
    modelling_plasma_app(
      bids_dir = dirs$bids_dir,
      derivatives_dir = dirs$derivatives_dir,
      blood_dir = dirs$blood_dir,
      subfolder = opt$analysis_foldername
    )
  } else if (opt$func == "modelling_ref") {
    modelling_ref_app(
      bids_dir = dirs$bids_dir,
      derivatives_dir = dirs$derivatives_dir,
      blood_dir = dirs$blood_dir,
      subfolder = opt$analysis_foldername
    )
  }
  
  cat("App closed. Container exiting.\n")
  
} else if (opt$mode == "automatic") {
  cat("=== Starting Automatic Mode ===\n")

  # Execute based on function type
  if (opt$func == "regiondef") {
    # Region definition automatic mode
    cat("Executing region definition pipeline...\n")

    tryCatch({
      result <- petfit_regiondef_auto(
        bids_dir = dirs$bids_dir,
        derivatives_dir = dirs$derivatives_dir,
        petfit_output_foldername = opt$petfit_output_foldername
      )

      # Print all messages
      for (msg in result$messages) {
        cat(msg, "\n")
      }

      if (result$success) {
        cat("\nRegion definition pipeline completed successfully.\n")
        quit(status = 0)
      } else {
        cat("\nRegion definition pipeline failed.\n")
        quit(status = 3)
      }

    }, error = function(e) {
      cat("Error executing region definition pipeline:", e$message, "\n")
      quit(status = 3)
    })

  } else {
    # Modelling automatic mode
    derivatives_path <- dirs$derivatives_dir %||% file.path(dirs$bids_dir, "derivatives")
    petfit_dir <- file.path(derivatives_path, opt$petfit_output_foldername)
    analysis_folder <- file.path(petfit_dir, opt$analysis_foldername)

    cat("Analysis folder:", analysis_folder, "\n")

    # Check if analysis folder exists
    if (!dir.exists(analysis_folder)) {
      cat("Error: Analysis folder does not exist:", analysis_folder, "\n")
      quit(status = 2)
    }

    # Execute the automatic pipeline
    tryCatch({
      result <- petfit_modelling_auto(
        analysis_subfolder = opt$analysis_foldername,
        bids_dir = dirs$bids_dir,
        derivatives_dir = dirs$derivatives_dir,
        petfit_output_foldername = opt$petfit_output_foldername,
        blood_dir = dirs$blood_dir,
        step = opt$step
      )

      # Print all messages
      for (msg in result$messages) {
        cat(msg, "\n")
      }

      if (result$success) {
        if (length(result$reports_generated) > 0) {
          cat("\nReports generated:\n")
          for (report in result$reports_generated) {
            cat("  -", report, "\n")
          }
        }
        cat("\nAutomatic pipeline completed successfully.\n")
        quit(status = 0)
      } else {
        cat("\nAutomatic pipeline failed.\n")
        quit(status = 3)
      }

    }, error = function(e) {
      cat("Error executing automatic pipeline:", e$message, "\n")
      quit(status = 3)
    })
  }
}

# Clean exit
quit(status = 0)