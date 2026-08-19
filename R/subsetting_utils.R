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

# --- Filesystem safety for the cleanup ------------------------------------
#
# Cleanup deletes, so every question it asks about a path has to be answered
# positively before it acts. Base R cannot do that portably: Sys.readlink() is
# documented as reporting nothing on Windows even though NTFS has symbolic
# links and junctions, and a junction presents to directory-walking code as an
# ordinary directory while redirecting traversal elsewhere. normalizePath()
# usually resolves them on modern R but documents a fallback that does not, so
# it cannot be the only boundary either. fs wraps libuv and answers these
# questions the same way on every platform.
#
# The rule throughout: never descend into an entry unless it has been
# positively established as a real directory whose canonical path lies inside
# the analysis root. Anything unresolvable, unclassifiable, or outside is an
# error -- a directory nobody can classify is not "probably ordinary".

# The canonical destination of a path, or an error naming what could not be
# resolved. Never called on a link: path_real() follows one, and a broken link
# cannot be resolved at all.
petfit_real_path <- function(path, description = "path") {
  tryCatch(
    as.character(fs::path_real(path)),
    error = function(e) {
      stop("Refusing to clear the analysis folder: could not resolve ",
           description, ":\n  ", path, "\nReason: ", conditionMessage(e),
           call. = FALSE)
    })
}

# Is this entry a filesystem link -- POSIX symbolic link, Windows symbolic
# link, or NTFS junction? Anything other than a definite yes or no stops the
# cleanup rather than defaulting to "ordinary file".
petfit_link_state <- function(path) {

  result <- tryCatch(fs::is_link(path), error = function(e) NA)

  if (length(result) != 1L || is.na(result)) {
    stop("Refusing to clear the analysis folder: could not determine whether ",
         "this path is a link:\n  ", path, call. = FALSE)
  }

  isTRUE(result)
}

# Everything under `dir`, classified, without following a single link.
#
# The whole tree is enumerated before anything is deleted, so a path that
# cannot be classified stops the cleanup while the folder is still intact.
# Links are recorded as one entry each, whatever they point at and wherever
# they point: the policy is "never follow a link", not "never leave the
# folder", so a link to a sibling directory inside the analysis is still a
# link and is still not descended into. Hidden entries are included --
# a directory holding only dotfiles is not empty, and treating it as empty is
# how a recursive delete reaches them.
petfit_list_tree <- function(dir) {

  root_real <- petfit_real_path(dir, "the analysis folder")

  files <- character(0)
  dirs  <- character(0)
  links <- character(0)

  descend <- function(current) {

    children <- as.character(
      fs::dir_ls(current, all = TRUE, recurse = FALSE, fail = TRUE))

    for (child in children) {

      if (petfit_link_state(child)) {
        links <<- c(links, child)
        next
      }

      child_real <- petfit_real_path(child)
      inside <- identical(child_real, root_real) ||
        isTRUE(fs::path_has_parent(child_real, root_real))

      if (!inside) {
        # fs did not call this a link, yet it leads out of the folder. It may
        # be a reparse point, a mount, or something on a filesystem fs cannot
        # describe. Guessing how to delete it is exactly the mistake this
        # function exists to avoid.
        stop("Refusing to clear the analysis folder: a path resolves outside ",
             "it but is not identifiable as a removable link:\n  Path: ", child,
             "\n  Destination: ", child_real, call. = FALSE)
      }

      if (isTRUE(fs::is_dir(child, follow = FALSE))) {
        dirs <<- c(dirs, child)
        descend(child)
      } else if (isTRUE(fs::is_file(child, follow = FALSE))) {
        files <<- c(files, child)
      } else {
        stop("Refusing to clear the analysis folder: unsupported or ",
             "unclassifiable filesystem entry:\n  ", child, call. = FALSE)
      }
    }
  }

  descend(dir)

  list(files = files, dirs = dirs, links = links)
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
  #
  # Hidden entries count. The walker below enumerates and removes them, so a
  # guard that cannot see them reads a directory holding only a .env or a
  # .gitkeep as empty, waves it through as "nothing here to protect", and the
  # walker then deletes exactly the files the guard was meant to stand in
  # front of. A genuinely empty directory is still fine.
  entries <- list.files(output_dir, all.files = TRUE, no.. = TRUE)
  has_config <- any(grepl("^desc-.*_config\\.json$", entries))
  if (!has_config && length(entries) > 0) {
    stop("Refusing to clear ", output_dir, ": it contains no ",
         "desc-*_config.json, so it does not look like an analysis folder. ",
         "Clearing it would delete files petfit did not generate.",
         call. = FALSE)
  }

  # Classify the whole tree first. Anything unclassifiable stops the cleanup
  # here, with the folder untouched.
  tree <- petfit_list_tree(output_dir)

  keepable <- function(paths) {
    grepl("^desc-.*_config\\.json$", basename(paths)) |
      grepl("_inputfunction\\.(tsv|json)$", basename(paths))
  }

  # Links go first. If one cannot be removed, the cleanup stops while the
  # derived outputs are still there rather than after clearing them.
  links_removed <- 0L
  for (linkpath in tree$links[!keepable(tree$links)]) {

    fs::link_delete(linkpath)

    if (isTRUE(fs::link_exists(linkpath))) {
      stop("Cleanup reported that a link was deleted, but it is still there:",
           "\n  ", linkpath, call. = FALSE)
    }

    links_removed <- links_removed + 1L
    cat("Removed symlink:", basename(linkpath),
        "- whatever it pointed at was left alone\n")
  }

  files_removed <- 0L
  for (filepath in tree$files[!keepable(tree$files)]) {

    # Re-check: an entry could have been replaced by a link since it was
    # classified, and a deletion that follows one leaves the folder.
    if (petfit_link_state(filepath) ||
        !isTRUE(fs::is_file(filepath, follow = FALSE))) {
      stop("Refusing to continue: this entry changed between being examined ",
           "and being removed:\n  ", filepath, call. = FALSE)
    }

    fs::file_delete(filepath)
    files_removed <- files_removed + 1L
    cat("Removed file:", basename(filepath), "\n")
  }

  # Prune the directories those removals emptied, deepest first, re-checking
  # each one the same way. fs::dir_delete() removes contents as well, so it is
  # only ever reached for a directory just confirmed empty.
  dirs_removed <- 0L
  root_real <- petfit_real_path(output_dir, "the analysis folder")
  for (dir_path in tree$dirs[order(-lengths(strsplit(tree$dirs, "/", fixed = TRUE)))]) {

    if (!dir.exists(dir_path)) next

    if (petfit_link_state(dir_path) ||
        !isTRUE(fs::is_dir(dir_path, follow = FALSE)) ||
        !isTRUE(fs::path_has_parent(petfit_real_path(dir_path), root_real))) {
      stop("Refusing to continue: this folder changed between being examined ",
           "and being removed:\n  ", dir_path, call. = FALSE)
    }

    if (length(fs::dir_ls(dir_path, all = TRUE, recurse = FALSE)) > 0) next

    fs::dir_delete(dir_path)
    dirs_removed <- dirs_removed + 1L
  }

  total_removed <- files_removed + links_removed

  summary_msg <- if (total_removed > 0 || dirs_removed > 0) {
    paste0("Cleared ", total_removed, " derived files and ", dirs_removed,
           " folders from the previous data definition",
           if (links_removed > 0) {
             paste0(" (", links_removed, " of them symbolic links, whose ",
                    "targets were left alone)")
           } else "")
  } else {
    "No existing analysis files found"
  }

  return(list(
    files_removed = total_removed,
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