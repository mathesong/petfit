#' Combine Single Region TAC using Volume-Weighted Averaging
#'
#' @description Core function for volume-weighted averaging of constituent regions
#'
#' @param tacs_data TACs tibble in wide format (regions as columns)
#' @param morph_data Morph tibble with volume data (can be NULL for volume=1 fallback)
#' @param constituent_regions Vector of region names to combine
#' @param region_name Name for the combined region
#' @return Single tibble with combined TAC and total volume
#' @export
combine_single_region_tac <- function(tacs_data, morph_data, constituent_regions, region_name) {

  # Validate inputs with graceful handling
  if (is.null(tacs_data) || nrow(tacs_data) == 0) {
    warning(paste("TACs data is empty or NULL for", region_name, "- excluding from output"))
    return(tibble::tibble())
  }

  if (length(constituent_regions) == 0) {
    warning(paste("No constituent regions provided for", region_name, "- excluding from output"))
    return(tibble::tibble())
  }

  # Check which constituent regions are available in tacs
  available_in_tacs <- constituent_regions[constituent_regions %in% colnames(tacs_data)]

  if (length(available_in_tacs) == 0) {
    # GRACEFUL: Return empty tibble instead of stopping
    warning(paste("No constituent regions found in TACs data for", region_name, ":",
                  paste(constituent_regions, collapse = ", "),
                  "- excluding from output"))
    return(tibble::tibble())
  }

  # Handle morph data: use volume=1 fallback if NULL or missing volume-mm3 column
  if (is.null(morph_data) || !"volume-mm3" %in% colnames(morph_data)) {
    # Use volume=1 for all regions (equal weighting)
    region_volumes <- tibble::tibble(
      name = available_in_tacs,
      `volume-mm3` = 1.0
    )
    available_regions <- available_in_tacs
  } else {
    # Use actual volumes from morph data
    available_in_morph <- constituent_regions[constituent_regions %in% morph_data$name]
    available_regions <- intersect(available_in_tacs, available_in_morph)

    if (length(available_regions) == 0) {
      # GRACEFUL: Return empty tibble instead of stopping
      warning(paste("No constituent regions found for", region_name, ":",
                    paste(constituent_regions, collapse = ", "),
                    "- excluding from output"))
      return(tibble::tibble())
    }

    if (length(available_regions) < length(constituent_regions)) {
      missing_regions <- setdiff(constituent_regions, available_regions)
      # GRACEFUL: Warning instead of error
      warning(paste("Some constituent regions not found for", region_name, ":",
                    paste(missing_regions, collapse = ", "),
                    "- using available regions only"))
    }

    # Filter morph data for available regions
    region_volumes <- morph_data %>%
      dplyr::filter(name %in% available_regions) %>%
      dplyr::select(name, `volume-mm3`)
  }

  # Calculate total volume
  total_volume <- sum(region_volumes$`volume-mm3`)
  
  if (total_volume == 0) {
    # GRACEFUL: Return empty tibble instead of stopping
    warning(paste("Total volume is zero for", region_name, 
                  "- excluding from output"))
    return(tibble::tibble())
  }
  
  # Calculate volume fractions
  region_volumes <- region_volumes %>%
    dplyr::mutate(volume_fraction = `volume-mm3` / total_volume)
  
  # Apply volume weighting to TACs data
  time_cols <- c("frame_start", "frame_end")
  
  # Initialize result with time columns
  combined_tac <- tacs_data %>%
    dplyr::select(dplyr::all_of(time_cols))
  
  # Calculate volume-weighted TAC for each time frame
  weighted_tac_values <- rep(0, nrow(tacs_data))
  
  for (region in available_regions) {
    volume_frac <- region_volumes$volume_fraction[region_volumes$name == region]
    # Note: readr::read_tsv preserves hyphens in column names, no conversion needed
    region_tac <- tacs_data[[region]]
    weighted_tac_values <- weighted_tac_values + (region_tac * volume_frac)
  }
  
  # Add combined results
  combined_tac$name <- region_name
  combined_tac$TAC <- weighted_tac_values
  combined_tac$`volume-mm3` <- total_volume
  
  # Calculate frame duration and midpoint
  combined_tac$frame_dur <- combined_tac$frame_end - combined_tac$frame_start
  combined_tac$frame_mid <- combined_tac$frame_start + 0.5 * combined_tac$frame_dur
  
  return(combined_tac)
}

#' Create petfit Regions Files Mapping
#'
#' @description Creates file mapping TSV linking regions to their TACs/morph files using seg/label-based matching
#'
#' @param petfit_regions_file Path to petfit_regions.tsv
#' @param derivatives_folder Base path to derivatives folder
#' @return Creates petfit_regions_files.tsv and returns the mapping data
#' @export
create_petfit_regions_files <- function(petfit_regions_file, derivatives_folder) {

  # Validate inputs
  if (!file.exists(petfit_regions_file)) {
    stop(paste("petfit_regions.tsv file not found:", petfit_regions_file))
  }

  if (!dir.exists(derivatives_folder)) {
    stop(paste("Derivatives folder not found:", derivatives_folder))
  }

  # Read petfit_regions.tsv
  regions_config <- readr::read_tsv(petfit_regions_file, show_col_types = FALSE)

  if (nrow(regions_config) == 0) {
    stop("petfit_regions.tsv is empty")
  }

  # Get unique folder combinations
  unique_folders <- unique(regions_config$folder)

  # Create tacs-morph mappings for each folder using new matching system
  all_mappings <- purrr::map_dfr(unique_folders, function(folder_name) {
    folder_path <- file.path(derivatives_folder, folder_name)

    if (!dir.exists(folder_path)) {
      warning(paste("Folder not found:", folder_path))
      return(tibble::tibble())
    }

    # Use efficient bulk matching
    cat("Creating tacs-morph mapping for folder:", folder_name, "\n")
    mapping <- create_tacs_morph_mapping(folder_path)

    if (nrow(mapping) == 0) {
      warning(paste("No tacs files with seg/label found in", folder_path))
      return(tibble::tibble())
    }

    # Extract descriptions from tacs files
    mapping <- mapping %>%
      dplyr::mutate(
        folder = folder_name,
        # Extract full filename from path for matching with description
        tacs_basename = basename(tacs_path),
        # Create relative paths from derivatives folder
        tacs_filename = stringr::str_replace(tacs_path, paste0("^", derivatives_folder, "/?"), ""),
        morph_filename = dplyr::if_else(
          !is.na(morph_path),
          stringr::str_replace(morph_path, paste0("^", derivatives_folder, "/?"), ""),
          NA_character_
        )
      )

    return(mapping)
  })

  if (nrow(all_mappings) == 0) {
    stop("No valid TACs files with seg/label attributes found")
  }

  # Match tacs files to descriptions using filename patterns
  # Extract descriptions from tacs filenames
  all_mappings <- all_mappings %>%
    dplyr::mutate(
      # Extract description string from tacs filename (all attributes except sub, ses, trc, rec, task, run)
      description_parsed = purrr::map(tacs_basename, extract_bids_attributes_from_filename)
    ) %>%
    tidyr::unnest(description_parsed) %>%
    dplyr::mutate(
      # Create description string from all non-identifier attributes
      description = create_bids_key_value_pairs(
        dplyr::pick(dplyr::everything()),
        setdiff(colnames(dplyr::pick(dplyr::everything())), c("tacs_path", "morph_path", "folder", "tacs_basename", "tacs_filename", "morph_filename", "sub", "ses", "trc", "rec", "task", "run", "pet"))
      )$description
    )

  # Join with original regions config
  regions_files <- regions_config %>%
    dplyr::inner_join(
      all_mappings %>% dplyr::select(folder, description, tacs_filename, morph_filename),
      by = c("folder", "description"),
      relationship = "many-to-many"
    )

  if (nrow(regions_files) == 0) {
    stop("No regions could be matched to valid file pairs. Check that descriptions in petfit_regions.tsv match the tacs file attributes.")
  }

  # Write to output file
  output_dir <- dirname(petfit_regions_file)
  output_file <- file.path(output_dir, "petfit_regions_files.tsv")

  readr::write_tsv(regions_files, output_file)

  cat("Created petfit_regions_files.tsv with", nrow(regions_files), "region-file mappings\n")
  cat("Output file:", output_file, "\n")

  return(regions_files)
}

#' Combine Regions from Single TACs/Morph File Pair
#'
#' @description Process all region combinations for one TACs/morph file pair
#'
#' @param derivatives_folder Base path to derivatives folder
#' @param tacs_relative_path Relative path to TACs file from derivatives folder
#' @param morph_relative_path Relative path to morph file from derivatives folder
#' @param regions_for_files Filtered regions config for these specific files
#' @return Tibble with all combined regions for this file pair
#' @export
combine_regions_from_files <- function(derivatives_folder, tacs_relative_path, 
                                      morph_relative_path, regions_for_files) {
  
  # Construct full file paths
  tacs_full_path <- file.path(derivatives_folder, tacs_relative_path)
  morph_full_path <- file.path(derivatives_folder, morph_relative_path)
  
  # Validate file existence with graceful handling
  if (!file.exists(tacs_full_path)) {
    warning(paste("TACs file not found:", tacs_full_path, "- skipping"))
    return(tibble::tibble())
  }
  
  if (!file.exists(morph_full_path)) {
    warning(paste("Morph file not found:", morph_full_path, "- skipping"))
    return(tibble::tibble())
  }
  
  # Read data files with graceful error handling
  tacs_data <- tryCatch({
    readr::read_tsv(tacs_full_path, show_col_types = FALSE)
  }, error = function(e) {
    warning(paste("Error reading TACs file:", e$message, "- skipping"))
    return(NULL)
  })
  
  if (is.null(tacs_data)) {
    return(tibble::tibble())
  }
  
  morph_data <- tryCatch({
    readr::read_tsv(morph_full_path, show_col_types = FALSE)
  }, error = function(e) {
    warning(paste("Error reading morph file:", e$message, "- skipping"))
    return(NULL)
  })
  
  if (is.null(morph_data)) {
    return(tibble::tibble())
  }
  
  # Group regions by RegionName
  region_groups <- regions_for_files %>%
    dplyr::group_by(RegionName) %>%
    dplyr::summarise(
      ConstituentRegions = list(ConstituentRegion),
      .groups = "drop"
    )
  
  # Combine each region group
  combined_results <- purrr::map_dfr(1:nrow(region_groups), function(i) {
    region_name <- region_groups$RegionName[i]
    constituent_regions <- region_groups$ConstituentRegions[[i]]
    
    tryCatch({
      combine_single_region_tac(tacs_data, morph_data, constituent_regions, region_name)
    }, error = function(e) {
      warning(paste("Failed to combine region", region_name, ":", e$message))
      return(tibble::tibble())
    })
  })
  
  if (nrow(combined_results) == 0) {
    warning("No regions were successfully combined")
    return(tibble::tibble())
  }
  
  return(combined_results)
}

#' Process All petfit Regions Across All Files
#'
#' @description Orchestrate entire region combination process across all files
#'
#' @param petfit_regions_files_path Path to petfit_regions_files.tsv
#' @param derivatives_folder Base path to derivatives folder
#' @param output_folder Where to save combined TACs files
#' @return Processing summary tibble
#' @export
process_all_petfit_regions <- function(petfit_regions_files_path, derivatives_folder, output_folder) {
  
  # Validate inputs
  if (!file.exists(petfit_regions_files_path)) {
    stop(paste("petfit_regions_files.tsv not found:", petfit_regions_files_path))
  }
  
  if (!dir.exists(derivatives_folder)) {
    stop(paste("Derivatives folder not found:", derivatives_folder))
  }
  
  # Create output folder if it doesn't exist
  if (!dir.exists(output_folder)) {
    dir.create(output_folder, recursive = TRUE)
    cat("Created output folder:", output_folder, "\n")
  }
  
  # Read regions files mapping
  regions_files <- readr::read_tsv(petfit_regions_files_path, show_col_types = FALSE)
  
  if (nrow(regions_files) == 0) {
    stop("petfit_regions_files.tsv is empty")
  }
  
  # Group by unique TACs/morph file pairs
  file_groups <- regions_files %>%
    dplyr::group_by(tacs_filename, morph_filename) %>%
    dplyr::group_nest(.key = "regions_data")
  
  # Process each file pair
  processing_summary <- purrr::map_dfr(1:nrow(file_groups), function(i) {
    tacs_file <- file_groups$tacs_filename[i]
    morph_file <- file_groups$morph_filename[i]
    regions_data <- file_groups$regions_data[[i]]
    
    cat("Processing:", tacs_file, "\n")
    
    tryCatch({
      # Combine regions for this file pair
      combined_results <- combine_regions_from_files(
        derivatives_folder, tacs_file, morph_file, regions_data
      )
      
      if (nrow(combined_results) > 0) {
        # Generate output filename
        base_filename <- basename(tacs_file)
        output_filename <- stringr::str_replace(base_filename, "_tacs\\.tsv$", "_combined_tacs.tsv")
        output_path <- file.path(output_folder, output_filename)
        
        # Save combined results
        readr::write_tsv(combined_results, output_path)
        
        cat("  Saved:", output_filename, "with", nrow(combined_results), "time points\n")
        
        return(tibble::tibble(
          tacs_file = tacs_file,
          output_file = output_filename,
          regions_combined = length(unique(combined_results$name)),
          time_points = nrow(combined_results),
          status = "success"
        ))
      } else {
        warning(paste("No regions combined for", tacs_file))
        return(tibble::tibble(
          tacs_file = tacs_file,
          output_file = NA_character_,
          regions_combined = 0,
          time_points = 0,
          status = "no_regions"
        ))
      }
    }, error = function(e) {
      warning(paste("Error processing", tacs_file, ":", e$message))
      return(tibble::tibble(
        tacs_file = tacs_file,
        output_file = NA_character_,
        regions_combined = 0,
        time_points = 0,
        status = paste("error:", e$message)
      ))
    })
  })
  
  # Print summary
  successful_files <- sum(processing_summary$status == "success")
  total_files <- nrow(processing_summary)
  total_regions <- sum(processing_summary$regions_combined, na.rm = TRUE)
  
  cat("\n=== Processing Summary ===\n")
  cat("Files processed successfully:", successful_files, "/", total_files, "\n")
  cat("Total regions combined:", total_regions, "\n")
  cat("Output folder:", output_folder, "\n")
  
  return(processing_summary)
}

#' Extract BIDS Attributes from Filename
#'
#' @description Extract BIDS key-value pairs from filename following bloodstream pattern
#'
#' @param filename Filename to parse (can be full path or basename)
#' @return Tibble with BIDS attributes (sub, ses, trc, rec, task, run, desc, seg, label, pet, plus any additional attributes like pvc)
#' @export
extract_bids_attributes_from_filename <- function(filename) {
  # Parse filename to extract BIDS key-value pairs
  # Required: sub, ses, trc, rec, task, run, desc, seg, label, pet
  # Additional: pvc and any other key-value pairs found in filename
  # IMPORTANT: Extract only VALUES, not key-value pairs (e.g., "01" not "sub-01")

  basename_file <- basename(filename)

  # Extract all key-value pairs from filename using regex
  # Pattern matches: key-value where key is letters and value is alphanumeric/hyphens
  matches <- stringr::str_extract_all(basename_file, "([a-zA-Z]+)-([a-zA-Z0-9]+)")[[1]]

  # Parse matches into key-value pairs
  attributes <- list()
  for (match in matches) {
    parts <- stringr::str_split(match, "-", n = 2)[[1]]
    if (length(parts) == 2) {
      key <- parts[1]
      value <- parts[2]
      attributes[[key]] <- value
    }
  }

  # Directories may supply sub and ses -- the only entities BIDS names
  # directories after. petfit's own derivatives put ses in the path but not
  # the filename, so reducing the path to its basename merged distinct
  # sessions into one measurement. Only whole sub-/ses- segments count, so
  # unrelated path components cannot inject entities, and a directory that
  # contradicts the filename is an error rather than a silent pick.
  segments <- strsplit(dirname(filename), "/", fixed = TRUE)[[1]]
  dir_entities <- stringr::str_match(segments, "^(sub|ses)-([a-zA-Z0-9]+)$")
  dir_entities <- dir_entities[!is.na(dir_entities[, 1]), , drop = FALSE]
  for (i in seq_len(nrow(dir_entities))) {
    key <- dir_entities[i, 2]
    value <- dir_entities[i, 3]
    if (is.null(attributes[[key]])) {
      attributes[[key]] <- value
    } else if (!identical(attributes[[key]], value)) {
      stop("The filename and the directory holding it disagree on ", key,
           " for ", filename, ": \"", attributes[[key]], "\" vs \"", value,
           "\". The file's identity is ambiguous.", call. = FALSE)
    }
  }

  # Always include required attributes (set to NA if missing)
  result <- tibble::tibble(
    sub = attributes[["sub"]] %||% NA_character_,
    ses = attributes[["ses"]] %||% NA_character_,
    trc = attributes[["trc"]] %||% NA_character_,
    rec = attributes[["rec"]] %||% NA_character_,
    task = attributes[["task"]] %||% NA_character_,
    run = attributes[["run"]] %||% NA_character_,
    desc = attributes[["desc"]] %||% NA_character_,
    seg = attributes[["seg"]] %||% NA_character_,
    label = attributes[["label"]] %||% NA_character_
  )

  # Create pet column (following bloodstream pattern) - PET measurement identifier
  # Remove desc and measurement suffix to get the core PET identifier
  pet <- basename_file %>%
    stringr::str_remove("_desc-[^_]+.*$") %>%  # Remove desc and everything after
    stringr::str_remove("_tacs\\.tsv$")       # Remove measurement suffix if still there
  result$pet <- pet

  # Add any other attributes found (excluding the required ones already added)
  required_keys <- c("sub", "ses", "trc", "rec", "task", "run", "desc", "seg", "label")
  other_attributes <- attributes[!names(attributes) %in% required_keys]

  for (key in names(other_attributes)) {
    result[[key]] <- other_attributes[[key]]
  }

  return(result)
}

#' Check Hierarchical Match Between TACs and Morph Attributes
#'
#' @description Determines if a morph file matches a tacs file using hierarchical matching rules
#'
#' @param tacs_attrs Tibble with tacs BIDS attributes from extract_bids_attributes_from_filename()
#' @param morph_attrs Tibble with morph BIDS attributes from extract_bids_attributes_from_filename()
#' @return Logical TRUE if files match, FALSE otherwise
#' @details
#' Matching rules:
#' - EXACT: sub, seg/label must match exactly
#' - HIERARCHICAL: morph without ses/run matches all ses/run values for that subject
#' - FALLBACK: a single available subject/segmentation morph can be reused across sessions/runs
#' - IGNORED: pvc, desc, rec, task not used for matching
#' @export
is_hierarchical_match <- function(tacs_attrs, morph_attrs) {

  # 1. EXACT MATCH: sub must match exactly
  if (is.na(tacs_attrs$sub) || is.na(morph_attrs$sub)) return(FALSE)
  if (tacs_attrs$sub != morph_attrs$sub) return(FALSE)

  # 2. EXACT MATCH: seg OR label must match exactly
  # Check seg first
  if (!is.na(tacs_attrs$seg)) {
    # TACs has seg - morph must also have matching seg
    if (is.na(morph_attrs$seg)) return(FALSE)
    if (tacs_attrs$seg != morph_attrs$seg) return(FALSE)
  } else if (!is.na(tacs_attrs$label)) {
    # TACs has label - morph must also have matching label
    if (is.na(morph_attrs$label)) return(FALSE)
    if (tacs_attrs$label != morph_attrs$label) return(FALSE)
  } else {
    # TACs has neither seg nor label - cannot match
    return(FALSE)
  }

  # 3. HIERARCHICAL MATCH: ses
  if (!is.na(morph_attrs$ses)) {
    # Morph has ses - exact matching is preferred. Cross-session reuse is
    # handled in create_tacs_morph_mapping() only when the candidate is unique.
    if (is.na(tacs_attrs$ses)) return(FALSE)
    if (tacs_attrs$ses != morph_attrs$ses) return(FALSE)
  }
  # If morph has no ses, it matches all ses values (no check needed)

  # 4. HIERARCHICAL MATCH: run
  if (!is.na(morph_attrs$run)) {
    # Morph has run - must match exactly
    if (is.na(tacs_attrs$run)) return(FALSE)
    if (tacs_attrs$run != morph_attrs$run) return(FALSE)
  }
  # If morph has no run, it matches all run values (no check needed)

  # 5. IGNORED: pvc, desc, rec, task - not checked at all

  return(TRUE)
}

#' Create TACs-Morph File Mapping for Pipeline Folder
#'
#' @description Efficiently maps all tacs files to their matching morph files using dplyr joins
#'
#' @param pipeline_folder Full path to pipeline folder (e.g., derivatives/petprep)
#' @return Tibble with columns: tacs_path, morph_path (morph_path is NA if no match)
#' @details
#' Efficient bulk matching strategy:
#' 1. Recursively finds all tacs and morph files once
#' 2. Extracts attributes from all files (keeping only those with seg/label)
#' 3. Uses dplyr join with hierarchical ses/run matching
#' 4. Returns complete mapping
#' @export
create_tacs_morph_mapping <- function(pipeline_folder) {

  # Find all tacs files (excluding combined files)
  tacs_files <- list.files(pipeline_folder, pattern = "_tacs\\.tsv$",
                           full.names = TRUE, recursive = TRUE)
  tacs_files <- tacs_files[!grepl("desc-combinedregions_tacs\\.tsv$", tacs_files)]

  # Find all morph files
  morph_files <- list.files(pipeline_folder, pattern = "_morph\\.tsv$",
                            full.names = TRUE, recursive = TRUE)

  # No files of a kind means no attributes to read, and purrr::map_dfr() over an
  # empty vector returns a tibble with no columns at all -- not one with the
  # expected columns and no rows. Filtering that for `seg` fails with "object
  # 'seg' not found", which is what a whole derivatives folder used to die of
  # because one pipeline folder inside it had TACs but no morph files. The
  # emptiness has to be answered before the columns are referred to.
  tacs_data <- if (length(tacs_files) == 0) {
    tibble::tibble()
  } else {
    purrr::map_dfr(tacs_files, function(f) {
      attrs <- extract_bids_attributes_from_filename(f)
      attrs$tacs_path <- f
      attrs
    }) %>%
      # Filter tacs files to only those with seg or label
      dplyr::filter(!is.na(seg) | !is.na(label))
  }

  # If no valid tacs files, return empty
  if (nrow(tacs_data) == 0) {
    return(tibble::tibble(tacs_path = character(0), morph_path = character(0)))
  }

  morph_data <- if (length(morph_files) == 0) {
    tibble::tibble()
  } else {
    purrr::map_dfr(morph_files, function(f) {
      attrs <- extract_bids_attributes_from_filename(f)
      attrs$morph_path <- f
      attrs
    }) %>%
      # Filter morph files to only those with seg or label
      dplyr::filter(!is.na(seg) | !is.na(label))
  }

  # If no valid morph files, return tacs with NA morph paths. Every region is
  # then combined with equal weighting -- see get_region_volumes_from_morph().
  if (nrow(morph_data) == 0) {
    return(tibble::tibble(
      tacs_path = tacs_data$tacs_path,
      morph_path = NA_character_
    ))
  }

  # Perform hierarchical matching using joins
  # Match on: sub (exact), seg/label (exact), ses (hierarchical), run (hierarchical)

  # Create matching keys
  tacs_data <- tacs_data %>%
    dplyr::mutate(
      match_key = dplyr::coalesce(seg, label),  # Use seg if present, else label
      match_type = dplyr::if_else(!is.na(seg), "seg", "label")
    )

  morph_data <- morph_data %>%
    dplyr::mutate(
      match_key = dplyr::coalesce(seg, label),
      match_type = dplyr::if_else(!is.na(seg), "seg", "label")
    )

  # Join on sub and match_key, then score candidate morph specificity.
  # Exact matches win, morphs without ses/run are valid for all PETs, and a
  # single available subject/segmentation morph can be reused across PET
  # sessions/runs when no exact or entity-agnostic morph exists.
  mapping <- tacs_data %>%
    dplyr::left_join(
      morph_data %>% dplyr::select(sub, match_key, ses, run, morph_path),
      by = c("sub", "match_key"),
      relationship = "many-to-many"
    ) %>%
    dplyr::group_by(tacs_path) %>%
    dplyr::mutate(
      n_morph_candidates = dplyr::n_distinct(morph_path[!is.na(morph_path)]),
      ses_score = dplyr::case_when(
        is.na(morph_path) ~ 0L,
        is.na(ses.y) ~ 1L,
        !is.na(ses.x) & ses.x == ses.y ~ 0L,
        n_morph_candidates == 1L ~ 2L,
        TRUE ~ NA_integer_
      ),
      run_score = dplyr::case_when(
        is.na(morph_path) ~ 0L,
        is.na(run.y) ~ 1L,
        !is.na(run.x) & run.x == run.y ~ 0L,
        n_morph_candidates == 1L ~ 2L,
        TRUE ~ NA_integer_
      )
    ) %>%
    dplyr::filter(!is.na(ses_score), !is.na(run_score)) %>%
    dplyr::arrange(ses_score, run_score, morph_path, .by_group = TRUE) %>%
    dplyr::slice(1) %>%
    dplyr::ungroup() %>%
    dplyr::select(tacs_path, morph_path)

  return(mapping)
}

#' Get Region Volumes from Morph File with Fallback
#'
#' @description Read morph file and return volume data, or NULL for volume=1 fallback
#'
#' @param morph_path Full path to morph file (can be NULL or NA)
#' @return Tibble with morph data (name, volume-mm3), or NULL if file not found
#' @details
#' If morph file is missing, NULL, or NA:
#' - Issues warning about BIDS spec non-conformance
#' - Returns NULL to signal volume=1 fallback
#' @export
get_region_volumes_from_morph <- function(morph_path) {

  # Check if morph_path is NULL or NA
  if (is.null(morph_path) || is.na(morph_path)) {
    warning("Derivative data does not conform to the PET Preprocessing Derivatives BIDS specification. Using volume=1 for all regions.")
    return(NULL)
  }

  # Check if file exists
  if (!file.exists(morph_path)) {
    warning("Derivative data does not conform to the PET Preprocessing Derivatives BIDS specification. Using volume=1 for all regions.")
    return(NULL)
  }

  # Read and return morph data
  tryCatch({
    readr::read_tsv(morph_path, show_col_types = FALSE)
  }, error = function(e) {
    warning(paste("Error reading morph file:", e$message, ". Using volume=1 for all regions."))
    return(NULL)
  })
}

#' Determine Varying BIDS Attributes
#'
#' @description Identifies which BIDS attributes vary across the dataset.
#'
#'   **Never use this to construct identifiers.** What varies depends on the
#'   cohort, so an identifier built from it moves when the dataset grows --
#'   the defect behind cohort-dependent measurement names. Retained for
#'   display decisions only.
#'
#' @param all_data Tibble containing BIDS attributes
#' @param candidate_attrs Vector of candidate attribute names to check
#' @return Character vector of attribute names that vary in the dataset
#' @export
determine_varying_attributes <- function(all_data, candidate_attrs = c("sub", "ses", "trc", "rec", "task", "run")) {
  varying <- purrr::map_lgl(candidate_attrs, function(attr) {
    if (!attr %in% colnames(all_data)) return(FALSE)
    # Always include 'sub' regardless of variation
    if (attr == "sub") return(TRUE)
    unique_vals <- unique(all_data[[attr]])
    unique_vals <- unique_vals[!is.na(unique_vals)]
    length(unique_vals) > 1
  })
  candidate_attrs[varying]
}

#' Reconstruct Pet Column from BIDS Attributes
#'
#' @description Builds each row's pet identifier from the given attributes,
#'   skipping the ones that are `NA` for that row. Pass every entity attribute
#'   the data carries, in BIDS filename order (`sub`, `ses`, `task`, `trc`,
#'   `rec`, `run`), so the identifier is built from the measurement's own
#'   entities and matches [pet_key()]. Passing only cohort-varying attributes
#'   makes identity depend on the cohort, which renames measurements when the
#'   dataset grows.
#'
#' @param data Tibble with BIDS attributes
#' @param varying_attrs Character vector of attribute names to build from
#' @return Tibble with reconstructed pet column
#' @export
reconstruct_pet_column <- function(data, varying_attrs) {
  if (length(varying_attrs) == 0) {
    # No varying attributes - use a default
    data %>% dplyr::mutate(pet = "pet-01")
  } else {
    data %>%
      dplyr::mutate(
        pet = purrr::pmap_chr(dplyr::select(., dplyr::all_of(varying_attrs)), function(...) {
          attrs <- list(...)
          names(attrs) <- varying_attrs
          attrs <- attrs[!is.na(attrs)]
          pairs <- paste0(names(attrs), "-", attrs)
          paste(pairs, collapse = "_")
        })
      )
  }
}

#' Calculate Segmentation Mean TAC
#'
#' @description Calculate volume-weighted mean TAC across all regions in the segmentation
#'
#' @param derivatives_folder Base path to derivatives folder
#' @param tacs_relative_path Relative path to TACs file from derivatives folder
#' @param morph_relative_path Relative path to morph file from derivatives folder
#' @param regions_for_files Filtered regions config for these specific files
#' @return Tibble with segmentation mean TAC for each time frame
#' @export
calculate_segmentation_mean_tac <- function(derivatives_folder, tacs_relative_path,
                                          morph_relative_path, regions_for_files) {
  
  # Construct full file paths
  tacs_full_path <- file.path(derivatives_folder, tacs_relative_path)
  morph_full_path <- file.path(derivatives_folder, morph_relative_path)
  
  # Validate file existence
  if (!file.exists(tacs_full_path) || !file.exists(morph_full_path)) {
    return(tibble::tibble())
  }
  
  # Read data files
  tacs_data <- tryCatch({
    readr::read_tsv(tacs_full_path, show_col_types = FALSE)
  }, error = function(e) {
    warning(paste("Error reading TACs file for segmentation mean:", e$message))
    return(NULL)
  })
  
  morph_data <- tryCatch({
    readr::read_tsv(morph_full_path, show_col_types = FALSE)
  }, error = function(e) {
    warning(paste("Error reading morph file for segmentation mean:", e$message))
    return(NULL)
  })
  
  if (is.null(tacs_data) || is.null(morph_data)) {
    return(tibble::tibble())
  }
  
  # Get all unique constituent regions from this segmentation
  all_constituent_regions <- unique(regions_for_files$ConstituentRegion)
  
  # Check which regions are available in both datasets
  available_in_tacs <- all_constituent_regions[all_constituent_regions %in% colnames(tacs_data)]
  available_in_morph <- all_constituent_regions[all_constituent_regions %in% morph_data$name]
  available_regions <- intersect(available_in_tacs, available_in_morph)
  
  if (length(available_regions) == 0) {
    warning("No regions available for segmentation mean TAC calculation")
    return(tibble::tibble())
  }
  
  # Filter morph data for available regions
  region_volumes <- morph_data %>%
    dplyr::filter(name %in% available_regions) %>%
    dplyr::select(name, `volume-mm3`)
  
  # Calculate total volume
  total_volume <- sum(region_volumes$`volume-mm3`)
  
  if (total_volume == 0) {
    warning("Total volume is zero for segmentation mean TAC calculation")
    return(tibble::tibble())
  }
  
  # Calculate volume fractions
  region_volumes <- region_volumes %>%
    dplyr::mutate(volume_fraction = `volume-mm3` / total_volume)
  
  # Initialize result with time columns
  time_cols <- c("frame_start", "frame_end")
  segmentation_mean <- tacs_data %>%
    dplyr::select(dplyr::all_of(time_cols))
  
  # Calculate volume-weighted mean TAC for each time frame
  weighted_tac_values <- rep(0, nrow(tacs_data))
  
  for (region in available_regions) {
    volume_frac <- region_volumes$volume_fraction[region_volumes$name == region]
    region_tac <- tacs_data[[region]]
    weighted_tac_values <- weighted_tac_values + (region_tac * volume_frac)
  }
  
  # Add calculated segmentation mean TAC
  segmentation_mean$seg_meanTAC <- weighted_tac_values
  
  # Calculate frame duration and midpoint for consistency
  segmentation_mean$frame_dur <- segmentation_mean$frame_end - segmentation_mean$frame_start
  segmentation_mean$frame_mid <- segmentation_mean$frame_start + 0.5 * segmentation_mean$frame_dur
  
  return(segmentation_mean)
}

#' Create Consolidated petfit Combined TACs Output
#'
#' @description Create single consolidated TSV with BIDS attributes and long-format TACs
#'
#' @param petfit_regions_files_path Path to petfit_regions_files.tsv
#' @param derivatives_folder Base path to derivatives folder
#' @param output_dir Where to save consolidated combined TACs file
#' @param bids_dir Path to BIDS directory (optional, for participant data and PET metadata)
#' @param participant_data Participant data loaded from BIDS directory (optional)
#' @param cores Number of cores to use when fitting in parallel. `1` (the
#'   default) fits sequentially.
#' @param merge_runs Whether the runs of a measurement are consecutive scans of
#'   a single injection, and should be pooled into one measurement with no `run`
#'   entity (`TRUE`, the default), or separate injections which must stay apart
#'   (`FALSE`). See [merge_tacs_runs()].
#' @return Tibble with all combined TACs data in long format with BIDS attributes
#' @export
create_petfit_combined_tacs <- function(petfit_regions_files_path, derivatives_folder, output_dir, bids_dir = NULL, participant_data = NULL, cores = 1L, merge_runs = TRUE) {
  
  # Validate inputs
  if (!file.exists(petfit_regions_files_path)) {
    stop(paste("petfit_regions_files.tsv not found:", petfit_regions_files_path))
  }
  
  if (!dir.exists(derivatives_folder)) {
    stop(paste("Derivatives folder not found:", derivatives_folder))
  }

  # Each measurement warns at most once about an assumed dose unit, so start the
  # run with a clean slate: a second run in the same session should say so again.
  reset_dose_unit_warnings()

  # Parse BIDS study data once at the beginning if BIDS directory is provided
  study_data <- NULL
  if (!is.null(bids_dir)) {
    tryCatch({
      study_data <- kinfitr::bids_parse_study(bids_dir)
      cat("Parsed BIDS study with", nrow(study_data), "measurements\n")
    }, error = function(e) {
      warning(paste("Error parsing BIDS study:", e$message))
    })
  }
  
  # Create output folder if it doesn't exist
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    cat("Created output folder:", output_dir, "\n")
  }
  
  # Read regions files mapping
  regions_files <- readr::read_tsv(petfit_regions_files_path, show_col_types = FALSE)
  
  if (nrow(regions_files) == 0) {
    stop("petfit_regions_files.tsv is empty")
  }
  
  # Group by unique TACs/morph file pairs
  file_groups <- regions_files %>%
    dplyr::group_by(tacs_filename, morph_filename) %>%
    dplyr::group_nest(.key = "regions_data")
  
  # Detect TAC units from the first TACs file for consistent metadata
  original_tac_units <- "Bq"  # Default
  if (nrow(file_groups) > 0) {
    first_tacs_file <- file_groups$tacs_filename[1]
    original_tac_units <- detect_original_tac_units(derivatives_folder, first_tacs_file)
    cat("Detected TAC units from", first_tacs_file, ":", original_tac_units, "\n")
  }
  
  # Set up parallel processing
  if (cores > 1L) {
    if (future::supportsMulticore()) {
    future::plan(future::multicore, workers = cores)
  } else {
    future::plan(future::multisession, workers = cores)
  }
    on.exit(future::plan(future::sequential), add = TRUE)
  }

  # Process all file pairs and collect results. Each group returns its data and
  # whatever it had to assume, rather than warning where it stands: this runs in
  # furrr workers, which are separate processes with their own copy of the
  # package, so a warning raised in one is deduplicated against nothing and the
  # same measurement warns once per segmentation. The parent warns, once, below.
  group_results <- furrr::future_map(1:nrow(file_groups), function(i) {
    nothing <- list(data = tibble::tibble(), assumed_dose_units_for = NA_character_)

    tacs_file <- file_groups$tacs_filename[i]
    morph_file <- file_groups$morph_filename[i]
    regions_data <- file_groups$regions_data[[i]]

    cat("Processing:", tacs_file, "\n")

    # Create segmentation value from folder and description (as shown in shiny app dropdown)
    segmentation_value <- paste0(regions_data$folder[1], ": ", regions_data$description[1])

    # Combine regions for this file pair
    combined_results <- tryCatch({
      combine_regions_from_files(derivatives_folder, tacs_file, morph_file, regions_data)
    }, error = function(e) {
      warning(paste("Error processing", tacs_file, ":", e$message))
      return(tibble::tibble())
    })

    if (nrow(combined_results) == 0) {
      return(nothing)
    }

    # Calculate segmentation mean TAC (volume-weighted mean of all regions in the segmentation)
    segmentation_mean_tac <- tryCatch({
      calculate_segmentation_mean_tac(derivatives_folder, tacs_file, morph_file, regions_data)
    }, error = function(e) {
      warning(paste("Error calculating segmentation mean TAC for", tacs_file, ":", e$message))
      return(tibble::tibble())
    })

    # Extract BIDS attributes from filename
    bids_attributes <- extract_bids_attributes_from_filename(tacs_file)

    # Extract PET metadata from _tacs.json sidecar file (preferred method)
    pet_metadata <- extract_pet_metadata_from_tacs_json(derivatives_folder, tacs_file)
    assumed_dose_units_for <- pet_metadata$AssumedDoseUnitsFor %||% NA_character_

    # If metadata not found in _tacs.json and BIDS directory available, try legacy method
    if (is.na(pet_metadata$InjectedRadioactivity) && (!is.null(study_data) || !is.null(bids_dir))) {
      legacy_metadata <- extract_pet_metadata(
        bids_dir,
        bids_attributes$sub,
        bids_attributes$ses,
        bids_attributes$trc,
        bids_attributes$rec,
        bids_attributes$task,
        bids_attributes$run,
        study_data  # Pass pre-parsed data for efficiency
      )
      # Use legacy data only if _tacs.json didn't have it
      if (!is.na(legacy_metadata$InjectedRadioactivity)) {
        pet_metadata$InjectedRadioactivity <- legacy_metadata$InjectedRadioactivity
        pet_metadata$InjectedRadioactivityUnits <- legacy_metadata$InjectedRadioactivityUnits
        # The dose came from the BIDS metadata, so any assumption about its
        # units did too.
        assumed_dose_units_for <- legacy_metadata$AssumedDoseUnitsFor %||% NA_character_
      }
    }

    # Add BIDS attributes to each row and ensure they stay as character
    # TimeZero places this measurement's runs on a common clock. The
    # derivative sidecar is preferred where a pipeline propagated it; otherwise
    # it comes from the raw _pet.json, which needs a bids_dir.
    time_zero <- pet_metadata$TimeZero %||% NA_character_
    if (is.na(time_zero)) {
      time_zero <- lookup_pet_time_zero(study_data, bids_attributes)
    }

    combined_results_with_bids <- combined_results %>%
      dplyr::mutate(
        sub = as.character(bids_attributes$sub),
        ses = as.character(bids_attributes$ses),
        trc = as.character(bids_attributes$trc),
        rec = as.character(bids_attributes$rec),
        task = as.character(bids_attributes$task),
        run = as.character(bids_attributes$run),
        time_zero = as.character(time_zero),
        segmentation = segmentation_value,
        pet = as.character(bids_attributes$pet),
        InjectedRadioactivity = as.numeric(pet_metadata$InjectedRadioactivity),
        bodyweight = as.numeric(pet_metadata$bodyweight)  # Get from _tacs.json if available
      )
    
    # Add segmentation mean TAC to the combined results
    if (nrow(segmentation_mean_tac) > 0) {
      # Add segmentation identifier to segmentation mean TAC data
      segmentation_mean_tac_with_bids <- segmentation_mean_tac %>%
        dplyr::mutate(
          segmentation = segmentation_value,
          pet = as.character(bids_attributes$pet)
        )

      # Join segmentation mean TAC with combined results
      combined_results_with_bids <- combined_results_with_bids %>%
        dplyr::left_join(
          segmentation_mean_tac_with_bids %>%
            dplyr::select(frame_start, frame_end, segmentation, pet, seg_meanTAC),
          by = c("frame_start", "frame_end", "segmentation", "pet")
        )
    } else {
      # Add seg_meanTAC column with NA values if calculation failed
      combined_results_with_bids <- combined_results_with_bids %>%
        dplyr::mutate(seg_meanTAC = NA_real_)
    }
    
    # Add participant data if available
    weight_column_found <- NULL
    if (!is.null(participant_data) && !is.null(participant_data$data)) {
      # Check for weight column with multiple possible names
      participant_columns_to_add <- participant_data$data
      possible_weight_columns <- c("bodyweight", "body_weight", "BodyWeight", "weight", "Weight", "Body_Weight")

      # Find the first matching weight column
      for (col_name in possible_weight_columns) {
        if (col_name %in% colnames(participant_columns_to_add)) {
          weight_column_found <- col_name
          break
        }
      }

      if (!is.null(weight_column_found)) {
        # Use _tacs.json bodyweight as primary, participants.tsv as fallback
        # Convert weight column to numeric (handles "n/a" or other non-numeric values as NA)
        combined_results_with_bids <- combined_results_with_bids %>%
          dplyr::left_join(participant_columns_to_add, by = "sub") %>%
          dplyr::mutate(bodyweight = dplyr::coalesce(bodyweight, as.numeric(.data[[weight_column_found]]))) %>%
          dplyr::select(-dplyr::all_of(weight_column_found))  # Remove the participant weight column, keep bodyweight
      } else {
        # Keep our bodyweight column (from _tacs.json) and add other participant data
        combined_results_with_bids <- combined_results_with_bids %>%
          dplyr::left_join(participant_columns_to_add, by = "sub")
      }
    }

    # Determine participant columns (excluding sub and any weight columns found)
    participant_columns <- if (!is.null(participant_data) && !is.null(participant_data$data)) {
      exclude_cols <- c("sub")
      if (!is.null(weight_column_found)) {
        exclude_cols <- c(exclude_cols, weight_column_found)
      }
      setdiff(colnames(participant_data$data), exclude_cols)
    } else {
      character(0)
    }

    # Column order: sub, ses, trc, rec, task, run, segmentation, pet, InjectedRadioactivity, bodyweight, [participant_columns], region, volume_mm3, frame_*, seg_meanTAC, TAC
    base_columns <- c("sub", "ses", "trc", "rec", "task", "run", "time_zero", "segmentation", "pet", "InjectedRadioactivity", "bodyweight")
    frame_columns <- c("frame_start", "frame_end", "frame_dur", "frame_mid")
    end_columns <- c("region", "volume_mm3", frame_columns, "seg_meanTAC", "TAC")

    column_order <- c(base_columns, participant_columns, end_columns)

    combined_results_with_bids <- combined_results_with_bids %>%
      dplyr::rename(region = name, volume_mm3 = `volume-mm3`) %>%
      dplyr::select(dplyr::all_of(column_order[column_order %in% colnames(.)]))  # Only select columns that exist

    return(list(data = combined_results_with_bids,
                assumed_dose_units_for = assumed_dose_units_for))
  }, .options = furrr::furrr_options(seed = TRUE))

  # One warning per measurement, in the process the user is watching.
  assumed_measurements <- unique(stats::na.omit(
    purrr::map_chr(group_results, ~.x$assumed_dose_units_for %||% NA_character_)
  ))
  purrr::walk(assumed_measurements, warn_assumed_dose_units)

  all_combined_data <- dplyr::bind_rows(purrr::map(group_results, "data"))

  if (nrow(all_combined_data) == 0) {
    warning("No regions were successfully combined across all files")
    return(tibble::tibble())
  }

  # Merging happens before the identifiers are built, because that is all a
  # merge is: the rows of two runs are already pooled in this long-format
  # table, and dropping `run` from what identifies a measurement is what joins
  # them into one. The checks live in merge_tacs_runs().
  runs_merged <- FALSE
  if (isTRUE(merge_runs)) {
    merge_result <- merge_tacs_runs(all_combined_data)
    all_combined_data <- merge_result$data
    runs_merged <- isTRUE(merge_result$merged)
    cat(paste0(merge_result$messages, collapse = "\n"), "\n")
  } else {
    cat("Run merging is off: each run is kept as a separate measurement.\n")
  }

  # TimeZero exists only to align runs, and has no place in the output. The
  # merge drops it; this covers the case where no merge ran.
  all_combined_data <- dplyr::select(all_combined_data,
                                     -dplyr::any_of("time_zero"))

  # Build each measurement's identifier from its own entities -- all of them,
  # in the BIDS filename order pet_key() uses. Building it from only the
  # attributes that vary across the current dataset made identity depend on
  # the cohort: adding the first retest scan to a single-session study renamed
  # every existing measurement and orphaned the files written under the old
  # names.
  entity_attrs <- intersect(c("sub", "ses", "task", "trc", "rec", "run"),
                            colnames(all_combined_data))
  cat("Constructing pet identifiers from each measurement's own entities:",
      paste(entity_attrs, collapse = ", "), "\n")
  all_combined_data <- reconstruct_pet_column(all_combined_data, entity_attrs)

  # Convert TAC data from original units to kBq for standardization
  cat("Converting TAC data from", original_tac_units, "to kBq\n")
  all_combined_data <- all_combined_data %>%
    dplyr::mutate(
      TAC = kinfitr::unit_convert(TAC, from_units = original_tac_units, to_units = "kBq"),
      seg_meanTAC = kinfitr::unit_convert(seg_meanTAC, from_units = original_tac_units, to_units = "kBq")
    )
  
  # Save single consolidated TSV
  output_file <- file.path(output_dir, "desc-combinedregions_tacs.tsv")
  
  readr::write_tsv(all_combined_data, output_file)
  
  # Create JSON description file if participant data is available
  if (!is.null(participant_data)) {
    if ("InjectedRadioactivity" %in% colnames(all_combined_data)) {
      create_combined_tacs_json_description(
        participants_metadata = participant_data$metadata, 
        injected_radioactivity_units = "kBq",  # Always kBq since we standardize to this unit
        original_tac_units = "kBq",  # TAC units are now standardized to kBq
        output_dir = output_dir,
        merged_runs = runs_merged
      )
    }
  } else {
    # Create JSON even without participant data, using kBq units
    create_combined_tacs_json_description(
      participants_metadata = NULL,
      injected_radioactivity_units = "kBq", 
      original_tac_units = "kBq",
      output_dir = output_dir,
      merged_runs = runs_merged
    )
  }
  
  cat("\n=== Consolidated Output Summary ===\n")
  cat("Total rows:", nrow(all_combined_data), "\n")
  cat("Total regions:", length(unique(all_combined_data$region)), "\n")
  cat("Unique subjects:", length(unique(all_combined_data$sub)), "\n")
  cat("Unique sessions:", length(unique(all_combined_data$ses)), "\n")
  if (!is.null(participant_data)) {
    cat("Participant data integrated: YES\n")
    cat("Participant columns:", paste(setdiff(colnames(participant_data$data), "sub"), collapse = ", "), "\n")
  } else {
    cat("Participant data integrated: NO\n")
  }
  cat("Output file:", output_file, "\n")
  
  return(all_combined_data)
}
#' Does This Dataset Have More Than One Run per Measurement?
#'
#' @description Report whether any measurement in a derivatives folder is
#'   represented by more than one run.
#'
#'   Used to decide whether the run merging option is worth putting in front of
#'   a user. The mere presence of a `run` entity is not enough: a dataset
#'   labelled `run-01` throughout has nothing to merge, so the question is
#'   whether any one measurement has several runs.
#'
#'   Read from the filenames rather than from the TACs themselves, so it costs
#'   a directory listing and can be answered before the app opens.
#'
#' @param derivatives_folder Character string path to the derivatives folder.
#' @return `TRUE` when at least one measurement has two or more runs.
#' @export
#'
#' @examples
#' \dontrun{
#' dataset_has_multiple_runs("/path/to/derivatives")
#' }
dataset_has_multiple_runs <- function(derivatives_folder) {

  if (is.null(derivatives_folder) || !dir.exists(derivatives_folder)) {
    return(FALSE)
  }

  tacs_paths <- list.files(derivatives_folder, pattern = "_tacs\\.tsv$",
                           recursive = TRUE)
  tacs_paths <- tacs_paths[!stringr::str_detect(
    tacs_paths, "desc-combinedregions_tacs\\.tsv$")]

  if (length(tacs_paths) == 0) {
    return(FALSE)
  }

  runs <- stringr::str_match(basename(tacs_paths), "_run-([a-zA-Z0-9]+)")[, 2]

  if (all(is.na(runs))) {
    return(FALSE)
  }

  # Everything but the run entity identifies the measurement. The whole
  # relative path is used, so the same measurement under two pipelines or two
  # segmentations counts separately rather than colliding.
  keys <- stringr::str_remove(tacs_paths, "_run-[a-zA-Z0-9]+")

  distinct_runs <- tapply(runs, keys, function(x) {
    length(unique(x[!is.na(x)]))
  })

  any(distinct_runs > 1, na.rm = TRUE)
}

#' Find Folders Containing TACs Files
#'
#' @description Identifies directories that contain *_tacs.tsv files
#'
#' @param derivatives_folder Character string path to the derivatives folder
#' @return Character vector of directory paths containing *_tacs.tsv files
#' @export
find_tacs_folders <- function(derivatives_folder) {
  
  # Find all subdirectories in the derivatives folder
  subdirs <- list.dirs(derivatives_folder, recursive = FALSE, full.names = TRUE)
  
  # Function to check if a directory contains *_tacs.tsv files (excluding combined files)
  has_tacs_files <- function(dir_path) {
    tacs_files <- list.files(dir_path, pattern = "*_tacs\\.tsv$", recursive = TRUE)
    # Exclude combined TACs files
    tacs_files <- tacs_files[!grepl("desc-combinedregions_tacs\\.tsv$", tacs_files)]
    return(length(tacs_files) > 0)
  }
  
  # Filter directories that contain *_tacs.tsv files
  valid_dirs <- subdirs[purrr::map_lgl(subdirs, has_tacs_files)]
  
  if (length(valid_dirs) == 0) {
    stop("No directories with *_tacs.tsv files found in ", derivatives_folder)
  }
  
  return(valid_dirs)
}

#' Summarise TACs File Descriptions
#'
#' @description Process and summarize TACs files descriptions, filtering for files with seg or label attributes
#'
#' @param dir_path Character string path to directory containing *_tacs.tsv files
#' @return Data frame with region configurations from the directory (only files with seg or label)
#' @export
summarise_tacs_descriptions <- function(dir_path) {

  # Get all *_tacs.tsv files in this directory (excluding combined files)
  tacs_files <- list.files(dir_path, pattern = "*_tacs\\.tsv$",
                           recursive = TRUE, full.names = TRUE)
  # Exclude combined TACs files
  tacs_files <- tacs_files[!grepl("desc-combinedregions_tacs\\.tsv$", tacs_files)]

  if (length(tacs_files) == 0) {
    return(NULL)
  }

  # These are derived TACs files, not PET images, so the derivative parser
  # applies.
  parsed_files <- kinfitr::bids_parse_derivatives(dir_path)

  unnested_tacfiledata <- parsed_files %>%
    dplyr::rename(measurement = "suffix") %>%
    dplyr::filter(measurement=="tacs") %>%
    # Only the entities describing the *region definition* belong here: seg,
    # label, desc and the like. The selectors are dropped deliberately, since
    # including them would put the subject and session into every region
    # description.
    dplyr::select(-dplyr::any_of(c("path_absolute", "path", "extension",
                                   "measurement", "source_key", "artifact_key",
                                   "analysis_scope_key",
                                   "sub", "ses", "task", "trc", "rec", "run"))) %>%
    dplyr::distinct()

  # Filter for files with seg or label attributes (silently exclude others)
  # kinfitr::bids_parse_derivatives() provides seg and label columns if present
  if ("seg" %in% colnames(unnested_tacfiledata) || "label" %in% colnames(unnested_tacfiledata)) {
    if (!"seg" %in% colnames(unnested_tacfiledata)) {
      unnested_tacfiledata$seg <- NA_character_
    }
    if (!"label" %in% colnames(unnested_tacfiledata)) {
      unnested_tacfiledata$label <- NA_character_
    }

    unnested_tacfiledata <- unnested_tacfiledata %>%
      dplyr::filter(!is.na(seg) | !is.na(label))
  } else {
    # No seg or label columns found - return empty
    return(tibble::tibble(description = character(0)))
  }

  # Return empty if no files match
  if (nrow(unnested_tacfiledata) == 0) {
    return(tibble::tibble(description = character(0)))
  }

  create_bids_key_value_pairs(unnested_tacfiledata,
                              colnames(unnested_tacfiledata))

}

create_tacs_list <- function(derivatives_folder) {

  # Find TACs folders and create descriptions
  tacs_folders <- tibble::tibble(
    path = find_tacs_folders(derivatives_folder)) %>%
    dplyr::mutate(foldername = basename(path)) %>%
    dplyr::mutate(
      descriptions = purrr::map(path, summarise_tacs_descriptions),
      # Pre-compute TACs-morph mappings using BIDS matching rules
      mappings = purrr::map(path, create_tacs_morph_mapping)
    ) %>%
    tidyr::unnest(descriptions)

  # Expand mappings and join with descriptions
  tacs_with_mappings <- tacs_folders %>%
    # Unnest the mappings to get tacs_path and morph_path
    tidyr::unnest(mappings) %>%
    # Extract BIDS attributes from tacs_path to match with description
    dplyr::mutate(
      tacs_attrs = purrr::map(tacs_path, extract_bids_attributes_from_filename)
    ) %>%
    tidyr::unnest(tacs_attrs) %>%
    # Create description from attributes (excluding identifiers and desc for matching)
    dplyr::mutate(
      desc_from_path = create_bids_key_value_pairs(
        dplyr::pick(dplyr::everything()),
        setdiff(colnames(dplyr::pick(dplyr::everything())), c("path", "foldername", "description", "mappings", "tacs_path", "morph_path", "tacs_attrs", "sub", "ses", "trc", "rec", "task", "run", "pet", "desc_from_path"))
      )$description
    ) %>%
    # Join with original descriptions
    dplyr::filter(desc_from_path == description) %>%
    dplyr::select(path, foldername, description, tacs_path, morph_path) %>%
    dplyr::mutate(tacs_filedescription = paste0(foldername, ": ", description))

  # Sort alphabetically by display description for organized dropdown
  tacs_with_mappings <- tacs_with_mappings %>%
    dplyr::arrange(tacs_filedescription)

  return(tacs_with_mappings)
}


create_bids_key_value_pairs <- function(data, columns) {
  # Prioritize seg/label first, then alphabetically sort the rest
  priority_cols <- c("seg", "label")
  priority_present <- intersect(priority_cols, columns)
  other_cols <- setdiff(columns, priority_cols)
  other_cols <- sort(other_cols)  # Alphabetically sort remaining columns
  ordered_columns <- c(priority_present, other_cols)

  data %>%
    dplyr::mutate(
      key_value_pairs = apply(
        data[ordered_columns], 1,
        function(row) {
          # Create key-value pairs only for non-NA values
          pairs <- paste(ordered_columns, row, sep = "-")
          non_na_pairs <- pairs[!is.na(row)]
          paste(non_na_pairs, collapse = "_")
        }
      )
    ) %>%
    dplyr::select(description=key_value_pairs)
}

#' Interpret BIDS Key-Value Pairs
#'
#' @description Parse key-value pair strings back into tibble columns
#'
#' @param key_value_strings Character vector of key-value pair strings
#' @return Tibble with parsed columns
#' @export
interpret_bids_key_value_pairs <- function(key_value_strings) {
  
  if (length(key_value_strings) == 0) {
    return(tibble::tibble())
  }
  
  # Parse each key-value string
  parsed_list <- purrr::map(key_value_strings, function(kv_string) {
    
    if (is.na(kv_string) || kv_string == "") {
      return(list())
    }
    
    # Split by underscore to get individual pairs
    pairs <- stringr::str_split(kv_string, "_")[[1]]
    
    # Parse each pair (format: "key-value")
    result <- list()
    for (pair in pairs) {
      if (stringr::str_detect(pair, "-")) {
        parts <- stringr::str_split(pair, "-", n = 2)[[1]]
        if (length(parts) == 2) {
          key <- parts[1]
          value <- parts[2]
          result[[key]] <- value
        }
      }
    }
    
    return(result)
  })
  
  # Get all unique column names
  all_columns <- unique(unlist(purrr::map(parsed_list, names)))
  
  if (length(all_columns) == 0) {
    return(tibble::tibble())
  }
  
  # Create tibble with all columns
  result_data <- purrr::map_dfc(all_columns, function(col) {
    values <- purrr::map_chr(parsed_list, function(row) {
      if (col %in% names(row)) {
        return(row[[col]])
      } else {
        return(NA_character_)
      }
    })
    
    # Create a named list for this column
    stats::setNames(list(values), col)
  })
  
  return(result_data)
}

#' Load Participant Data from BIDS Directory
#'
#' @description Load and process participants.tsv and participants.json files
#'
#' @param bids_dir Path to BIDS directory
#' @return List with participant data and metadata, or NULL if files don't exist
#' @export
load_participant_data <- function(bids_dir) {
  
  if (is.null(bids_dir) || !dir.exists(bids_dir)) {
    return(NULL)
  }
  
  participants_tsv <- file.path(bids_dir, "participants.tsv")
  participants_json <- file.path(bids_dir, "participants.json")
  
  # Check if participants.tsv exists
  if (!file.exists(participants_tsv)) {
    return(NULL)
  }
  
  # Load participants.tsv
  participants_data <- tryCatch({
    readr::read_tsv(participants_tsv, show_col_types = FALSE)
  }, error = function(e) {
    warning(paste("Error reading participants.tsv:", e$message))
    return(NULL)
  })
  
  if (is.null(participants_data) || nrow(participants_data) == 0) {
    return(NULL)
  }
  
  # Transform participant_id column to sub column
  if ("participant_id" %in% colnames(participants_data)) {
    participants_data <- participants_data %>%
      dplyr::mutate(sub = stringr::str_replace(participant_id, "^sub-", "")) %>%
      dplyr::select(-participant_id)
  } else {
    warning("participants.tsv does not contain participant_id column")
    return(NULL)
  }
  
  # Load participants.json if it exists
  participants_metadata <- NULL
  if (file.exists(participants_json)) {
    participants_metadata <- tryCatch({
      jsonlite::fromJSON(participants_json)
    }, error = function(e) {
      warning(paste("Error reading participants.json:", e$message))
      return(NULL)
    })
  }
  
  return(list(
    data = participants_data,
    metadata = participants_metadata
  ))
}

#' Default units for an unlabelled injected radioactivity
#'
#' @description
#' BIDS recommends MBq for `InjectedRadioactivity`, and it is what most
#' converters write, so an `InjectedRadioactivity` with no
#' `InjectedRadioactivityUnits` beside it is read as MBq. This is an assumption
#' rather than a reading, so it is made in one place, and whoever makes it warns.
#'
#' The alternative — discarding an unlabelled dose — would silently drop SUV for
#' datasets whose converter simply omitted the field. The alternative petfit used
#' to take was worse still: the value was passed through unconverted and then
#' labelled kBq, so a dose in MBq was recorded as though it were a thousand times
#' smaller.
#'
#' @return The assumed units, `"MBq"`.
#' @keywords internal
assumed_injected_radioactivity_units <- function() "MBq"

# Warned-about measurements, so that a cohort with one region definition file
# per segmentation does not raise the same warning four times over for every
# measurement and bury it under R's "There were 50 or more warnings".
.petfit_dose_unit_warnings <- new.env(parent = emptyenv())

#' Forget which measurements have already warned about assumed dose units
#'
#' @description
#' The warning about an assumed `InjectedRadioactivityUnits` is raised once per
#' measurement. Region definition calls this at the start of a run so that a
#' second run in the same session warns again rather than staying silent.
#'
#' @return Invisibly `NULL`.
#' @keywords internal
reset_dose_unit_warnings <- function() {
  rm(list = ls(.petfit_dose_unit_warnings), envir = .petfit_dose_unit_warnings)
  invisible(NULL)
}

# Warn once per measurement, naming what the assumption was made about, so that
# it can be traced back rather than appearing as a bare note.
warn_assumed_dose_units <- function(what) {
  key <- paste0("m:", what)
  if (!is.null(.petfit_dose_unit_warnings[[key]])) {
    return(invisible(FALSE))
  }
  assign(key, TRUE, envir = .petfit_dose_unit_warnings)

  warning(
    "No InjectedRadioactivityUnits found for ", what, ". Assuming ",
    assumed_injected_radioactivity_units(),
    ", which is what BIDS recommends and what most converters write. ",
    "Set InjectedRadioactivityUnits in the metadata if the dose is in other ",
    "units: SUV will be wrong by whatever factor separates them. SUVR is ",
    "unaffected, because the dose cancels in the ratio.",
    call. = FALSE
  )
  invisible(TRUE)
}

#' Extract PET Metadata from TACs JSON Sidecar
#'
#' @description Extract InjectedRadioactivity and body_weight from _tacs.json sidecar file
#'
#' @param derivatives_folder Base derivatives folder
#' @param tacs_relative_path Relative path to TACs file from derivatives folder
#' @return List with InjectedRadioactivity, InjectedRadioactivityUnits, and bodyweight (NA if not found)
#' @export
extract_pet_metadata_from_tacs_json <- function(derivatives_folder, tacs_relative_path) {

  # Convert TSV filename to JSON filename for TACs sidecar file
  json_relative_path <- stringr::str_replace(tacs_relative_path, "\\.tsv$", ".json")
  json_full_path <- file.path(derivatives_folder, json_relative_path)

  # Default values
  result <- list(
    InjectedRadioactivity = NA_real_,
    InjectedRadioactivityUnits = NA_character_,
    # The measurement whose dose units were assumed, for the caller to warn
    # about once, or NA where nothing was assumed.
    AssumedDoseUnitsFor = NA_character_,
    bodyweight = NA_real_,
    # The clock time the frame times are relative to, for placing the runs of
    # one measurement on a common clock. Most pipelines do not propagate it
    # into their _tacs.json, in which case it is read from the raw _pet.json.
    TimeZero = NA_character_
  )

  if (!file.exists(json_full_path)) {
    return(result)
  }

  # Try to read the TACs JSON sidecar file
  tryCatch({
    json_data <- jsonlite::fromJSON(json_full_path)

    # Extract InjectedRadioactivity
    if ("InjectedRadioactivity" %in% names(json_data)) {
      result$InjectedRadioactivity <- as.numeric(json_data$InjectedRadioactivity)
    }

    # Extract InjectedRadioactivityUnits
    if ("InjectedRadioactivityUnits" %in% names(json_data)) {
      result$InjectedRadioactivityUnits <- as.character(json_data$InjectedRadioactivityUnits)
    }

    # Extract body_weight (if present)
    if ("body_weight" %in% names(json_data)) {
      result$bodyweight <- as.numeric(json_data$body_weight)
    }

    if ("TimeZero" %in% names(json_data)) {
      result$TimeZero <- as.character(json_data$TimeZero)[1]
    }

    # An unlabelled dose is assumed to be MBq rather than passed through as
    # though it were already kBq, which would understate it a thousandfold.
    if (!is.na(result$InjectedRadioactivity) &&
        (is.na(result$InjectedRadioactivityUnits) ||
         !nzchar(result$InjectedRadioactivityUnits))) {
      # Name the measurement, not the region definition file: the same dose is
      # read once per segmentation, and it is the measurement that lacks units.
      # The assumption is reported back rather than warned about here, because
      # this runs in a furrr worker, where a warning is neither deduplicated
      # against the other segmentations nor guaranteed to reach the user.
      result$AssumedDoseUnitsFor <-
        stringr::str_remove(basename(json_full_path), "_(desc|label|seg|space)-.*$")
      result$InjectedRadioactivityUnits <- assumed_injected_radioactivity_units()
    }

    # Convert InjectedRadioactivity to kBq if units are different
    if (!is.na(result$InjectedRadioactivity) && !is.na(result$InjectedRadioactivityUnits) &&
        result$InjectedRadioactivityUnits != "kBq") {
      tryCatch({
        result$InjectedRadioactivity <- kinfitr::unit_convert(
          result$InjectedRadioactivity,
          result$InjectedRadioactivityUnits,
          "kBq"
        )
        result$InjectedRadioactivityUnits <- "kBq"
      }, error = function(e) {
        warning(paste("Could not convert injected radioactivity from",
                     result$InjectedRadioactivityUnits, "to kBq:", e$message))
      })
    }

  }, error = function(e) {
    warning(paste("Error reading _tacs.json file:", e$message))
  })

  return(result)
}

#' Look Up a Measurement's TimeZero in a Parsed BIDS Study
#'
#' @description Read the BIDS `TimeZero` of one acquisition from the raw
#'   `_pet.json` metadata that [kinfitr::bids_parse_study()] has already
#'   collected, matching on whichever entities the measurement carries.
#'
#'   `TimeZero` is what lets the runs of one measurement be placed on a common
#'   clock. It lives in the raw sidecars, and the preprocessing pipelines
#'   generally do not carry it into their `_tacs.json`, so a run given only a
#'   derivatives directory usually has none -- which is handled by taking the
#'   frame times as already shared. See [merge_tacs_runs()].
#'
#' @param study_data Parsed study, as returned by [kinfitr::bids_parse_study()],
#'   or `NULL`.
#' @param attributes One row of BIDS attributes, as returned by
#'   [extract_bids_attributes_from_filename()].
#' @return The `TimeZero` string, or `NA_character_` when it cannot be found.
#' @export
lookup_pet_time_zero <- function(study_data, attributes) {

  if (is.null(study_data) || nrow(study_data) == 0) {
    return(NA_character_)
  }

  matching <- dplyr::ungroup(study_data)

  # Every entity the measurement names and the study carries has to agree. An
  # entity the filename is silent about is not filtered on, so a study which
  # records more entities than the derivative filename does still matches.
  for (entity in c("sub", "ses", "task", "trc", "rec", "run")) {

    wanted <- attributes[[entity]]
    if (is.null(wanted) || length(wanted) == 0 || is.na(wanted[1]) ||
        !nzchar(as.character(wanted[1])) ||
        !entity %in% colnames(matching)) {
      next
    }

    matching <- matching[!is.na(matching[[entity]]) &
                           as.character(matching[[entity]]) ==
                           as.character(wanted[1]), , drop = FALSE]
  }

  if (nrow(matching) == 0) {
    return(NA_character_)
  }

  pet_info <- matching$petinfo[[1]]

  if (is.null(pet_info) || length(pet_info) == 0 ||
      !"TimeZero" %in% names(pet_info)) {
    return(NA_character_)
  }

  time_zero <- pet_info$TimeZero
  if (length(time_zero) == 0 || is.na(time_zero[1])) {
    return(NA_character_)
  }

  as.character(time_zero[1])
}

#' Extract PET Metadata from BIDS Directory using kinfitr
#'
#' @description Extract InjectedRadioactivity from matching PET measurements using kinfitr::bids_parse_study
#' @note DEPRECATED: Use extract_pet_metadata_from_tacs_json() instead for derivatives-based workflows
#'
#' @param bids_dir Path to BIDS directory (can be NULL if study_data provided)
#' @param sub Subject ID (without 'sub-' prefix)
#' @param ses Session ID (without 'ses-' prefix, can be NA)
#' @param trc Tracer ID (can be NA)
#' @param rec Reconstruction ID (can be NA)
#' @param task Task ID (can be NA)
#' @param run Run ID (can be NA)
#' @param study_data Pre-parsed BIDS study data (optional, for efficiency)
#' @return List with InjectedRadioactivity and units, or NA values if not found
#' @export
extract_pet_metadata <- function(bids_dir, sub, ses = NA, trc = NA, rec = NA, task = NA, run = NA, study_data = NULL) {
  
  if (is.na(sub)) {
    return(list(InjectedRadioactivity = NA_real_, InjectedRadioactivityUnits = NA_character_))
  }
  
  # Use pre-parsed study data if available, otherwise parse BIDS directory
  tryCatch({
    if (is.null(study_data)) {
      if (is.null(bids_dir) || !dir.exists(bids_dir)) {
        return(list(InjectedRadioactivity = NA_real_, InjectedRadioactivityUnits = NA_character_))
      }
      study_data <- kinfitr::bids_parse_study(bids_dir)
    }
    
    if (is.null(study_data) || nrow(study_data) == 0) {
      return(list(InjectedRadioactivity = NA_real_, InjectedRadioactivityUnits = NA_character_))
    }
    
    # Filter for matching measurement
    # Note: kinfitr uses different column names and may not have all BIDS entities
    matching_measurements <- study_data %>%
      dplyr::filter(sub == !!sub)
    
    # Filter by session if provided and column exists
    if (!is.na(ses) && ses != "" && "ses" %in% colnames(matching_measurements)) {
      matching_measurements <- matching_measurements %>%
        dplyr::filter(ses == !!ses)
    }
    
    # Filter by task if provided and column exists  
    if (!is.na(task) && task != "" && "task" %in% colnames(matching_measurements)) {
      matching_measurements <- matching_measurements %>%
        dplyr::filter(task == !!task)
    }
    
    # Filter by tracer if provided and column exists
    if (!is.na(trc) && trc != "" && "trc" %in% colnames(matching_measurements)) {
      matching_measurements <- matching_measurements %>%
        dplyr::filter(trc == !!trc)
    }
    
    # Filter by reconstruction if provided and column exists
    if (!is.na(rec) && rec != "" && "rec" %in% colnames(matching_measurements)) {
      matching_measurements <- matching_measurements %>%
        dplyr::filter(rec == !!rec)
    }
    
    # Filter by run if provided and column exists
    if (!is.na(run) && run != "" && "run" %in% colnames(matching_measurements)) {
      matching_measurements <- matching_measurements %>%
        dplyr::filter(run == !!run)
    }
    
    if (nrow(matching_measurements) == 0) {
      return(list(InjectedRadioactivity = NA_real_, InjectedRadioactivityUnits = NA_character_))
    }
    
    # Get the first matching measurement's PET info
    pet_info <- matching_measurements$petinfo[[1]]
    
    if (is.null(pet_info) || length(pet_info) == 0) {
      return(list(InjectedRadioactivity = NA_real_, InjectedRadioactivityUnits = NA_character_))
    }
    
    # Extract InjectedRadioactivity and units
    injected_radioactivity <- if ("InjectedRadioactivity" %in% names(pet_info)) {
      pet_info$InjectedRadioactivity
    } else {
      NA_real_
    }
    
    injected_radioactivity_units <- if ("InjectedRadioactivityUnits" %in% names(pet_info)) {
      pet_info$InjectedRadioactivityUnits
    } else {
      NA_character_
    }
    
    # As in the sidecar path: an unlabelled dose is assumed to be MBq, and the
    # assumption is reported back for the caller to warn about once.
    assumed_dose_units_for <- NA_character_
    if (!is.na(injected_radioactivity) &&
        (is.na(injected_radioactivity_units) || !nzchar(injected_radioactivity_units))) {
      assumed_dose_units_for <- paste0("sub-", sub,
                                       if (!is.na(ses)) paste0("_ses-", ses) else "")
      injected_radioactivity_units <- assumed_injected_radioactivity_units()
    }

    # Convert to kBq if units are different and radioactivity is not NA
    if (!is.na(injected_radioactivity) && !is.na(injected_radioactivity_units) && injected_radioactivity_units != "kBq") {
      tryCatch({
        injected_radioactivity <- kinfitr::unit_convert(injected_radioactivity, injected_radioactivity_units, "kBq")
        injected_radioactivity_units <- "kBq"
      }, error = function(e) {
        warning(paste("Could not convert injected radioactivity from", injected_radioactivity_units, "to kBq:", e$message))
      })
    }
    
    return(list(
      InjectedRadioactivity = injected_radioactivity,
      InjectedRadioactivityUnits = injected_radioactivity_units,
      AssumedDoseUnitsFor = assumed_dose_units_for
    ))
    
  }, error = function(e) {
    warning(paste("Error parsing BIDS study for PET metadata:", e$message))
    return(list(InjectedRadioactivity = NA_real_, InjectedRadioactivityUnits = NA_character_))
  })
}

#' Detect TAC Radioactivity Units from Original TACs JSON Sidecar
#'
#' @description Helper function to detect radioactivity units from TACs JSON sidecar files
#'
#' @param derivatives_folder Base derivatives folder
#' @param tacs_relative_path Relative path to TACs file  
#' @return String with radioactivity units (e.g., "Bq", "kBq") or "Bq" as default
detect_original_tac_units <- function(derivatives_folder, tacs_relative_path) {
  # Convert TSV filename to JSON filename for TAC sidecar file
  json_relative_path <- stringr::str_replace(tacs_relative_path, "\\.tsv$", ".json")
  json_full_path <- file.path(derivatives_folder, json_relative_path)
  
  if (file.exists(json_full_path)) {
    # Try to read the TAC JSON sidecar file
    tryCatch({
      json_data <- jsonlite::fromJSON(json_full_path)
      # Look for radioactivity column units (e.g., "Bq/mL", "kBq/mL")
      if ("radioactivity" %in% names(json_data) && "Units" %in% names(json_data$radioactivity)) {
        # Extract just the radioactivity part before the "/" using kinfitr function
        full_units <- json_data$radioactivity$Units
        rad_units <- kinfitr::get_units_radioactivity(full_units)$rad
        return(rad_units)
      }
    }, error = function(e) {
      # If JSON reading fails, return default
      return("Bq")
    })
  }
  
  # Default: assume Bq if no JSON metadata found
  return("Bq")
}

#' Create JSON Description File for Combined TACs
#'
#' @description Generate JSON metadata file describing columns in combined TACs file
#'
#' @param participants_metadata Participants metadata from participants.json (can be NULL)
#' @param injected_radioactivity_units Units for InjectedRadioactivity (can be NA)
#' @param original_tac_units Original radioactivity units detected from source TACs files (default "Bq")
#' @param output_dir Directory to save the JSON file
#' @param merged_runs Whether the runs of each measurement were **actually**
#'   pooled into one measurement -- not merely whether merging was asked for.
#'   Recorded in the sidecar so that a later step can tell whether an empty
#'   `run` column means "merged" or "no runs in this dataset".
#' @return Path to created JSON file
#' @export
create_combined_tacs_json_description <- function(participants_metadata, injected_radioactivity_units, original_tac_units = "Bq", output_dir, merged_runs = TRUE) {
  
  # Base column descriptions (following kinfitr BIDS pattern, excluding acq as it's deprecated)
  base_descriptions <- list(
    "sub" = list("Description" = "Subject identifier (numeric part only, without 'sub-' prefix)"),
    "ses" = list("Description" = "Session identifier (without 'ses-' prefix)"),
    "trc" = list("Description" = "Tracer identifier"),
    "rec" = list("Description" = "Reconstruction identifier"),
    "task" = list("Description" = "Task identifier"),
    "run" = list("Description" = if (isTRUE(merged_runs)) {
      paste("Run identifier. Empty because the runs of each measurement were",
            "merged into a single measurement, so no run identifies it.")
    } else {
      "Run identifier"
    }),
    "segmentation" = list("Description" = "Segmentation identifier from preprocessing pipeline"),
    "pet" = list("Description" = "PET measurement identifier"),
    "bodyweight" = list("Description" = "Body weight of participant for SUV calculation", "Units" = "kg"),
    "region" = list("Description" = "Brain region name (combined from constituent regions)"),
    "volume_mm3" = list("Description" = "Total volume of combined regions", "Units" = "mm3"),
    "frame_start" = list("Description" = "Frame start time", "Units" = "seconds"),
    "frame_end" = list("Description" = "Frame end time", "Units" = "seconds"),
    "frame_dur" = list("Description" = "Frame duration", "Units" = "seconds"),
    "frame_mid" = list("Description" = "Frame midpoint time", "Units" = "seconds"),
    "seg_meanTAC" = list("Description" = "Volume-weighted mean TAC across all regions within the segmentation", "Units" = paste0(original_tac_units, "/mL")),
    "TAC" = list("Description" = "Time Activity Curve value (volume-weighted average)", "Units" = paste0(original_tac_units, "/mL"))
  )
  
  # Add participant columns if available
  combined_descriptions <- base_descriptions
  if (!is.null(participants_metadata)) {
    # Add descriptions from participants.json (excluding participant_id)
    for (col_name in names(participants_metadata)) {
      if (col_name != "participant_id") {
        combined_descriptions[[col_name]] <- participants_metadata[[col_name]]
      }
    }
  }
  
  # Add InjectedRadioactivity description (standardized to kBq)
  injected_desc <- list(
    "Description" = "Injected radioactivity at time of injection (converted to kBq from original units if necessary)",
    "Units" = "kBq"
  )
  combined_descriptions[["InjectedRadioactivity"]] <- injected_desc
  
  # Add time and radioactivity metadata structures for report templates
  combined_descriptions[["time"]] <- list("Units" = "s")
  combined_descriptions[["radioactivity"]] <- list("Units" = paste0(original_tac_units, "/mL"))

  # Which version of petfit built these TACs. The measurement identifiers in the
  # `pet` column are constructed here, and how they are constructed has changed
  # between versions, so every later step needs to know whether the file it is
  # reading predates its own expectations.
  combined_descriptions[["GeneratedBy"]] <- list(petfit_generated_by())

  # Whether the runs of each measurement were pooled. Without this, an empty
  # `run` column is ambiguous: a dataset with no runs at all looks identical to
  # one whose runs were merged, and the two mean different things for anybody
  # reading the measurement identifiers.
  combined_descriptions[["MergedRuns"]] <- isTRUE(merged_runs)

  # Write JSON file
  output_file <- file.path(output_dir, "desc-combinedregions_tacs.json")
  
  tryCatch({
    jsonlite::write_json(combined_descriptions, output_file, pretty = TRUE, auto_unbox = TRUE)
    cat("Created JSON description file:", output_file, "\n")
    return(output_file)
  }, error = function(e) {
    warning(paste("Error writing JSON description file:", e$message))
    return(NULL)
  })
}
