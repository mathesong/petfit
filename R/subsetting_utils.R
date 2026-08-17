#' Parse Semicolon-Separated Values
#'
#' @description Parse a semicolon-separated subsetting string into a vector of
#'   values.
#'
#'   Values are separated by `;` and **may not contain commas**. A comma is
#'   always a mistyped separator, and silently treating `"A, B"` as one value is
#'   what caused analyses to run on fewer regions than were asked for.
#'
#'   A string whose first non-whitespace character is `-` selects everything
#'   *except* the values listed, so `"-test;retest"` means "neither test nor
#'   retest". The `-` applies to the whole field, so including and excluding
#'   cannot be mixed within a single field. Each subsetting field reads its own
#'   prefix independently.
#'
#' @param input_string Character string with semicolon-separated values
#' @param field Optional name of the field being parsed, used to make error and
#'   warning messages specific (e.g. `"Regions"`).
#' @return Character vector of parsed values, or `NULL` if empty. The result
#'   carries a `negate` attribute — `TRUE` when the field was prefixed with `-`,
#'   otherwise `FALSE`. Read it with `attr(x, "negate")`.
#' @export
parse_semicolon_values <- function(input_string, field = NULL) {
  if (is.null(input_string) || length(input_string) == 0) {
    return(NULL)
  }

  input_string <- stringr::str_trim(as.character(input_string)[1])

  if (is.na(input_string) || input_string == "") {
    return(NULL)
  }

  # A leading "-" negates the whole field, not just the first value
  negate <- stringr::str_starts(input_string, stringr::fixed("-"))
  if (negate) {
    input_string <- stringr::str_sub(input_string, 2)
  }

  # Split by semicolon and trim whitespace
  values <- stringr::str_split(input_string, ";")[[1]]
  values <- stringr::str_trim(values)

  # Remove empty values
  values <- values[values != ""]

  if (length(values) == 0) {
    if (negate) {
      warning(subset_field_prefix(field),
              "\"-\" on its own excludes nothing; no filter applied.",
              call. = FALSE)
    }
    return(NULL)
  }

  check_no_commas(values, field)

  attr(values, "negate") <- negate

  return(values)
}

#' Subset Combined TACs Data
#'
#' @description Filter combined TACs data based on subsetting criteria.
#'
#'   Every value is validated first — see [validate_subset_params()]. A value
#'   you asked to include that matches nothing is an error rather than a silent
#'   no-op.
#'
#'   A field parsed from a string prefixed with `-` (see
#'   [parse_semicolon_values()]) excludes its values instead of including them.
#'   Note the asymmetry around missing entities: including `ses = "test"` drops
#'   rows whose session is `NA`, whereas excluding `ses = "-test"` **keeps**
#'   them, since a measurement with no session at all is indeed not `ses-test`.
#'
#' @param combined_tacs_data Tibble with combined TACs data
#' @param subset_params List of subsetting parameters
#' @return Filtered tibble
#' @export
subset_combined_tacs <- function(combined_tacs_data, subset_params) {

  if (is.null(combined_tacs_data) || nrow(combined_tacs_data) == 0) {
    return(tibble::tibble())
  }

  validate_subset_params(combined_tacs_data, subset_params)

  filtered_data <- combined_tacs_data

  # Apply filters for each parameter
  for (field in names(subset_field_columns)) {
    values <- subset_params[[field]]
    if (is.null(values) || length(values) == 0) {
      next
    }

    column <- subset_field_columns[[field]]
    if (!column %in% colnames(filtered_data)) {
      # Only reachable for an exclusion; an inclusion has already errored.
      next
    }

    # as.character() on both sides mirrors what %in% does anyway, and base
    # subsetting keeps NA rows under negation rather than dropping them the way
    # dplyr::filter() would.
    keep <- as.character(filtered_data[[column]]) %in% as.character(values)
    if (isTRUE(attr(values, "negate"))) {
      keep <- !keep
    }

    filtered_data <- filtered_data[keep, , drop = FALSE]
  }

  return(filtered_data)
}

#' Subset TACs by Frame or Time Range
#'
#' @description Filter TAC data to keep only specified frame range or time window
#' @param tacs_data Tibble with TAC data
#' @param subset_type Type of subsetting: "frame", "time", or NULL for no subsetting
#' @param start_point Start frame number or time in minutes
#' @param end_point End frame number or time in minutes
#' @return Filtered tibble with only specified frames
#' @export
subset_tacs_by_frames <- function(tacs_data, subset_type = NULL,
                                  start_point = NULL, end_point = NULL) {

  # If no subsetting specified, return data as-is
  if (is.null(subset_type) || subset_type == "" ||
      is.null(start_point) || is.null(end_point)) {
    return(tacs_data)
  }

  if (is.null(tacs_data) || nrow(tacs_data) == 0) {
    return(tibble::tibble())
  }

  filtered_data <- tacs_data

  if (subset_type == "frame") {
    # Subset by frame number (assuming frames are numbered sequentially)
    # Create frame number column if not exists
    if (!"frame_num" %in% colnames(filtered_data)) {
      filtered_data <- filtered_data %>%
        dplyr::group_by(dplyr::across(dplyr::any_of(c("pet", "region")))) %>%
        dplyr::mutate(frame_num = dplyr::row_number()) %>%
        dplyr::ungroup()
    }

    filtered_data <- filtered_data %>%
      dplyr::filter(frame_num >= start_point & frame_num <= end_point) %>%
      dplyr::select(-dplyr::any_of("frame_num"))

  } else if (subset_type == "time") {
    # Subset by time in minutes using frame midpoint
    # Convert time inputs from minutes to seconds (frame_mid is in seconds)
    start_seconds <- start_point * 60
    end_seconds <- end_point * 60
    filtered_data <- filtered_data %>%
      dplyr::filter(frame_mid >= start_seconds & frame_mid <= end_seconds)
  }

  return(filtered_data)
}

#' Clear Derived Outputs from an Analysis Folder
#'
#' @description Remove every derived output from an analysis folder before the
#'   data definition step regenerates it. Rerunning data definition changes the
#'   data every later step consumes, so everything downstream of it -- the
#'   individual TACs files, weights, delay fits, model results and reports --
#'   is invalidated and removed, to be recalculated from the new definition.
#'
#'   Two things are kept. The analysis configuration (`desc-*_config.json`)
#'   defines the analysis rather than deriving from it. And
#'   `*_inputfunction.tsv`/`.json` pairs are a supported blood *source* --
#'   [determine_blood_source()] looks for them in the analysis folder, and a
#'   user may have placed them there by hand -- while the ones petfit itself
#'   writes derive from the BIDS blood data, which a data definition does not
#'   change. Either way they are not stale, and deleting the hand-placed kind
#'   would destroy source data.
#'
#'   This replaces a selective cleanup that compared filename stems against the
#'   measurements being kept. That comparison deleted files whose stems it did
#'   not understand, and left stale results behind when it did: outputs
#'   computed from a previous data definition are stale whether or not their
#'   measurement is still in the analysis.
#'
#' @param output_dir Output directory containing the analysis
#' @return List with counts of removed files and directories
#' @export
cleanup_individual_tacs_files <- function(output_dir) {

  if (!dir.exists(output_dir)) {
    return(list(files_removed = 0, dirs_removed = 0,
                summary = "Output directory does not exist"))
  }

  # Guard against clearing something that is not an analysis folder: an
  # analysis folder is recognised by the configuration that defines it. A
  # mispointed path -- the petfit derivatives root, "." -- would otherwise be
  # emptied wholesale.
  entries <- list.files(output_dir, all.files = FALSE)
  has_config <- any(grepl("^desc-.*_config\\.json$", entries))
  if (!has_config && length(entries) > 0) {
    stop("Refusing to clear ", output_dir, ": it contains no ",
         "desc-*_config.json, so it does not look like an analysis folder. ",
         "Clearing it would delete files petfit did not generate.",
         call. = FALSE)
  }

  all_files <- list.files(output_dir, recursive = TRUE, full.names = TRUE,
                          all.files = FALSE)

  keep <- grepl("^desc-.*_config\\.json$", basename(all_files)) |
    grepl("_inputfunction\\.(tsv|json)$", basename(all_files))
  remove <- all_files[!keep]

  files_removed <- length(remove)
  for (filepath in remove) {
    file.remove(filepath)
    cat("Removed file:", basename(filepath), "\n")
  }

  # Prune directories the removals emptied, deepest first
  dirs_removed <- 0
  dirs <- list.dirs(output_dir, recursive = TRUE, full.names = TRUE)
  dirs <- setdiff(dirs, output_dir)
  dirs <- dirs[order(-lengths(strsplit(dirs, "/", fixed = TRUE)))]
  for (dir_path in dirs) {
    if (length(list.files(dir_path, all.files = FALSE)) == 0) {
      unlink(dir_path, recursive = TRUE)
      dirs_removed <- dirs_removed + 1
    }
  }

  summary_msg <- if (files_removed > 0 || dirs_removed > 0) {
    paste("Cleared", files_removed, "derived files and", dirs_removed,
          "folders from the previous data definition")
  } else {
    "No existing analysis files found"
  }

  return(list(
    files_removed = files_removed,
    dirs_removed = dirs_removed,
    summary = summary_msg
  ))
}

#' Create Individual TACs Files
#'
#' @description Create individual TACs files for each subject/session/pet combination
#' @param filtered_data Filtered combined TACs data
#' @param output_dir Output directory for individual files
#' @return Summary of created files
#' @export
create_individual_tacs_files <- function(filtered_data, output_dir) {
  
  if (is.null(filtered_data) || nrow(filtered_data) == 0) {
    warning("No data to create individual files")
    return(list(files_created = 0, summary = "No data"))
  }
  
  # Group by individual measurements (sub, ses, pet)
  measurement_groups <- filtered_data %>%
    dplyr::group_by(sub, ses, pet) %>%
    dplyr::group_nest(.key = "tacs_data", keep = TRUE)
  
  created_files <- c()
  
  # Create individual files for each measurement group
  for (i in 1:nrow(measurement_groups)) {
    sub_id <- measurement_groups$sub[i]
    ses_id <- measurement_groups$ses[i]
    pet_id <- measurement_groups$pet[i]
    tacs_data <- measurement_groups$tacs_data[[i]]
    
    # Create folder structure
    if (!is.na(ses_id)) {
      folder_path <- file.path(output_dir, paste0("sub-", sub_id), paste0("ses-", ses_id), "pet")
    } else {
      folder_path <- file.path(output_dir, paste0("sub-", sub_id), "pet")
    }
    
    # Create directories recursively
    if (!dir.exists(folder_path)) {
      dir.create(folder_path, recursive = TRUE)
    }
    
    # Generate filename using pet column
    filename <- paste0(pet_id, "_desc-combinedregions_tacs.tsv")
    filepath <- file.path(folder_path, filename)
    
    # Select and reorder columns for output
    output_data <- tacs_data %>%
      dplyr::select(pet, region, volume_mm3, InjectedRadioactivity, bodyweight, 
                   frame_start, frame_end, frame_dur, frame_mid, TAC) %>%
      dplyr::arrange(region, frame_start)
    
    # Write file
    tryCatch({
      readr::write_tsv(output_data, filepath)
      created_files <- c(created_files, filepath)
      cat("Created:", filename, "\n")
    }, error = function(e) {
      warning(paste("Error creating file", filename, ":", e$message))
    })
  }
  
  # Return summary
  return(list(
    files_created = length(created_files),
    file_paths = created_files,
    summary = paste("Created", length(created_files), "individual TACs files")
  ))
}