# Integration test helpers for petfit
#
# Provides dataset management, workspace isolation, and skip functions
# for integration tests using real OpenNeuro data (ds004869).
#
# Integration tests are disabled by default. Enable with environment variables:
#   PETFIT_INTEGRATION_TESTS=true  -- R-native integration tests
#   PETFIT_DOCKER_TESTS=true       -- Docker container tests
#   PETFIT_SINGULARITY_TESTS=true  -- Apptainer/Singularity tests
#
# Test data source (in priority order):
#   1. PETFIT_TESTDATA_PATH env var (explicit path to .tar.gz)
#   2. Local file: tests/testthat/fixtures/integration/ds004869_testdata.tar.gz
#   3. GitHub Release download (R-native HTTP, then gh CLI fallback)

# GitHub repo for release downloads
PETFIT_GH_REPO <- "mathesong/petfit"
PETFIT_TESTDATA_RELEASE_TAG <- "testdata-v1.0"
PETFIT_TESTDATA_FILENAME <- "ds004869_testdata.tar.gz"

# ---------------------------------------------------------------------------
# Skip functions
# ---------------------------------------------------------------------------

#' Skip test if integration tests are not enabled
skip_if_no_integration <- function() {
  testthat::skip_if(
    Sys.getenv("PETFIT_INTEGRATION_TESTS") == "",
    "Integration tests disabled. Set PETFIT_INTEGRATION_TESTS=true to enable."
  )
}

#' Skip test if Docker tests are not enabled or Docker is not available
skip_if_no_docker <- function() {
  skip_if_no_integration()
  testthat::skip_if(
    Sys.getenv("PETFIT_DOCKER_TESTS") == "",
    "Docker tests disabled. Set PETFIT_DOCKER_TESTS=true to enable."
  )
  testthat::skip_if_not(
    nchar(Sys.which("docker")) > 0,
    "Docker not available on this system"
  )
}

#' Skip test if Singularity/Apptainer tests are not enabled or not available
skip_if_no_singularity <- function() {
  skip_if_no_integration()
  testthat::skip_if(
    Sys.getenv("PETFIT_SINGULARITY_TESTS") == "",
    "Singularity tests disabled. Set PETFIT_SINGULARITY_TESTS=true to enable."
  )
  testthat::skip_if_not(
    nchar(Sys.which("singularity")) > 0 || nchar(Sys.which("apptainer")) > 0,
    "Singularity/Apptainer not available on this system"
  )
}

# ---------------------------------------------------------------------------
# Test data management
# ---------------------------------------------------------------------------

#' Get the integration cache directory
#'
#' Returns PETFIT_INTEGRATION_CACHE env var if set, otherwise tempdir-based path.
#' The cache persists across test files within a session (or across sessions if
#' PETFIT_INTEGRATION_CACHE points to a persistent directory).
get_integration_cache_dir <- function() {
  cache_dir <- Sys.getenv("PETFIT_INTEGRATION_CACHE", unset = "")
  if (cache_dir == "") {
    cache_dir <- file.path(tempdir(), "petfit_integration")
  }
  if (!dir.exists(cache_dir)) {
    dir.create(cache_dir, recursive = TRUE)
  }
  cache_dir
}

#' Find the test data tarball
#'
#' Searches for the tarball in priority order:
#' 1. PETFIT_TESTDATA_PATH env var
#' 2. Local fixtures directory (included in the git repo)
#' 3. GitHub Release download (R-native HTTP, then gh CLI fallback)
#'
#' In most cases, the tarball is found at priority 2 since it's committed to
#' the repository. The download fallback exists for edge cases where someone
#' has a partial clone or the file was removed locally.
#'
#' @return Path to tarball, or NULL if not found
find_testdata_tarball <- function() {
  # Priority 1: Explicit path from env var
  explicit_path <- Sys.getenv("PETFIT_TESTDATA_PATH", unset = "")
  if (explicit_path != "" && file.exists(explicit_path)) {
    return(explicit_path)
  }

  # Priority 2: Local file in fixtures (the normal case for cloned repos)
  local_path <- testthat::test_path("fixtures", "integration", PETFIT_TESTDATA_FILENAME)
  if (file.exists(local_path)) {
    return(local_path)
  }

  # Priority 3: Download from GitHub Release (fallback)
  cache_dir <- get_integration_cache_dir()
  cached_tarball <- file.path(cache_dir, PETFIT_TESTDATA_FILENAME)

  if (file.exists(cached_tarball)) {
    return(cached_tarball)
  }

  # 3a: R-native HTTP download (no external tools needed)
  download_url <- sprintf(
    "https://github.com/%s/releases/download/%s/%s",
    PETFIT_GH_REPO, PETFIT_TESTDATA_RELEASE_TAG, PETFIT_TESTDATA_FILENAME
  )
  tryCatch({
    message("Test data not found locally. Downloading from GitHub Release...")
    utils::download.file(download_url, cached_tarball, mode = "wb", quiet = FALSE)
    if (file.exists(cached_tarball)) {
      message("Downloaded test data to: ", cached_tarball)
      return(cached_tarball)
    }
  }, error = function(e) {
    message("R download failed: ", conditionMessage(e))
    if (file.exists(cached_tarball)) file.remove(cached_tarball)
  })

  # 3b: gh CLI fallback
  if (nchar(Sys.which("gh")) > 0) {
    message("Trying gh CLI download...")
    result <- system2(
      "gh", c(
        "release", "download", PETFIT_TESTDATA_RELEASE_TAG,
        "--repo", PETFIT_GH_REPO,
        "--pattern", PETFIT_TESTDATA_FILENAME,
        "--dir", cache_dir
      ),
      stdout = TRUE, stderr = TRUE
    )
    exit_code <- attr(result, "status") %||% 0L
    if (exit_code == 0L && file.exists(cached_tarball)) {
      message("Downloaded test data to: ", cached_tarball)
      return(cached_tarball)
    }
    warning("gh CLI download failed: ", paste(result, collapse = "\n"))
  }

  # No tarball found
  NULL
}

#' Ensure test data is extracted and ready
#'
#' Extracts the ds004869 tarball once per session and returns the dataset path.
#' If the tarball cannot be found, the test is skipped.
#'
#' @return Path to the extracted ds004869 directory
ensure_testdata <- function() {
  cache_dir <- get_integration_cache_dir()
  dataset_dir <- file.path(cache_dir, "ds004869")
  sentinel <- file.path(cache_dir, ".ds004869_ready")

  # Already extracted in this session

  if (file.exists(sentinel) && dir.exists(dataset_dir)) {
    return(dataset_dir)
  }

  # Find the tarball
  tarball <- find_testdata_tarball()
  if (is.null(tarball)) {
    testthat::skip(paste0(
      "Test data tarball not found. Provide it via one of:\n",
      "  1. PETFIT_TESTDATA_PATH=/path/to/ds004869_testdata.tar.gz\n",
      "  2. Place at tests/testthat/fixtures/integration/ds004869_testdata.tar.gz\n",
      "  3. Upload to GitHub Release '", PETFIT_TESTDATA_RELEASE_TAG, "' (requires gh CLI)"
    ))
  }

  # Extract tarball
  if (dir.exists(dataset_dir)) {
    unlink(dataset_dir, recursive = TRUE)
  }

  message("Extracting test data from: ", tarball)
  result <- utils::untar(tarball, exdir = cache_dir)
  if (result != 0 || !dir.exists(dataset_dir)) {
    testthat::skip("Failed to extract test data tarball")
  }

  # Write sentinel
  writeLines(format(Sys.time()), sentinel)
  message("Test data ready at: ", dataset_dir)

  dataset_dir
}

# ---------------------------------------------------------------------------
# Workspace management
# ---------------------------------------------------------------------------

#' Create an isolated writable workspace for integration tests
#'
#' Creates a temporary workspace with:
#' - A writable derivatives directory
#' - A symlink to the petprep derivatives (read-only source data)
#' - The bids_dir pointing to the extracted dataset (read-only)
#'
#' @param dataset_dir Path to the extracted ds004869 directory
#' @return List with bids_dir, derivatives_dir, and workspace paths
create_integration_workspace <- function(dataset_dir) {
  cache_dir <- get_integration_cache_dir()
  workspace <- tempfile(pattern = "petfit_ws_", tmpdir = cache_dir)
  dir.create(workspace, recursive = TRUE)

  derivatives_dir <- file.path(workspace, "derivatives")
  dir.create(derivatives_dir, recursive = TRUE)

  # Symlink petprep derivatives into workspace
  petprep_source <- file.path(dataset_dir, "derivatives", "petprep")
  petprep_link <- file.path(derivatives_dir, "petprep")
  if (dir.exists(petprep_source)) {
    file.symlink(normalizePath(petprep_source), petprep_link)
  }

  list(
    bids_dir = dataset_dir,
    derivatives_dir = derivatives_dir,
    workspace = workspace
  )
}

#' Clean up an integration workspace
#'
#' @param workspace_info List returned by create_integration_workspace()
cleanup_workspace <- function(workspace_info) {
  if (!is.null(workspace_info$workspace) && dir.exists(workspace_info$workspace)) {
    unlink(workspace_info$workspace, recursive = TRUE)
  }
}

# ---------------------------------------------------------------------------
# Config helpers
# ---------------------------------------------------------------------------

#' Set up region definition config in the workspace
#'
#' Copies the ds004869_petfit_regions.tsv fixture into the appropriate location
#' within the workspace derivatives directory.
#'
#' @param workspace_info List returned by create_integration_workspace()
#' @return Path to the installed petfit_regions.tsv file
setup_regiondef_config <- function(workspace_info) {
  # Create petfit directory in workspace derivatives
  petfit_dir <- file.path(workspace_info$derivatives_dir, "petfit")
  if (!dir.exists(petfit_dir)) {
    dir.create(petfit_dir, recursive = TRUE)
  }

  # Copy fixture file
  fixture_file <- testthat::test_path("fixtures", "integration", "ds004869_petfit_regions.tsv")
  dest_file <- file.path(petfit_dir, "petfit_regions.tsv")
  file.copy(fixture_file, dest_file, overwrite = TRUE)

  dest_file
}

#' Set up modelling config in the workspace
#'
#' Copies a JSON config fixture into the analysis folder within the workspace.
#'
#' @param workspace_info List returned by create_integration_workspace()
#' @param config_fixture_name Name of the JSON config fixture file
#'   (e.g., "ds004869_plasma_config.json")
#' @param analysis_subfolder Name for the analysis subfolder (default: "Primary_Analysis")
#' @return Path to the installed config file
setup_modelling_config <- function(workspace_info, config_fixture_name,
                                   analysis_subfolder = "Primary_Analysis") {
  # Create analysis directory
  analysis_dir <- file.path(workspace_info$derivatives_dir, "petfit", analysis_subfolder)
  if (!dir.exists(analysis_dir)) {
    dir.create(analysis_dir, recursive = TRUE)
  }

  # Copy fixture file
  fixture_file <- testthat::test_path("fixtures", "integration", config_fixture_name)
  dest_file <- file.path(analysis_dir, "desc-petfitoptions_config.json")
  file.copy(fixture_file, dest_file, overwrite = TRUE)

  dest_file
}

# ---------------------------------------------------------------------------
# Container runners (for Docker/Singularity tests)
# ---------------------------------------------------------------------------

#' Run petfit Docker container
#'
#' @param func Character: "regiondef", "modelling_plasma", or "modelling_ref"
#' @param mode Character: "interactive" or "automatic"
#' @param workspace_info List returned by create_integration_workspace()
#' @param blood_dir Optional path to blood data directory
#' @param step Optional step name for automatic mode
#' @param image Docker image name (default: "mathesong/petfit:latest")
#' @param analysis_foldername Analysis subfolder name (default: "Primary_Analysis")
#' @return List with output (character vector) and exit_code (integer)
run_petfit_docker <- function(func, mode, workspace_info,
                              blood_dir = NULL, step = NULL,
                              image = "mathesong/petfit:latest",
                              analysis_foldername = "Primary_Analysis",
                              cores = 1L) {
  # Build volume mounts
  volumes <- c(
    paste0(workspace_info$bids_dir, ":/data/bids_dir:ro"),
    paste0(workspace_info$derivatives_dir, ":/data/derivatives_dir")
  )
  if (!is.null(blood_dir)) {
    volumes <- c(volumes, paste0(blood_dir, ":/data/blood_dir:ro"))
  }

  # Build docker args
  docker_args <- c(
    "run", "--rm",
    "--user", paste0(as.integer(system("id -u", intern = TRUE)), ":",
                     as.integer(system("id -g", intern = TRUE)))
  )
  for (v in volumes) {
    docker_args <- c(docker_args, "-v", v)
  }
  docker_args <- c(docker_args, image, "--func", func, "--mode", mode)
  docker_args <- c(docker_args, "--analysis_foldername", analysis_foldername)
  if (!is.null(step)) {
    docker_args <- c(docker_args, "--step", step)
  }
  if (cores > 1L) {
    docker_args <- c(docker_args, "--cores", as.character(cores))
  }

  result <- system2("docker", docker_args, stdout = TRUE, stderr = TRUE)
  exit_code <- attr(result, "status") %||% 0L

  list(
    output = result,
    exit_code = exit_code
  )
}

#' Run petfit Singularity/Apptainer container
#'
#' @param func Character: "regiondef", "modelling_plasma", or "modelling_ref"
#' @param mode Character: "interactive" or "automatic"
#' @param workspace_info List returned by create_integration_workspace()
#' @param container Path to SIF file or Docker reference
#' @param blood_dir Optional path to blood data directory
#' @param step Optional step name for automatic mode
#' @param analysis_foldername Analysis subfolder name (default: "Primary_Analysis")
#' @return List with output (character vector) and exit_code (integer)
run_petfit_singularity <- function(func, mode, workspace_info,
                                   container = "petfit_latest.sif",
                                   blood_dir = NULL, step = NULL,
                                   analysis_foldername = "Primary_Analysis",
                                   cores = 1L) {
  # Detect whether to use singularity or apptainer command
  cmd <- if (nchar(Sys.which("apptainer")) > 0) "apptainer" else "singularity"

  # Build bind mounts
  binds <- c(
    paste0(workspace_info$bids_dir, ":/data/bids_dir:ro"),
    paste0(workspace_info$derivatives_dir, ":/data/derivatives_dir")
  )
  if (!is.null(blood_dir)) {
    binds <- c(binds, paste0(blood_dir, ":/data/blood_dir:ro"))
  }

  # Build command args
  cmd_args <- c("run")
  for (b in binds) {
    cmd_args <- c(cmd_args, "--bind", b)
  }
  cmd_args <- c(cmd_args, container,
                "--func", func, "--mode", mode,
                "--analysis_foldername", analysis_foldername)
  if (!is.null(step)) {
    cmd_args <- c(cmd_args, "--step", step)
  }
  if (cores > 1L) {
    cmd_args <- c(cmd_args, "--cores", as.character(cores))
  }

  result <- system2(cmd, cmd_args, stdout = TRUE, stderr = TRUE)
  exit_code <- attr(result, "status") %||% 0L

  list(
    output = result,
    exit_code = exit_code
  )
}

# ---------------------------------------------------------------------------
# Docker container helpers
# ---------------------------------------------------------------------------

DOCKER_IMAGE <- "mathesong/petfit:latest"

#' Ensure Docker image is available (build or pull if needed)
ensure_docker_image <- function() {
  # Optionally rebuild the image from source
  if (Sys.getenv("PETFIT_DOCKER_BUILD") == "true") {
    pkg_root <- testthat::test_path("..", "..")
    build_result <- system2(
      "docker",
      c("build", "-t", DOCKER_IMAGE, "-f", "docker/Dockerfile", "."),
      stdout = TRUE, stderr = TRUE,
      env = paste0("DOCKER_BUILDKIT=1")
    )
    exit_code <- attr(build_result, "status") %||% 0L
    if (exit_code != 0L) {
      testthat::skip(paste("Docker build failed:", paste(build_result, collapse = "\n")))
    }
  }

  # Verify image exists
  check <- system2("docker", c("image", "inspect", DOCKER_IMAGE),
                    stdout = FALSE, stderr = FALSE)
  if (check != 0L) {
    testthat::skip(paste("Docker image not available:", DOCKER_IMAGE,
                         "\nPull with: docker pull", DOCKER_IMAGE,
                         "\nOr set PETFIT_DOCKER_BUILD=true to build from source"))
  }
}

#' Set up workspace for Docker tests (resolves symlinks)
setup_docker_workspace <- function() {
  dataset_dir <- ensure_testdata()
  ws <- create_integration_workspace(dataset_dir)

  # Docker needs real paths, not symlinks -- resolve the petprep symlink
  petprep_link <- file.path(ws$derivatives_dir, "petprep")
  if (file.exists(petprep_link) && Sys.readlink(petprep_link) != "") {
    real_path <- normalizePath(petprep_link)
    unlink(petprep_link)
    system2("cp", c("-a", real_path, petprep_link))
  }

  ws
}

# ---------------------------------------------------------------------------
# Singularity/Apptainer container helpers
# ---------------------------------------------------------------------------

#' Locate singularity/apptainer command
get_singularity_cmd <- function() {
  if (nchar(Sys.which("apptainer")) > 0) return("apptainer")
  if (nchar(Sys.which("singularity")) > 0) return("singularity")
  NULL
}

#' Find or build Singularity container image
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
    return("docker-daemon://mathesong/petfit:latest")
  }

  NULL
}

#' Set up workspace for Singularity tests (resolves symlinks)
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
