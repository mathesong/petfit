#' Launch petfit Apps
#'
#' @description Launch a specified petfit application
#'
#' @param app Character string specifying which app to launch: "regiondef", "modelling_plasma", or "modelling_ref" (required)
#' @param bids_dir Character string path to the BIDS directory (default: NULL)
#' @param derivatives_dir Character string path to derivatives directory (default: bids_dir/derivatives if bids_dir provided)
#' @param blood_dir Character string path to the blood data directory (default: NULL, for modelling_plasma app)
#' @param petfit_output_foldername Character string name for the petfit output folder within derivatives (default: "petfit")
#' @param subfolder Character string name for analysis subfolder (default: "Primary_Analysis", for modelling apps)
#' @param config_file Character string path to existing config file (optional, for modelling apps)
#'
#' @details
#' This function provides a unified interface to launch petfit applications built on kinfitr:
#' - "regiondef": Region Definition App for creating brain region definitions and generating combined TACs
#' - "modelling_plasma": Plasma Input Modelling App for invasive kinetic models (1TCM, 2TCM, Logan, MA1)
#' - "modelling_ref": Reference Tissue Modelling App for non-invasive kinetic models (SRTM, refLogan, MRTM1, MRTM2)
#'
#' Parameter usage:
#' - regiondef: Uses bids_dir, derivatives_dir, petfit_output_foldername
#' - modelling_plasma: Uses bids_dir, derivatives_dir, blood_dir, subfolder, config_file
#' - modelling_ref: Uses bids_dir, derivatives_dir, subfolder, config_file
#'
#' @examples
#' \dontrun{
#' # Launch region definition app
#' launch_petfit_apps(app = "regiondef", bids_dir = "/path/to/bids")
#'
#' # Launch plasma input modelling app
#' launch_petfit_apps(app = "modelling_plasma", bids_dir = "/path/to/bids")
#'
#' # Launch reference tissue modelling app
#' launch_petfit_apps(app = "modelling_ref", bids_dir = "/path/to/bids")
#' }
#'
#' @export
launch_petfit_apps <- function(app = c("regiondef", "modelling_plasma", "modelling_ref"),
                               bids_dir = NULL,
                               derivatives_dir = NULL,
                               blood_dir = NULL,
                               petfit_output_foldername = "petfit",
                               subfolder = "Primary_Analysis",
                               config_file = NULL) {

  # Validate app parameter
  app <- match.arg(app, choices = c("regiondef", "modelling_plasma", "modelling_ref"))
  
  # Print configuration
  cat("=== Launching petfit app:", app, "===\n")
  if (!is.null(bids_dir)) {
    cat("  BIDS directory:", bids_dir, "\n")
  }
  if (!is.null(derivatives_dir)) {
    cat("  Derivatives directory:", derivatives_dir, "\n")
  } else if (!is.null(bids_dir)) {
    cat("  Derivatives directory:", file.path(bids_dir, "derivatives"), "(default)\n")
  }
  if (!is.null(blood_dir)) {
    cat("  Blood directory:", blood_dir, "\n")
  }
  if (app == "regiondef") {
    cat("  petfit output folder:", petfit_output_foldername, "\n")
  } else {
    cat("  Analysis subfolder:", subfolder, "\n")
    if (!is.null(config_file)) {
      cat("  Config file:", config_file, "\n")
    }
  }
  cat("\n")

  # Launch the specified app
  switch(app,
    regiondef = {
      region_definition_app(
        bids_dir = bids_dir,
        derivatives_dir = derivatives_dir,
        petfit_output_foldername = petfit_output_foldername
      )
    },
    modelling_plasma = {
      modelling_plasma_app(
        bids_dir = bids_dir,
        derivatives_dir = derivatives_dir,
        blood_dir = blood_dir,
        subfolder = subfolder,
        config_file = config_file
      )
    },
    modelling_ref = {
      modelling_ref_app(
        bids_dir = bids_dir,
        derivatives_dir = derivatives_dir,
        blood_dir = blood_dir,
        subfolder = subfolder,
        config_file = config_file
      )
    }
  )

  cat("App closed.\n")
}
