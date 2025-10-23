#' Minify Derivatives Directory for Debugging
#'
#' Creates a lightweight copy of a derivatives directory by replacing files
#' larger than 1MB with empty files, then zips the result. Useful for creating
#' shareable directory structures for debugging without large data files.
#'
#' @param derivatives_dir Character string. Path to the derivatives directory
#'   to minify.
#' @param output_zip Character string. Path for the output zip file. Defaults
#'   to "mini_derivatives.zip" in the current working directory.
#' @param size_threshold Numeric. File size threshold in MB above which files
#'   will be replaced with empty files. Default is 1 MB.
#'
#' @return Invisibly returns the path to the created zip file.
#'
#' @details
#' This function:
#' \itemize{
#'   \item Creates a temporary copy of the derivatives directory structure
#'   \item Identifies all files larger than the size threshold (default 1MB)
#'   \item Replaces large files with empty files of the same name
#'   \item Creates a zip archive of the minified directory
#'   \item Cleans up temporary files
#' }
#'
#' The resulting zip file preserves the complete directory structure and all
#' file names, making it useful for debugging configuration and file detection
#' issues without transferring large data files.
#'
#' @examples
#' \dontrun{
#' # Create minified version of derivatives directory
#' minify_derivatives_dir("/path/to/derivatives")
#'
#' # Custom output location and size threshold
#' minify_derivatives_dir(
#'   derivatives_dir = "/path/to/derivatives",
#'   output_zip = "~/debug_derivatives.zip",
#'   size_threshold = 0.5  # 500KB threshold
#' )
#' }
#'
#' @export
minify_derivatives_dir <- function(derivatives_dir,
                                   output_zip = "mini_derivatives.zip",
                                   size_threshold = 1) {

  # Validate inputs
  if (!dir.exists(derivatives_dir)) {
    stop("derivatives_dir does not exist: ", derivatives_dir)
  }

  derivatives_dir <- normalizePath(derivatives_dir)
  size_threshold_bytes <- size_threshold * 1024 * 1024

  message("Starting minification of: ", derivatives_dir)
  message("Size threshold: ", size_threshold, " MB")

  # Create temporary directory for the minified copy
  temp_dir <- tempfile("minify_")
  dir.create(temp_dir)
  on.exit(unlink(temp_dir, recursive = TRUE), add = TRUE)

  # Copy directory structure
  temp_copy <- file.path(temp_dir, basename(derivatives_dir))
  message("Creating temporary copy...")
  dir.create(temp_copy, recursive = TRUE)

  # Get all files in the derivatives directory
  all_files <- list.files(
    derivatives_dir,
    full.names = TRUE,
    recursive = TRUE,
    include.dirs = FALSE,
    all.files = TRUE
  )

  if (length(all_files) == 0) {
    warning("No files found in derivatives_dir")
    return(invisible(NULL))
  }

  message("Found ", length(all_files), " files to process")

  # Process each file
  files_replaced <- 0
  files_copied <- 0

  for (file_path in all_files) {
    # Calculate relative path
    rel_path <- sub(paste0("^", derivatives_dir, "/?"), "", file_path)
    dest_path <- file.path(temp_copy, rel_path)

    # Create parent directory if needed
    dest_dir <- dirname(dest_path)
    if (!dir.exists(dest_dir)) {
      dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
    }

    # Check file size
    file_size <- file.info(file_path)$size

    if (is.na(file_size)) {
      warning("Could not determine size for: ", file_path)
      next
    }

    if (file_size > size_threshold_bytes) {
      # Create empty file
      file.create(dest_path)
      files_replaced <- files_replaced + 1
    } else {
      # Copy small file as-is
      file.copy(file_path, dest_path, overwrite = TRUE)
      files_copied <- files_copied + 1
    }
  }

  message("Files replaced with empty files: ", files_replaced)
  message("Files copied unchanged: ", files_copied)

  # Create zip archive
  message("Creating zip archive: ", output_zip)

  # Change to temp directory to zip from there
  current_wd <- getwd()
  on.exit(setwd(current_wd), add = TRUE)
  setwd(temp_dir)

  # Remove existing zip if present
  if (file.exists(output_zip)) {
    file.remove(output_zip)
  }

  # Create zip
  zip_result <- utils::zip(
    zipfile = output_zip,
    files = basename(temp_copy),
    flags = "-r9Xq"
  )

  if (zip_result != 0) {
    stop("Failed to create zip archive")
  }

  # Move zip to original working directory if needed
  final_zip_path <- file.path(current_wd, basename(output_zip))
  if (normalizePath(output_zip, mustWork = FALSE) != normalizePath(final_zip_path, mustWork = FALSE)) {
    file.copy(output_zip, final_zip_path, overwrite = TRUE)
  }

  message("Successfully created minified archive: ", final_zip_path)
  message("Original size: ", format(sum(file.info(all_files)$size, na.rm = TRUE) / 1024^2, digits = 2), " MB")
  message("Minified size: ", format(file.info(final_zip_path)$size / 1024^2, digits = 2), " MB")

  invisible(final_zip_path)
}
