# Interactive Tests for launch_petfit_apps() function
# 
# These tests launch actual Shiny applications and require manual verification
# DO NOT run these in automated test environments or CI/CD pipelines
#
# To run these tests manually:
# source("tests/interactive/test-launch_petfit_apps_interactive.R")

library(petfit)

# Load test setup helpers
if (file.exists("tests/testthat/fixtures/setup.R")) {
  source("tests/testthat/fixtures/setup.R")
} else if (file.exists("testthat/fixtures/setup.R")) {
  source("testthat/fixtures/setup.R")
} else {
  stop("Cannot find setup.R file. Run from package root directory.")
}

# Helper function to create test BIDS structure
create_interactive_test_data <- function() {
  temp_dir <- tempdir()
  cat("Creating test BIDS structure in:", temp_dir, "\n")
  
  bids_dir <- create_test_bids_structure(temp_dir, n_subjects = 2, n_sessions = 1)
  
  cat("✓ Test BIDS structure created at:", bids_dir, "\n")
  cat("✓ Participants: sub-01, sub-02\n")
  cat("✓ Sessions: ses-01\n")
  cat("✓ Test data includes TACs, blood data, and participant info\n")
  
  return(bids_dir)
}

# Test 1: Region Definition App Only
test_region_definition_app <- function() {
  cat("\n=== INTERACTIVE TEST: Region Definition App ===\n")
  
  bids_dir <- create_interactive_test_data()
  
  cat("Launching region definition app...\n")
  cat("- A browser window should open with the petfit region definition interface\n")
  cat("- Verify the app loads without errors\n")
  cat("- Check that BIDS data is detected correctly\n")
  cat("- MANUALLY CLOSE the browser window when done testing\n")
  cat("- Press [Enter] in R console to continue after testing\n\n")
  
  tryCatch({
    launch_petfit_apps(
      bids_dir = bids_dir,
      region_definition = TRUE,
      modelling = FALSE
    )
    cat("✓ Region definition app launched successfully\n")
  }, error = function(e) {
    cat("✗ Error launching region definition app:", e$message, "\n")
  })
  
  cat("Press [Enter] to continue...")
  readline()
  
  # Cleanup
  cleanup_test_dirs(bids_dir)
  cat("✓ Test data cleaned up\n")
}

# Test 2: Modelling App Only  
test_modelling_app <- function() {
  cat("\n=== INTERACTIVE TEST: Modelling App ===\n")
  
  bids_dir <- create_interactive_test_data()
  
  cat("Launching modelling app...\n")
  cat("- A browser window should open with the petfit modelling interface\n")
  cat("- Verify the app loads without errors\n") 
  cat("- Check that configuration options are available\n")
  cat("- Test blood data detection (should find blood data for sub-01)\n")
  cat("- MANUALLY CLOSE the browser window when done testing\n")
  cat("- Press [Enter] in R console to continue after testing\n\n")
  
  tryCatch({
    launch_petfit_apps(
      bids_dir = bids_dir,
      region_definition = FALSE,
      modelling = TRUE
    )
    cat("✓ Modelling app launched successfully\n")
  }, error = function(e) {
    cat("✗ Error launching modelling app:", e$message, "\n")
  })
  
  cat("Press [Enter] to continue...")
  readline()
  
  # Cleanup
  cleanup_test_dirs(bids_dir)
  cat("✓ Test data cleaned up\n")
}

# Test 3: Both Apps Sequential
test_both_apps_sequential <- function() {
  cat("\n=== INTERACTIVE TEST: Both Apps Sequential ===\n")
  
  bids_dir <- create_interactive_test_data()
  
  cat("Launching both apps sequentially (region definition first, then modelling)...\n")
  cat("- First: Region definition app should open\n")
  cat("- Complete region definition or close the app\n") 
  cat("- Then: Modelling app should open automatically\n")
  cat("- Verify both apps launch in correct sequence\n")
  cat("- MANUALLY CLOSE browser windows when done testing\n")
  cat("- Press [Enter] in R console to continue after testing\n\n")
  
  tryCatch({
    launch_petfit_apps(
      bids_dir = bids_dir,
      region_definition = TRUE,
      modelling = TRUE
    )
    cat("✓ Both apps launched successfully in sequence\n")
  }, error = function(e) {
    cat("✗ Error launching sequential apps:", e$message, "\n")
  })
  
  cat("Press [Enter] to continue...")
  readline()
  
  # Cleanup
  cleanup_test_dirs(bids_dir)
  cat("✓ Test data cleaned up\n")
}

# Test 4: App with Custom Parameters
test_custom_parameters <- function() {
  cat("\n=== INTERACTIVE TEST: Custom Parameters ===\n")
  
  bids_dir <- create_interactive_test_data()
  
  # Create custom blood directory
  blood_dir <- file.path(tempdir(), "custom_blood")
  dir.create(blood_dir, showWarnings = FALSE)
  
  # Copy blood data to custom location
  blood_file <- file.path(blood_dir, "custom_blood_data.tsv")
  blood_data <- tibble::tibble(
    time = c(0, 1, 2, 5, 10),
    activity = c(0, 150, 280, 220, 180)
  )
  readr::write_tsv(blood_data, blood_file)
  
  cat("Testing with custom parameters:\n")
  cat("- BIDS dir:", bids_dir, "\n")
  cat("- Blood dir:", blood_dir, "\n")
  cat("- Subfolder: Custom_Analysis\n")
  cat("- The modelling app should detect custom blood directory\n")
  cat("- Verify custom subfolder is used for analysis outputs\n\n")
  
  tryCatch({
    launch_petfit_apps(
      bids_dir = bids_dir,
      blood_dir = blood_dir,
      subfolder = "Custom_Analysis",
      region_definition = FALSE,
      modelling = TRUE
    )
    cat("✓ App launched with custom parameters\n")
  }, error = function(e) {
    cat("✗ Error launching app with custom parameters:", e$message, "\n")
  })
  
  cat("Press [Enter] to continue...")
  readline()
  
  # Cleanup
  cleanup_test_dirs(bids_dir)
  unlink(blood_dir, recursive = TRUE)
  cat("✓ Test data and custom directories cleaned up\n")
}

# Test 5: Error Handling
test_error_conditions <- function() {
  cat("\n=== INTERACTIVE TEST: Error Conditions ===\n")
  
  cat("Testing error conditions (these should fail gracefully):\n\n")
  
  # Test 1: Non-existent directory
  cat("1. Testing with non-existent BIDS directory...\n")
  tryCatch({
    launch_petfit_apps(
      bids_dir = "/this/path/does/not/exist",
      region_definition = TRUE,
      modelling = FALSE
    )
    cat("✗ Unexpected success - should have failed\n")
  }, error = function(e) {
    cat("✓ Correctly failed with error:", e$message, "\n")
  })
  
  # Test 2: No apps enabled
  cat("\n2. Testing with no apps enabled...\n")
  bids_dir <- create_interactive_test_data()
  
  tryCatch({
    launch_petfit_apps(
      bids_dir = bids_dir,
      region_definition = FALSE,
      modelling = FALSE
    )
    cat("✗ Unexpected success - should have failed\n")
  }, error = function(e) {
    cat("✓ Correctly failed with error:", e$message, "\n")
  })
  
  cleanup_test_dirs(bids_dir)
  cat("✓ Error condition testing complete\n")
}

# Main interactive test runner
run_all_interactive_tests <- function() {
  cat("╔════════════════════════════════════════════════════════════════╗\n")
  cat("║                    KINFITR INTERACTIVE TESTS                  ║\n")
  cat("║                                                                ║\n")
  cat("║  These tests will launch Shiny applications in your browser   ║\n")
  cat("║  Please interact with each app to verify functionality        ║\n")
  cat("║  MANUALLY CLOSE browser windows between tests                 ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n\n")
  
  cat("Available tests:\n")
  cat("1. Region Definition App Only\n")
  cat("2. Modelling App Only\n") 
  cat("3. Both Apps Sequential\n")
  cat("4. Custom Parameters\n")
  cat("5. Error Conditions\n")
  cat("6. Docker Functions\n")
  cat("7. Run All Tests\n")
  cat("0. Exit\n\n")
  
  repeat {
    choice <- readline("Select test to run (1-7, 0 to exit): ")
    
    switch(choice,
           "1" = test_region_definition_app(),
           "2" = test_modelling_app(),
           "3" = test_both_apps_sequential(), 
           "4" = test_custom_parameters(),
           "5" = test_error_conditions(),
           "6" = test_docker_functions(),
           "7" = {
             test_region_definition_app()
             test_modelling_app()
             test_both_apps_sequential()
             test_custom_parameters()
             test_error_conditions()
             test_docker_functions()
             cat("\n✓ All interactive tests completed!\n")
           },
           "0" = {
             cat("Exiting interactive tests.\n")
             break
           },
           cat("Invalid choice. Please select 1-7 or 0 to exit.\n")
    )
    
    cat("\n" %_% rep("─", 60) %_% "\n\n")
  }
}

# Convenience functions for quick testing
quick_test_region_app <- function() {
  bids_dir <- create_interactive_test_data()
  launch_petfit_apps(bids_dir = bids_dir, region_definition = TRUE, modelling = FALSE)
  cleanup_test_dirs(bids_dir)
}

quick_test_modelling_app <- function() {
  bids_dir <- create_interactive_test_data()  
  launch_petfit_apps(bids_dir = bids_dir, region_definition = FALSE, modelling = TRUE)
  cleanup_test_dirs(bids_dir)
}

# Test 6: Docker Function Validation
test_docker_functions <- function() {
  cat("\n=== INTERACTIVE TEST: Docker Functions ===\n")
  
  source(here::here("tests/testthat/fixtures/setup.R"))
  
  # Create test environment
  temp_dir <- tempdir()
  bids_dir <- create_test_bids_structure(temp_dir, n_subjects = 1, n_sessions = 1)
  
  cat("Testing Docker validation functions:\n")
  cat("- validate_directory_requirements()\n")
  cat("- validate_blood_requirements()\n")
  cat("- petfit_modelling_auto()\n\n")
  
  # Test 1: Directory validation
  cat("1. Testing directory validation...\n")
  tryCatch({
    result <- validate_directory_requirements("modelling", "interactive", bids_dir, NULL)
    if (result$valid) {
      cat("✓ Directory validation passed\n")
    } else {
      cat("✗ Directory validation failed:", paste(result$messages, collapse = "; "), "\n")
    }
  }, error = function(e) {
    cat("✗ Error in directory validation:", e$message, "\n")
  })
  
  # Test 2: Blood requirements validation
  cat("2. Testing blood requirements validation...\n")
  config <- list(
    FitDelay = list(model = "1tcm_median"),
    Model1 = list(model_type = "1TCM")
  )
  
  tryCatch({
    result <- validate_blood_requirements(config)
    if (result$required) {
      cat("✓ Blood requirements correctly detected\n")
    } else {
      cat("✗ Blood requirements not detected\n")
    }
  }, error = function(e) {
    cat("✗ Error in blood validation:", e$message, "\n")
  })
  
  # Test 3: Pipeline validation (expected to fail without proper setup)
  cat("3. Testing pipeline validation (expected to fail gracefully)...\n")
  analysis_folder <- file.path(bids_dir, "derivatives", "petfit", "Primary_Analysis")
  dir.create(analysis_folder, recursive = TRUE, showWarnings = FALSE)
  
  config_file <- file.path(analysis_folder, "desc-petfitoptions_config.json")
  jsonlite::write_json(config, config_file, auto_unbox = TRUE, pretty = TRUE)
  
  tryCatch({
    result <- petfit_modelling_auto(analysis_folder, bids_dir = bids_dir)
    cat("✗ Unexpected success - should have failed\n")
  }, error = function(e) {
    cat("✓ Pipeline validation correctly failed:", e$message, "\n")
  })
  
  cat("✓ Docker function testing complete\n")
  
  # Cleanup
  cleanup_test_dirs(bids_dir)
  cat("✓ Test data cleaned up\n")
}

# Auto-run if sourced directly
if (interactive()) {
  cat("Interactive tests loaded!\n")
  cat("Run: run_all_interactive_tests() for the full test menu\n")
  cat("Or run individual tests like: test_region_definition_app()\n\n")
  
  cat("Quick test functions:\n")
  cat("- quick_test_region_app()\n")
  cat("- quick_test_modelling_app()\n")
  cat("- test_docker_functions()\n\n")
} else {
  cat("Interactive tests loaded but not run (non-interactive session)\n")
}
