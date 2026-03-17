# Integration tests: Singularity/Apptainer container
#
# Tests petfit Singularity container in automatic mode using real ds004869 data.
# Also validates shell scripts and definition file without requiring a container.
#
# Container tests require: PETFIT_INTEGRATION_TESTS=true, PETFIT_SINGULARITY_TESTS=true,
#   and either singularity or apptainer CLI available.
#
# Script validation tests run with just PETFIT_INTEGRATION_TESTS=true (no container needed).

# ---------------------------------------------------------------------------
# Helper: locate singularity/apptainer command
# ---------------------------------------------------------------------------

get_singularity_cmd <- function() {
  if (nchar(Sys.which("apptainer")) > 0) return("apptainer")
  if (nchar(Sys.which("singularity")) > 0) return("singularity")
  NULL
}

# ---------------------------------------------------------------------------
# Helper: find or build container image
# ---------------------------------------------------------------------------

find_singularity_container <- function() {
  # Check for explicit path
  sif_path <- Sys.getenv("PETFIT_SINGULARITY_SIF", unset = "")
  if (sif_path != "" && file.exists(sif_path)) {
    return(sif_path)
  }

  # Check for a SIF in the singularity/ directory
  pkg_root <- testthat::test_path("..", "..")
  sif_candidates <- list.files(
    file.path(pkg_root, "singularity"),
    pattern = "\\.sif$",
    full.names = TRUE
  )
  if (length(sif_candidates) > 0) {
    return(sif_candidates[1])
  }

  # Try docker-daemon reference if Docker image exists
  docker_check <- system2("docker", c("image", "inspect", "mathesong/petfit:latest"),
                          stdout = FALSE, stderr = FALSE)
  if (docker_check == 0L) {
    return("docker-daemon:mathesong/petfit:latest")
  }

  NULL
}

# ---------------------------------------------------------------------------
# Helper: set up workspace (same as Docker -- resolve symlinks)
# ---------------------------------------------------------------------------

setup_singularity_workspace <- function() {
  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)

  # Singularity needs real paths for bind mounts
  petprep_link <- file.path(ws$derivatives_dir, "petprep")
  if (file.exists(petprep_link) && Sys.readlink(petprep_link) != "") {
    real_path <- normalizePath(petprep_link)
    unlink(petprep_link)
    system2("cp", c("-a", real_path, petprep_link))
  }

  ws
}

# ---------------------------------------------------------------------------
# Script validation (no container needed)
# ---------------------------------------------------------------------------

test_that("Singularity shell scripts are executable", {
  skip_if_no_integration()

  pkg_root <- testthat::test_path("..", "..")
  singularity_dir <- file.path(pkg_root, "singularity")

  scripts <- c("build.sh", "run-interactive.sh", "run-automatic.sh",
               "run-regiondef.sh", "test-basic.sh")

  for (script in scripts) {
    script_path <- file.path(singularity_dir, script)
    expect_true(file.exists(script_path),
                info = paste("Script should exist:", script))

    # Check executable permission
    file_info <- file.info(script_path)
    expect_true(as.integer(file_info$mode) %% 2 == 1 ||
                  bitwAnd(as.integer(file_info$mode), 0x49) > 0,
                info = paste("Script should be executable:", script))
  }
})

test_that("Singularity definition file has required sections", {
  skip_if_no_integration()

  pkg_root <- testthat::test_path("..", "..")
  def_file <- file.path(pkg_root, "singularity", "petfit.def")

  expect_true(file.exists(def_file), info = "petfit.def should exist")

  def_content <- readLines(def_file)
  def_text <- paste(def_content, collapse = "\n")

  expect_true(grepl("Bootstrap:\\s*docker", def_text),
              info = "Definition should have Docker bootstrap")
  expect_true(grepl("From:\\s*rocker/shiny-verse", def_text),
              info = "Definition should use rocker/shiny-verse base")
  expect_true(grepl("%runscript", def_text),
              info = "Definition should have a runscript section")
  expect_true(grepl("%post", def_text),
              info = "Definition should have a post section")
  expect_true(grepl("kinfitr", def_text),
              info = "Definition should install kinfitr")
})

test_that("Singularity run-automatic.sh validates arguments", {
  skip_if_no_integration()

  pkg_root <- testthat::test_path("..", "..")
  script <- file.path(pkg_root, "singularity", "run-automatic.sh")

  # Should fail with invalid step
  result <- suppressWarnings(
    system2("bash", c(script, "--derivatives-dir", "/tmp", "--step", "invalid"),
            stdout = TRUE, stderr = TRUE)
  )
  exit_code <- attr(result, "status") %||% 0L
  expect_true(exit_code != 0L, info = "Should reject invalid step")

  # Should fail with missing func
  result2 <- suppressWarnings(
    system2("bash", c(script, "--derivatives-dir", "/tmp"),
            stdout = TRUE, stderr = TRUE)
  )
  exit_code2 <- attr(result2, "status") %||% 0L
  expect_true(exit_code2 != 0L, info = "Should require --func argument")
})

test_that("Singularity run-interactive.sh validates arguments", {
  skip_if_no_integration()

  pkg_root <- testthat::test_path("..", "..")
  script <- file.path(pkg_root, "singularity", "run-interactive.sh")

  # Should fail with invalid function
  result <- suppressWarnings(
    system2("bash", c(script, "--func", "invalid", "--bids-dir", "/tmp"),
            stdout = TRUE, stderr = TRUE)
  )
  exit_code <- attr(result, "status") %||% 0L
  expect_true(exit_code != 0L, info = "Should reject invalid function")

  # Should fail with no directories
  result2 <- suppressWarnings(
    system2("bash", c(script, "--func", "regiondef"),
            stdout = TRUE, stderr = TRUE)
  )
  exit_code2 <- attr(result2, "status") %||% 0L
  expect_true(exit_code2 != 0L, info = "Should require at least one directory")
})

# ---------------------------------------------------------------------------
# Container tests: regiondef automatic mode
# ---------------------------------------------------------------------------

test_that("Singularity: regiondef automatic mode produces combined TACs", {
  skip_if_no_singularity()

  container <- find_singularity_container()
  if (is.null(container)) {
    testthat::skip(paste(
      "No Singularity container found. Provide via one of:",
      "  1. PETFIT_SINGULARITY_SIF=/path/to/petfit.sif",
      "  2. Place .sif file in singularity/ directory",
      "  3. Have Docker image mathesong/petfit:latest available",
      sep = "\n"
    ))
  }

  ws <- setup_singularity_workspace()
  withr::defer(cleanup_workspace(ws))
  setup_regiondef_config(ws)

  result <- run_petfit_singularity(
    func = "regiondef",
    mode = "automatic",
    workspace_info = ws,
    container = container
  )

  expect_equal(result$exit_code, 0L,
               info = paste("Singularity regiondef failed:",
                            paste(result$output, collapse = "\n")))

  # Verify output files were created
  petfit_dir <- file.path(ws$derivatives_dir, "petfit")
  combined_tacs <- file.path(petfit_dir, "desc-combinedregions_tacs.tsv")
  expect_true(file.exists(combined_tacs),
              info = "Combined TACs file should be created")
})

# ---------------------------------------------------------------------------
# Container tests: modelling pipelines
# ---------------------------------------------------------------------------

test_that("Singularity: plasma modelling full pipeline succeeds", {
  skip_if_no_singularity()

  container <- find_singularity_container()
  if (is.null(container)) {
    testthat::skip("No Singularity container available")
  }

  ws <- setup_singularity_workspace()
  withr::defer(cleanup_workspace(ws))
  setup_regiondef_config(ws)

  # Run regiondef first
  regiondef_result <- run_petfit_singularity(
    func = "regiondef",
    mode = "automatic",
    workspace_info = ws,
    container = container
  )
  if (regiondef_result$exit_code != 0L) {
    testthat::skip("Singularity regiondef prerequisite failed")
  }

  # Install plasma config
  setup_modelling_config(ws, "ds004869_plasma_config.json")

  # Run full plasma pipeline
  result <- run_petfit_singularity(
    func = "modelling_plasma",
    mode = "automatic",
    workspace_info = ws,
    container = container
  )

  expect_equal(result$exit_code, 0L,
               info = paste("Singularity plasma pipeline failed:",
                            paste(result$output, collapse = "\n")))

  # Verify reports
  analysis_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  reports_dir <- file.path(analysis_dir, "reports")
  expect_true(dir.exists(reports_dir), info = "Reports directory should exist")
})

test_that("Singularity: reference tissue modelling full pipeline succeeds", {
  skip_if_no_singularity()

  container <- find_singularity_container()
  if (is.null(container)) {
    testthat::skip("No Singularity container available")
  }

  ws <- setup_singularity_workspace()
  withr::defer(cleanup_workspace(ws))
  setup_regiondef_config(ws)

  # Run regiondef first
  regiondef_result <- run_petfit_singularity(
    func = "regiondef",
    mode = "automatic",
    workspace_info = ws,
    container = container
  )
  if (regiondef_result$exit_code != 0L) {
    testthat::skip("Singularity regiondef prerequisite failed")
  }

  # Install ref config
  setup_modelling_config(ws, "ds004869_ref_config.json")

  # Run full reference tissue pipeline
  result <- run_petfit_singularity(
    func = "modelling_ref",
    mode = "automatic",
    workspace_info = ws,
    container = container
  )

  expect_equal(result$exit_code, 0L,
               info = paste("Singularity reference pipeline failed:",
                            paste(result$output, collapse = "\n")))

  # Verify reports
  analysis_dir <- file.path(ws$derivatives_dir, "petfit", "Primary_Analysis")
  reports_dir <- file.path(analysis_dir, "reports")
  expect_true(dir.exists(reports_dir), info = "Reports directory should exist")
})
