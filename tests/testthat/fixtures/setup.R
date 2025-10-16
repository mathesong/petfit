# Test setup helpers and utilities for petfit tests

library(testthat)
library(tibble)
library(dplyr)
library(readr)
library(jsonlite)

#' Create a temporary BIDS directory structure for testing
#'
#' @param base_dir Base directory to create the structure in
#' @param n_subjects Number of subjects to create (default: 2)
#' @param n_sessions Number of sessions per subject (default: 1)  
#' @return Path to the created BIDS directory
create_test_bids_structure <- function(base_dir = tempdir(), n_subjects = 2, n_sessions = 1) {
  
  bids_dir <- file.path(base_dir, "test_bids")
  
  # Create main BIDS directories
  dir.create(bids_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(bids_dir, "derivatives"), showWarnings = FALSE)
  dir.create(file.path(bids_dir, "derivatives", "petfit"), showWarnings = FALSE)
  dir.create(file.path(bids_dir, "code", "petfit"), recursive = TRUE, showWarnings = FALSE)
  
  # Create subjects
  for (sub in 1:n_subjects) {
    sub_id <- sprintf("sub-%02d", sub)
    
    for (ses in 1:n_sessions) {
      ses_id <- sprintf("ses-%02d", ses)
      
      # Create subject/session directory structure
      pet_dir <- file.path(bids_dir, sub_id, ses_id, "pet")
      dir.create(pet_dir, recursive = TRUE, showWarnings = FALSE)
      
      # Create empty PET files (replacing symbolic links)
      pet_file <- file.path(pet_dir, paste0(sub_id, "_", ses_id, "_trc-18FFDG_pet.nii.gz"))
      pet_json <- file.path(pet_dir, paste0(sub_id, "_", ses_id, "_trc-18FFDG_pet.json"))
      
      file.create(pet_file)
      
      # Create PET JSON sidecar with metadata
      pet_metadata <- list(
        InjectedRadioactivity = runif(1, 300000, 500000), # kBq
        InjectedRadioactivityUnits = "kBq",
        FrameTimesStart = c(0, 1, 2, 5, 10, 15, 20, 30, 45, 60, 90, 120),
        FrameDuration = c(1, 1, 3, 5, 5, 5, 10, 15, 15, 30, 30, 30)
      )
      write_json(pet_metadata, pet_json, auto_unbox = TRUE, pretty = TRUE)
      
      # Create derivatives structure for TACs and segmentations
      deriv_sub_ses <- file.path(bids_dir, "derivatives", "petfit", sub_id, ses_id)
      dir.create(deriv_sub_ses, recursive = TRUE, showWarnings = FALSE)
      
      # Create TACs file based on test data
      create_test_tacs_file(deriv_sub_ses, sub_id, ses_id)
      
      # Create morph file for segmentation volumes  
      create_test_morph_file(deriv_sub_ses, sub_id, ses_id)
      
      # Create blood data file (for some subjects)
      if (sub <= 1) { # Only first subject has blood data
        create_test_blood_file(deriv_sub_ses, sub_id, ses_id)
      }
    }
  }
  
  # Create participants.tsv
  participants <- tibble(
    participant_id = paste0("sub-", sprintf("%02d", 1:n_subjects)),
    age = c(25, 45),
    sex = c("M", "F"),
    weight = c(70, 65) # kg
  )
  write_tsv(participants, file.path(bids_dir, "participants.tsv"))
  
  # Create participants.json  
  participants_json <- list(
    age = list(Description = "Age of participant", Units = "years"),
    sex = list(Description = "Sex of participant", Levels = list(M = "Male", F = "Female")),
    weight = list(Description = "Weight of participant", Units = "kg")
  )
  write_json(participants_json, file.path(bids_dir, "participants.json"), auto_unbox = TRUE, pretty = TRUE)
  
  # Create petfit regions file
  create_test_petfit_regions(bids_dir)
  
  return(bids_dir)
}

#' Create test TACs file from the existing test data
create_test_tacs_file <- function(output_dir, sub_id, ses_id) {
  
  # Read the base test data
  test_data_path <- system.file("extdata", "test_tac_data.csv", package = "petfit")
  if (!file.exists(test_data_path)) {
    # Fallback to data directory
    test_data_path <- file.path(find.package("petfit"), "..", "data", "test_tac_data.csv")
  }
  
  if (file.exists(test_data_path)) {
    base_data <- read_csv(test_data_path, show_col_types = FALSE)
  } else {
    # Create basic data structure if file not found
    base_data <- tibble(
      time = c(0, 1, 2, 5, 10, 15, 20, 30, 45, 60, 90, 120),
      frontal = c(0, 100, 200, 180, 160, 145, 135, 125, 115, 105, 95, 85),
      temporal = c(0, 95, 190, 175, 155, 140, 130, 120, 110, 100, 90, 80),
      parietal = c(0, 85, 170, 155, 140, 125, 115, 105, 95, 85, 75, 65),
      blood = c(0, 150, 280, 220, 180, 150, 130, 110, 95, 85, 75, 70)
    )
  }
  
  # Convert to BIDS TACs format with frame timing
  frame_starts <- base_data$time
  frame_ends <- c(base_data$time[-1], base_data$time[length(base_data$time)] + 30)
  
  # Create long format with regions as rows
  regions <- c("Left-Cerebral-Cortex", "Right-Cerebral-Cortex", "Left-Hippocampus", "Right-Hippocampus")
  region_data <- c("frontal", "temporal", "parietal", "frontal") # Map to test data columns
  
  tacs_long <- tibble()
  
  for (i in seq_along(regions)) {
    region_tacs <- tibble(
      region = regions[i],
      frame_start = frame_starts,
      frame_end = frame_ends,
      frame_dur = frame_ends - frame_starts,
      frame_mid = frame_starts + (frame_ends - frame_starts) / 2,
      TAC = base_data[[region_data[i]]] * runif(1, 0.8, 1.2) # Add some variation
    )
    tacs_long <- bind_rows(tacs_long, region_tacs)
  }
  
  # Write TACs file
  tacs_file <- file.path(output_dir, paste0(sub_id, "_", ses_id, "_trc-18FFDG_desc-freesurfer_tacs.tsv"))
  write_tsv(tacs_long, tacs_file)
}

#' Create test morph file with region volumes
create_test_morph_file <- function(output_dir, sub_id, ses_id) {
  
  regions <- c("Left-Cerebral-Cortex", "Right-Cerebral-Cortex", "Left-Hippocampus", "Right-Hippocampus")
  volumes <- c(50000, 52000, 4200, 4000) # mm³
  
  morph_data <- tibble(
    name = regions,
    `volume-mm3` = volumes
  )
  
  morph_file <- file.path(output_dir, paste0(sub_id, "_", ses_id, "_trc-18FFDG_desc-freesurfer_morph.tsv"))
  write_tsv(morph_data, morph_file)
}

#' Create test blood data file
create_test_blood_file <- function(output_dir, sub_id, ses_id) {
  
  # Use blood column from test data
  test_data_path <- system.file("extdata", "test_tac_data.csv", package = "petfit")
  if (!file.exists(test_data_path)) {
    test_data_path <- file.path(find.package("petfit"), "..", "data", "test_tac_data.csv")
  }
  
  if (file.exists(test_data_path)) {
    base_data <- read_csv(test_data_path, show_col_types = FALSE)
    blood_activity <- base_data$blood
    time_points <- base_data$time
  } else {
    time_points <- c(0, 1, 2, 5, 10, 15, 20, 30, 45, 60, 90, 120)
    blood_activity <- c(0, 150, 280, 220, 180, 150, 130, 110, 95, 85, 75, 70)
  }
  
  blood_data <- tibble(
    time = time_points,
    activity = blood_activity,
    counts = blood_activity * runif(length(blood_activity), 0.9, 1.1)
  )
  
  blood_file <- file.path(output_dir, paste0(sub_id, "_", ses_id, "_trc-18FFDG_blood.tsv"))
  write_tsv(blood_data, blood_file)
}

#' Create test petfit regions file
create_test_petfit_regions <- function(bids_dir) {
  
  regions_data <- tibble(
    name = c("Cortex", "Hippocampus"),
    constituent_regions = c(
      "Left-Cerebral-Cortex;Right-Cerebral-Cortex",
      "Left-Hippocampus;Right-Hippocampus"
    )
  )
  
  regions_file <- file.path(bids_dir, "code", "petfit", "petfit_regions.tsv")
  write_tsv(regions_data, regions_file)
}

#' Cleanup test directories
cleanup_test_dirs <- function(dirs) {
  for (dir in dirs) {
    if (dir.exists(dir)) {
      unlink(dir, recursive = TRUE)
    }
  }
}

#' Create sample configuration files for testing
create_sample_configs <- function(config_dir) {
  
  # Basic 1TCM configuration
  config_1tcm <- list(
    DataSubset = list(
      sub = c("01", "02"),
      ses = c("01"),
      trc = c("18FFDG"),
      rec = "",
      task = "",
      run = "",
      desc = "freesurfer",
      regions = c("Cortex", "Hippocampus")
    ),
    Weights = list(
      region_type = "mean_combined",
      region = "",
      external_tacs = "",
      radioisotope = "F18",
      halflife = "",
      method = "2",
      custom_formula = "",
      minweight = 0.25
    ),
    FitDelay = list(
      blood_source = "1",
      model = "1tcm_median",
      time_window = 5,
      regions = "",
      multiple_regions = "",
      vB_value = 0.05,
      fit_vB = TRUE,
      use_weights = TRUE,
      inpshift_lower = -0.5,
      inpshift_upper = 0.5
    ),
    Model1 = list(
      model_type = "1TCM",
      K1_lower = 0.001,
      K1_upper = 1,
      K1_start = 0.1,
      k2_lower = 0.001,
      k2_upper = 1,
      k2_start = 0.1,
      vB_lower = 0,
      vB_upper = 0.1,
      vB_start = 0.05,
      fit_vB = TRUE,
      use_weights = TRUE
    ),
    Model2 = list(model_type = "No Model"),
    Model3 = list(model_type = "No Model")
  )
  
  # Basic 2TCM configuration
  config_2tcm <- config_1tcm
  config_2tcm$Model1 <- list(
    model_type = "2TCM",
    K1_lower = 0.001,
    K1_upper = 1,
    K1_start = 0.1,
    k2_lower = 0.001,
    k2_upper = 1,
    k2_start = 0.1,
    k3_lower = 0.001,
    k3_upper = 1,
    k3_start = 0.1,
    k4_lower = 0.001,
    k4_upper = 1,
    k4_start = 0.1,
    vB_lower = 0,
    vB_upper = 0.1,
    vB_start = 0.05,
    fit_vB = TRUE,
    use_weights = TRUE
  )
  
  # Configuration without blood data
  config_no_blood <- config_1tcm
  config_no_blood$FitDelay$model <- "Set to zero (i.e. no delay fitting to be performed)"
  
  # Write configuration files
  write_json(config_1tcm, file.path(config_dir, "config_1tcm.json"), auto_unbox = TRUE, pretty = TRUE)
  write_json(config_2tcm, file.path(config_dir, "config_2tcm.json"), auto_unbox = TRUE, pretty = TRUE)
  write_json(config_no_blood, file.path(config_dir, "config_no_blood.json"), auto_unbox = TRUE, pretty = TRUE)
}
