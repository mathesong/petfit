#' Run the t* finder and save diagnostic plots
#'
#' @description
#' Generates kinfitr t* (t-star) diagnostic plots for a chosen linear model and a
#' chosen set of PET measurements, to help decide on a t* value. Unlike the other
#' petfit steps this does **not** produce an HTML report: it writes one PNG per
#' measurement to `reports/tstar_finder/{model}/{measurement}_tstar.png` inside the
#' analysis folder.
#'
#' The internal fits are run unweighted, mirroring kinfitr's `*_tstar` functions
#' (which take no weights). For plasma models the blood delay is read from the
#' `*_desc-delayfit_kinpar.tsv` files (defaulting to 0 when absent) and `vB` is
#' fixed at 0.05. For `refLogan`/`MRTM2` the user supplies `k2prime`.
#'
#' @param analysis_folder Path to the analysis folder.
#' @param config_type Either "plasma input" or "reference tissue".
#' @param model Model to run the t* finder for. Plasma: "Logan", "MA1", "Patlak".
#'   Reference: "MRTM1", "refLogan", "MRTM2".
#' @param high_region,med_region,low_region Region names with high/medium/low binding.
#' @param selection One of "random" (default), "all", or "subset".
#' @param sub_filter,ses_filter Semicolon-separated sub/ses values used when
#'   `selection == "subset"`.
#' @param n_random Number of measurements to sample when `selection == "random"`.
#' @param k2prime k2prime value for refLogan/MRTM2 (default 0.1).
#' @param bids_dir,blood_dir Optional BIDS and blood directories (plasma only).
#' @param progress Optional callback `function(fraction, message)` for a progress bar.
#'
#' @return Character vector of written PNG file paths (invisibly on success).
#' @export
run_tstar_finder <- function(analysis_folder, config_type, model,
                             high_region, med_region, low_region,
                             selection = c("random", "all", "subset"),
                             sub_filter = "", ses_filter = "",
                             n_random = 5L, k2prime = 0.1,
                             bids_dir = NULL, blood_dir = NULL,
                             progress = NULL) {

  selection <- match.arg(selection)
  is_ref <- identical(config_type, "reference tissue")

  valid_models <- if (is_ref) c("MRTM1", "refLogan", "MRTM2") else c("Logan", "MA1", "Patlak")
  if (!model %in% valid_models) {
    stop("Model '", model, "' is not a valid t* model for ", config_type,
         " (expected one of: ", paste(valid_models, collapse = ", "), ").")
  }

  regions <- c(high_region, med_region, low_region)
  if (any(is.null(regions)) || any(!nzchar(regions))) {
    stop("High, medium and low binding regions must all be selected.")
  }

  tac_pattern <- if (is_ref) "_desc-targetregions_tacs.tsv" else "_desc-combinedregions_tacs.tsv"
  tac_files <- list.files(analysis_folder, pattern = tac_pattern,
                          recursive = TRUE, full.names = TRUE)
  if (length(tac_files) == 0) {
    stop("No TAC files found in the analysis folder. Run the Data Definition step first.",
         call. = FALSE)
  }

  # Reference t* needs the reference TACs; check upfront so the user gets a clear
  # message instead of every measurement failing individually.
  if (is_ref &&
      length(list.files(analysis_folder, pattern = "_desc-ref_tacs.tsv", recursive = TRUE)) == 0) {
    stop("No reference TAC files found. Run the Reference TAC step first.", call. = FALSE)
  }

  measurements <- tibble::tibble(path = tac_files) %>%
    dplyr::mutate(
      stem = stringr::str_remove(basename(.data$path), "_desc-.*$"),
      attrs = purrr::map(.data$path, ~kinfitr:::bids_filename_attributes(basename(.x)))
    ) %>%
    tidyr::unnest("attrs") %>%
    dplyr::select(-dplyr::any_of(c("measurement", "desc")))

  measurements <- .tstar_select_measurements(measurements, selection,
                                             sub_filter, ses_filter, n_random)
  if (nrow(measurements) == 0) {
    stop("No measurements matched the selection.")
  }

  blood_data <- if (!is_ref) .tstar_load_blood(analysis_folder, bids_dir, blood_dir) else NULL

  out_dir <- file.path(analysis_folder, "reports", "tstar_finder", model)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  n <- nrow(measurements)
  written <- character(0)

  for (i in seq_len(n)) {
    m <- measurements[i, ]
    if (is.function(progress)) progress(i / n, paste0("t* (", model, "): ", m$stem))

    res <- tryCatch({
      tac <- readr::read_tsv(m$path, show_col_types = FALSE) %>%
        dplyr::mutate(frame_mid = .data$frame_mid / 60)

      grab <- function(rg) {
        d <- tac[tac$region == rg, ]
        if (nrow(d) == 0) stop("Region '", rg, "' not found in ", m$stem, call. = FALSE)
        d
      }
      hi <- grab(high_region)
      md <- grab(med_region)
      lo <- grab(low_region)
      t_tac <- hi$frame_mid

      plt <- if (is_ref) {
        reffile <- list.files(dirname(m$path), pattern = "_desc-ref_tacs.tsv", full.names = TRUE)
        if (length(reffile) == 0) stop("No reference TAC found for ", m$stem, call. = FALSE)
        ref <- readr::read_tsv(reffile[1], show_col_types = FALSE)
        # Align the reference TAC to the region frames by frame timing (both in
        # seconds here, since only frame_mid was converted to minutes above).
        ridx <- match(hi$frame_start, ref$frame_start)
        if (anyNA(ridx)) stop("Reference TAC frames do not match the target frames for ", m$stem, call. = FALSE)
        reftac <- ref$RefTAC[ridx]
        switch(model,
          "MRTM1"    = kinfitr::mrtm1_tstar(t_tac, reftac, lo$TAC, md$TAC, hi$TAC),
          "refLogan" = kinfitr::refLogan_tstar(t_tac, reftac, lo$TAC, md$TAC, hi$TAC, k2prime = k2prime),
          "MRTM2"    = kinfitr::mrtm2_tstar(t_tac, reftac, lo$TAC, md$TAC, hi$TAC, k2prime = k2prime))
      } else {
        input <- .tstar_blood_for(blood_data, m)
        inpshift <- .tstar_delay_for(dirname(m$path))
        switch(model,
          "Logan"  = kinfitr::Logan_tstar(t_tac, lo$TAC, md$TAC, hi$TAC, input, inpshift = inpshift, vB = 0.05),
          "MA1"    = kinfitr::ma1_tstar(t_tac, lo$TAC, md$TAC, hi$TAC, input, inpshift = inpshift, vB = 0.05),
          "Patlak" = kinfitr::Patlak_tstar(t_tac, lo$TAC, md$TAC, hi$TAC, input, inpshift = inpshift, vB = 0.05))
      }

      fpath <- file.path(out_dir, paste0(m$stem, "_tstar.png"))
      ggplot2::ggsave(fpath, plot = plt, width = 12, height = 15, dpi = 150,
                      bg = "white", limitsize = FALSE)
      fpath
    }, error = function(e) {
      warning("t* finder failed for ", m$stem, ": ", conditionMessage(e), call. = FALSE)
      NA_character_
    })

    if (!is.na(res)) written <- c(written, res)
  }

  invisible(written)
}

# Apply one sub/ses filter, honouring the exclusion prefix. The column can be
# absent entirely: kinfitr::bids_filename_attributes() spreads only the entities
# a filename carries, so a sessionless study yields no `ses` column at all.
.tstar_apply_filter <- function(measurements, column, values) {
  if (is.null(values) || !column %in% colnames(measurements)) {
    return(measurements)
  }

  keep <- as.character(measurements[[column]]) %in% as.character(values)
  if (isTRUE(attr(values, "negate"))) {
    keep <- !keep
  }

  measurements[keep, , drop = FALSE]
}

# Apply the measurement-selection mode to the discovered measurements tibble.
.tstar_select_measurements <- function(measurements, selection,
                                       sub_filter, ses_filter, n_random) {
  if (selection == "subset") {
    subs <- parse_semicolon_values(sub_filter, field = "sub")
    sess <- parse_semicolon_values(ses_filter, field = "ses")

    # Catch values that match nothing before filtering, so a typo errors rather
    # than quietly shrinking the selection.
    validate_subset_params(measurements, list(sub = subs, ses = sess))

    measurements <- .tstar_apply_filter(measurements, "sub", subs)
    measurements <- .tstar_apply_filter(measurements, "ses", sess)
  } else if (selection == "random") {
    n_random <- suppressWarnings(as.integer(n_random))
    if (is.na(n_random) || n_random < 1) n_random <- 5L
    n <- min(n_random, nrow(measurements))
    if (n < nrow(measurements)) {
      measurements <- measurements[sample(nrow(measurements), n), , drop = FALSE]
    }
  }
  measurements
}

# Load blood input functions for plasma t* (mirrors the model reports' blood logic).
.tstar_load_blood <- function(analysis_folder, bids_dir, blood_dir) {
  has_blood_dir <- !is.null(blood_dir) && length(blood_dir) > 0 &&
    is.character(blood_dir) && nzchar(blood_dir) && dir.exists(blood_dir)

  bd <- if (has_blood_dir) {
    kinfitr::bloodstream_import_inputfunctions(blood_dir)
  } else {
    src <- determine_blood_source(analysis_folder, bids_dir)
    if (src == "analysis_folder") {
      kinfitr::bloodstream_import_inputfunctions(analysis_folder)
    } else {
      stop("No blood input functions found. Please run the previous steps ",
           "(Data Definition, Weights and Fit Delay) first, or launch the app with a ",
           "blood directory, so that blood input functions are available.",
           call. = FALSE)
    }
  }

  dplyr::select(bd, -dplyr::any_of(c("measurement", "desc")))
}

# Pick the blood input function matching one measurement (join on shared BIDS keys).
.tstar_blood_for <- function(blood_data, m) {
  keys <- setdiff(intersect(colnames(blood_data), colnames(m)), c("input", "path", "stem"))
  if (length(keys) == 0) {
    stop("Cannot match a blood input function for ", m$stem,
         ": no shared BIDS identifiers.", call. = FALSE)
  }
  # Use a join (NA-safe, like the reports) rather than vectorised `==`.
  matched <- dplyr::inner_join(blood_data, m[, keys, drop = FALSE], by = keys)
  if (nrow(matched) == 0) {
    stop("No blood input function matched measurement ", m$stem, call. = FALSE)
  }
  matched$input[[1]]
}

# Read the fitted blood delay (inpshift) for a measurement folder; default to 0.
.tstar_delay_for <- function(pet_dir) {
  df <- list.files(pet_dir, pattern = "_desc-delayfit_kinpar.tsv", full.names = TRUE)
  if (length(df) == 0) return(0)
  val <- tryCatch(
    readr::read_tsv(df[1], show_col_types = FALSE)$blood_timeshift,
    error = function(e) NULL
  )
  if (is.null(val) || length(val) == 0 || is.na(val[1])) 0 else val[1]
}
