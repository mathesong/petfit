#' Generate Step Report
#'
#' @description Generate a parameterised report for a specific analysis step
#'
#' @param step_name Character string name of the step ("data_definition", "weights", "delay", "reference_tac")
#' @param analysis_folder Character string path to the analysis folder
#' @param output_dir Character string path to output directory (default: analysis_folder/reports)
#' @param bids_dir Character string path to the BIDS directory (optional)
#' @param blood_dir Character string path to the blood data directory (optional)
#' @param cores Integer number of cores for parallel processing (default: 1)
#' @param save_logs Logical whether to save subprocess output to log files (default: FALSE)
#'
#' @return Character string path to the generated report file
#' @export
generate_step_report <- function(step_name, analysis_folder, output_dir = NULL, bids_dir = NULL, blood_dir = NULL, cores = 1L, save_logs = FALSE) {

  # Set default output directory
  if (is.null(output_dir)) {
    output_dir <- file.path(analysis_folder, "reports")
  }

  # Create reports directory if it doesn't exist
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    cat("Created reports directory:", output_dir, "\n")
  }

  # Get template file path
  template_file <- system.file("rmd", paste0(step_name, "_report.Rmd"),
                              package = "petfit")

  if (!file.exists(template_file)) {
    stop("Report template not found: ", paste0(step_name, "_report.Rmd"))
  }

  # Set output file path
  output_file <- file.path(output_dir, paste0(step_name, "_report.html"))

  # Prepare parameters - reports are now self-deriving
  params <- list(
    cores = cores,
    analysis_folder = analysis_folder,
    bids_dir = bids_dir,
    blood_dir = blood_dir
  )

  # Set up logging if requested
  log_file <- NULL
  if (save_logs) {
    log_dir <- file.path(analysis_folder, "reports", "logs")
    if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)
    log_file <- file.path(log_dir, paste0(step_name, "_report.log"))
  }

  # Generate report in a subprocess so future::supportsMulticore() returns TRUE
  # (Shiny disables multicore forking, but callr::r() escapes that context)
  tryCatch({
    callr::r(
      function(input, output_file, params, output_dir) {
        library(petfit)
        rmarkdown::render(
          input = input,
          output_file = output_file,
          params = params,
          envir = new.env(),
          quiet = TRUE,
          intermediates_dir = output_dir
        )
      },
      args = list(
        input = template_file,
        output_file = output_file,
        params = params,
        output_dir = output_dir
      ),
      stdout = log_file %||% "",
      stderr = log_file %||% ""
    )

    cat("Generated report:", output_file, "\n")
    return(output_file)

  }, error = function(e) {
    # Extract actual error from callr subprocess
    actual_msg <- if (!is.null(e$parent)) e$parent$message else e$message
    warning("Failed to generate ", step_name, " report: ", actual_msg)
    return(NULL)
  })
}

#' Generate Model Report
#'
#' @description Generate a parameterised report for a specific kinetic model
#'
#' @param model_type Character string type of model ("1TCM", "2TCM", "Logan", "Fit Delay")
#' @param model_number Character string model number ("Model 1", "Model 2", "Model 3")
#' @param analysis_folder Character string path to the analysis folder
#' @param output_dir Character string path to output directory (default: analysis_folder/reports)
#' @param bids_dir Character string path to the BIDS directory (optional)
#' @param blood_dir Character string path to the blood data directory (optional)
#' @param cores Integer number of cores for parallel processing (default: 1)
#' @param ancillary_path Character string path to ancillary analysis folder (optional)
#' @param save_logs Logical whether to save subprocess output to log files (default: FALSE)
#'
#' @return Character string path to the generated report file
#' @export
generate_model_report <- function(model_type, model_number, analysis_folder,
                                 output_dir = NULL, bids_dir = NULL, blood_dir = NULL, cores = 1L,
                                 ancillary_path = NULL, save_logs = FALSE) {

  # Set default output directory
  if (is.null(output_dir)) {
    output_dir <- file.path(analysis_folder, "reports")
  }

  # Create reports directory if it doesn't exist
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    cat("Created reports directory:", output_dir, "\n")
  }

  # Get template name based on model type
  template_name <- get_model_template(model_type)

  # Get template file path
  template_file <- system.file("rmd", template_name, package = "petfit")

  if (!file.exists(template_file)) {
    stop("Report template not found: ", template_name)
  }

  # Set output file path (always model1_report.html, model2_report.html, etc.)
  model_num <- tolower(gsub(" ", "", model_number))  # "Model 1" -> "model1"
  output_file <- file.path(output_dir, paste0(model_num, "_report.html"))

  # Prepare parameters
  params <- list(
    cores = cores,
    model_number = model_number,
    analysis_folder = analysis_folder,
    bids_dir = bids_dir,
    blood_dir = blood_dir
  )

  # Only include ancillary_path for templates that declare it (k2prime consumers)
  k2prime_models <- c("MRTM2", "SRTM2", "refLogan")
  if (model_type %in% k2prime_models) {
    params$ancillary_path <- ancillary_path
  }

  # Set up logging if requested
  log_file <- NULL
  if (save_logs) {
    log_dir <- file.path(analysis_folder, "reports", "logs")
    if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)
    log_file <- file.path(log_dir, paste0(model_num, "_report.log"))
  }

  # Generate report in a subprocess so future::supportsMulticore() returns TRUE
  # (Shiny disables multicore forking, but callr::r() escapes that context)
  tryCatch({
    callr::r(
      function(input, output_file, params, output_dir) {
        library(petfit)
        rmarkdown::render(
          input = input,
          output_file = output_file,
          params = params,
          envir = new.env(),
          quiet = TRUE,
          intermediates_dir = output_dir
        )
      },
      args = list(
        input = template_file,
        output_file = output_file,
        params = params,
        output_dir = output_dir
      ),
      stdout = log_file %||% "",
      stderr = log_file %||% ""
    )

    cat("Generated report:", output_file, "\n")
    return(output_file)

  }, error = function(e) {
    # Extract actual error from callr subprocess
    actual_msg <- if (!is.null(e$parent)) e$parent$message else e$message
    warning("Failed to generate ", model_type, " report for ", model_number, ": ", actual_msg)
    return(NULL)
  })
}

#' Get Model Template Name
#'
#' @description Map model type to corresponding template filename
#'
#' @param model_type Character string type of model
#'
#' @return Character string template filename
get_model_template <- function(model_type) {

  if (is.null(model_type) || length(model_type) == 0) {
    stop("Model type must be provided (received NULL)")
  }

  template_map <- list(
    "1TCM" = "1tcm_report.Rmd",
    "2TCM" = "2tcm_report.Rmd",
    "2TCM_irr" = "2tcmirr_report.Rmd",
    "Logan" = "logan_report.Rmd",
    "MA1" = "ma1_report.Rmd",
    "Patlak" = "patlak_report.Rmd",
    "Fit Delay" = "fit_delay_report.Rmd",
    "SRTM" = "srtm_report.Rmd",
    "SRTM2" = "srtm2_report.Rmd",
    "refLogan" = "reflogan_report.Rmd",
    "MRTM1" = "mrtm1_report.Rmd",
    "MRTM2" = "mrtm2_report.Rmd"
  )

  template_name <- template_map[[model_type]]

  if (is.null(template_name)) {
    stop("Unknown model type: ", model_type,
         ". Supported types: ", paste(names(template_map), collapse = ", "))
  }

  return(template_name)
}

#' Generate t* Finder Report
#'
#' @description Generate a parameterised report for t* finder analysis
#'
#' @param analysis_folder Character string path to the analysis folder
#' @param tstar_results List containing t* finder results
#' @param binding_regions List containing binding region classifications
#' @param output_dir Character string path to output directory (default: analysis_folder/reports)
#' @param cores Integer number of cores for parallel processing (default: 1)
#' @param save_logs Logical whether to save subprocess output to log files (default: FALSE)
#'
#' @return Character string path to the generated report file
#' @export
generate_tstar_report <- function(analysis_folder, tstar_results = NULL, binding_regions = NULL,
                                 output_dir = NULL, cores = 1L, save_logs = FALSE) {

  # Set default output directory
  if (is.null(output_dir)) {
    output_dir <- file.path(analysis_folder, "reports")
  }

  # Create reports directory if it doesn't exist
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    cat("Created reports directory:", output_dir, "\n")
  }

  # Get template file path
  template_file <- system.file("rmd", "tstar_finder_report.Rmd", package = "petfit")

  if (!file.exists(template_file)) {
    stop("Report template not found: tstar_finder_report.Rmd")
  }

  # Set output file path
  output_file <- file.path(output_dir, "tstar_finder_report.html")

  # Prepare parameters
  params <- list(
    cores = cores,
    analysis_folder = analysis_folder,
    tstar_results = tstar_results,
    binding_regions = binding_regions
  )

  # Set up logging if requested
  log_file <- NULL
  if (save_logs) {
    log_dir <- file.path(analysis_folder, "reports", "logs")
    if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)
    log_file <- file.path(log_dir, "tstar_finder_report.log")
  }

  # Generate report in a subprocess so future::supportsMulticore() returns TRUE
  # (Shiny disables multicore forking, but callr::r() escapes that context)
  tryCatch({
    callr::r(
      function(input, output_file, params, output_dir) {
        library(petfit)
        rmarkdown::render(
          input = input,
          output_file = output_file,
          params = params,
          envir = new.env(),
          quiet = TRUE,
          intermediates_dir = output_dir
        )
      },
      args = list(
        input = template_file,
        output_file = output_file,
        params = params,
        output_dir = output_dir
      ),
      stdout = log_file %||% "",
      stderr = log_file %||% ""
    )

    cat("Generated report:", output_file, "\n")
    return(output_file)

  }, error = function(e) {
    # Extract actual error from callr subprocess
    actual_msg <- if (!is.null(e$parent)) e$parent$message else e$message
    warning("Failed to generate t* finder report: ", actual_msg)
    return(NULL)
  })
}

#' Generate All Reports Summary
#'
#' @description Generate a summary report linking to all generated analysis reports
#'
#' @param analysis_folder Character string path to the analysis folder
#' @param output_dir Character string path to output directory (default: analysis_folder/reports)
#'
#' @return Character string path to the generated summary report file
#' @export
generate_reports_summary <- function(analysis_folder, output_dir = NULL) {

  # Set default output directory
  if (is.null(output_dir)) {
    output_dir <- file.path(analysis_folder, "reports")
  }

  # Find all generated reports
  report_files <- list.files(output_dir, pattern = "*.html", full.names = FALSE)

  if (length(report_files) == 0) {
    cat("No reports found to summarize.\n")
    return(NULL)
  }

  # Create summary HTML content
  summary_content <- paste0(
    "<h1>petfit Analysis Reports Summary</h1>\n",
    "<p><strong>Analysis folder:</strong> ", basename(analysis_folder), "</p>\n",
    "<p><strong>Generated on:</strong> ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "</p>\n",
    "<h2>Available Reports</h2>\n",
    "<ul>\n"
  )

  # Add links to each report
  for (report_file in sort(report_files)) {
    if (report_file != "reports_summary.html") {  # Don't include self-reference
      report_title <- gsub("_", " ", gsub("\\.html$", "", report_file))
      report_title <- tools::toTitleCase(report_title)
      summary_content <- paste0(summary_content,
                               '<li><a href="', report_file, '">', report_title, '</a></li>\n')
    }
  }

  summary_content <- paste0(summary_content, "</ul>\n")

  # Write summary file
  summary_file <- file.path(output_dir, "reports_summary.html")
  writeLines(summary_content, summary_file)

  cat("Generated reports summary:", summary_file, "\n")
  return(summary_file)
}
