#' Determine Blood Data Source
#'
#' @description Decide which blood data source to use when blood_dir is not specified
#'
#' @param analysis_folder Character string path to analysis folder
#' @param bids_dir Character string path to BIDS directory (optional)
#' 
#' @return Character string indicating which source to use: "analysis_folder", "bids_dir", or "none"
#' @export
determine_blood_source <- function(analysis_folder, bids_dir = NULL) {
  
  # Check for inputfunction files in analysis folder
  has_analysis_blood <- length(list.files(analysis_folder, pattern = "*_inputfunction\\.tsv$", recursive = TRUE)) > 0
  
  if (has_analysis_blood) {
    return("analysis_folder")
  }
  
  # Check for raw blood data in BIDS directory if provided
  has_bids_blood <- if (!is.null(bids_dir) && dir.exists(bids_dir)) {
    length(list.files(bids_dir, pattern = "_blood\\.tsv$", recursive = TRUE)) > 0
  } else {
    FALSE
  }
  
  if (has_bids_blood) {
    return("bids_dir")
  }
  
  return("none")
}

#' Save inputfunction.tsv data from a blooddata object
#'
#' @description Save inputfunction data as TSV file with accompanying JSON metadata
#'
#' @param blooddata Blooddata object containing the blood data structure
#' @param filename Character string full path for output file (with or without .tsv extension)
#' 
#' @details This function saves inputfunction data in the same way as bloodstream does:
#' - Creates interpolated input function using bd_create_input()
#' - TSV file with time, whole_blood_radioactivity, plasma_radioactivity, 
#'   metabolite_parent_fraction, and AIF columns
#' - JSON sidecar with column descriptions and units following BIDS conventions
#' - If filename contains .tsv, it removes it to create the file stem
#' - Saves both .tsv and .json files using the same stem
#' 
#' @return Invisibly returns the paths of created files
#' @export
blooddata2inputfunction_tsv <- function(blooddata, filename) {
  
  # Remove .tsv extension if present to get file stem
  file_stem <- str_remove(filename, "\\.tsv$")
  
  # Create output filenames
  tsv_file <- paste0(file_stem, ".tsv")
  json_file <- paste0(file_stem, ".json")
  
  # Ensure output directory exists
  dir.create(dirname(tsv_file), recursive = TRUE, showWarnings = FALSE)
  
  # Create input function data
  input_data <- kinfitr::bd_create_input(blooddata)
  
  blood_unit  <- blooddata$Data$Blood$Discrete$activity$Units
  plasma_unit <- blooddata$Data$Plasma$activity$Units
  
  blood_unit  <- str_remove(blood_unit, "/\\w*")
  plasma_unit <- str_remove(plasma_unit, "/\\w*")
  
  # Prepare data with proper column names and units
  output_data <- input_data %>%
    rename(
      "time" = Time,
      "whole_blood_radioactivity" = Blood,
      "plasma_radioactivity" = Plasma,
      "metabolite_parent_fraction" = ParentFraction,
      AIF = AIF
    ) %>%
    # Convert units: min to sec, kBq to Bq
    mutate(
      time = time * 60,  # min to sec
      whole_blood_radioactivity = kinfitr::unit_convert(whole_blood_radioactivity, 
                                                       from_units = blood_unit, 
                                                       to_units = "Bq"),
      plasma_radioactivity = kinfitr::unit_convert(plasma_radioactivity, plasma_unit, "Bq"),
      AIF = kinfitr::unit_convert(AIF, blood_unit, "Bq")
    )
  
  # Create JSON metadata following bloodstream format
  json_metadata <- list(
    time = list(
      Description = "Interpolated time in relation to time zero defined in _pet.json",
      Units = "s"
    ),
    whole_blood_radioactivity = list(
      Description = "Estimated interpolated radioactivity in whole blood samples",
      Units = "Bq"
    ),
    plasma_radioactivity = list(
      Description = "Estimated interpolated radioactivity in whole plasma samples", 
      Units = "Bq"
    ),
    metabolite_parent_fraction = list(
      Description = "Parent fraction of the radiotracer in arterial plasma samples"
    ),
    AIF = list(
      Description = "Estimated interpolated radioactivity in metabolite-corrected arterial plasma samples",
      Units = "Bq"
    )
  )
  
  # Write TSV file
  readr::write_tsv(output_data, tsv_file)
  
  # Write JSON file
  jsonlite::write_json(json_metadata, json_file, pretty = TRUE, auto_unbox = TRUE)
}

#' Summarise Blood Data Availability
#'
#' @description Provide a status summary of available blood data sources and priority selection.
#'
#' @param analysis_folder Character string path to the current analysis folder (for *_inputfunction.tsv files)
#' @param bids_dir Character string path to the BIDS directory (optional, for raw *_blood.tsv files)
#' @param blood_dir Character string path to an explicit blood data directory (optional)
#'
#' @return A list containing logical flags (`has_analysis_blood`, `has_bids_blood`, `has_blood_dir`)
#'   and the selected `priority_source` ("blood_dir", "analysis_folder", "bids_dir", or "none")
#' @export
get_blood_data_status <- function(analysis_folder, bids_dir = NULL, blood_dir = NULL) {

  # Helper to count files safely
  count_files <- function(path, pattern) {
    if (is.null(path) || !dir.exists(path)) {
      return(0L)
    }
    length(list.files(path, pattern = pattern, recursive = TRUE))
  }

  has_blood_dir <- count_files(blood_dir, "\\.tsv$") > 0
  has_analysis_blood <- count_files(analysis_folder, "(inputfunction|blood)\\.tsv$") > 0
  has_bids_blood <- count_files(bids_dir, "_blood\\.tsv$") > 0

  priority_source <- if (has_blood_dir) {
    "blood_dir"
  } else {
    determine_blood_source(analysis_folder, bids_dir)
  }

  list(
    has_analysis_blood = has_analysis_blood,
    has_bids_blood = has_bids_blood,
    has_blood_dir = has_blood_dir,
    priority_source = priority_source
  )
}
