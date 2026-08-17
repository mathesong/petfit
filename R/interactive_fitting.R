#' Fit a single plasma-input measurement interactively
#'
#' @description
#' Fits one model to one region of one PET measurement using the **saved** Model
#' 1/2/3 configuration, replicating exactly what the corresponding batch report
#' (`logan_report.Rmd`, `ma1_report.Rmd`, `2tcm_report.Rmd`, ...) would do. This
#' lets users sanity-check a fit (and its parameter limits) on a single, possibly
#' troublesome, measurement before running the whole cohort.
#'
#' @param analysis_folder Path to the analysis folder.
#' @param model_number Which configured model to fit: "model1"/"model2"/"model3",
#'   "Model 1", or an integer 1/2/3.
#' @param pet PET measurement identifier (as listed by [pet_key()]).
#' @param region Region to fit.
#' @param bids_dir,blood_dir Optional BIDS and blood directories.
#'
#' @return A list with `fit` (the kinfitr fit object), `par`, `par.se`, `type`,
#'   `model_number`, `pet` and `region`.
#' @export
fit_single_measurement_plasma <- function(analysis_folder, model_number, pet, region,
                                           bids_dir = NULL, blood_dir = NULL) {
  config <- .load_petfit_config(analysis_folder)
  model_config <- .get_model_config(config, model_number)
  type <- model_config$type
  plasma_types <- c("1TCM", "2TCM", "2TCM_irr", "Logan", "MA1", "Patlak")
  if (!type %in% plasma_types) {
    stop("Model ", model_number, " is type '", type, "', which is not a plasma-input model.")
  }

  tac_file <- .resolve_measurement_file(analysis_folder, pet, "_desc-combinedregions_tacs.tsv")
  pet_dir <- dirname(tac_file)

  use_model_weights <- isTRUE(model_config$use_model_weights)
  need_weights <- type %in% c("1TCM", "2TCM", "2TCM_irr", "MA1") || use_model_weights
  region_data <- .load_region_tac(tac_file, region, pet_dir,
                                   join_weights = need_weights)

  blood_data <- .load_all_blood(analysis_folder, bids_dir, blood_dir)
  input <- .blood_for_measurement(blood_data, tac_file)
  inpshift <- .delay_for_measurement(pet_dir)

  vB <- .resolve_vB(model_config, type, pet_dir, region)
  subset <- .subset_bounds(model_config$subset)

  weights <- region_data$weights
  fit <- switch(type,
    "Logan"    = kinfitr::Loganplot(
                   t_tac = region_data$frame_mid, tac = region_data$TAC, input = input,
                   tstar = as.numeric(model_config$tstar), tstar_type = model_config$tstar_type,
                   weights = if (use_model_weights) weights else NULL,
                   inpshift = inpshift, vB = vB, dur = region_data$frame_dur,
                   frameStartEnd = subset$frameStartEnd, timeStartEnd = subset$timeStartEnd),
    "MA1"      = kinfitr::ma1(
                   t_tac = region_data$frame_mid, tac = region_data$TAC, input = input,
                   tstar = as.numeric(model_config$tstar), tstar_type = model_config$tstar_type,
                   weights = weights, inpshift = inpshift, vB = vB, dur = region_data$frame_dur,
                   frameStartEnd = subset$frameStartEnd, timeStartEnd = subset$timeStartEnd),
    "Patlak"   = kinfitr::Patlakplot(
                   t_tac = region_data$frame_mid, tac = region_data$TAC, input = input,
                   tstar = as.numeric(model_config$tstar), tstar_type = model_config$tstar_type,
                   inpshift = inpshift, vB = vB,
                   weights = if (use_model_weights) weights else NULL,
                   frameStartEnd = subset$frameStartEnd, timeStartEnd = subset$timeStartEnd),
    "1TCM"     = .fit_onetcm(model_config, region_data, input, inpshift, vB, subset),
    "2TCM"     = .fit_twotcm(model_config, region_data, input, inpshift, vB, subset),
    "2TCM_irr" = .fit_twotcm_irr(model_config, region_data, input, inpshift, vB, subset)
  )

  .fit_result(fit, type, model_number, pet, region)
}

#' Fit a single reference-tissue measurement interactively
#'
#' @description Reference-tissue counterpart of [fit_single_measurement_plasma()],
#'   replicating `mrtm1_report.Rmd`, `mrtm2_report.Rmd`, `reflogan_report.Rmd`,
#'   `srtm_report.Rmd` and `srtm2_report.Rmd`.
#'
#' @param analysis_folder Path to the analysis folder.
#' @param model_number Which configured model to fit (see plasma version).
#' @param pet PET measurement identifier.
#' @param region Region to fit.
#' @param ancillary_path Optional ancillary analysis folder (for k2prime from
#'   an ancillary analysis).
#'
#' @return A list with `fit`, `par`, `par.se`, `type`, `model_number`, `pet`, `region`.
#' @export
fit_single_measurement_ref <- function(analysis_folder, model_number, pet, region,
                                        ancillary_path = NULL) {
  config <- .load_petfit_config(analysis_folder)
  model_config <- .get_model_config(config, model_number)
  type <- model_config$type
  ref_types <- c("SRTM", "SRTM2", "refLogan", "MRTM1", "MRTM2")
  if (!type %in% ref_types) {
    stop("Model ", model_number, " is type '", type, "', which is not a reference-tissue model.")
  }

  tac_file <- .resolve_measurement_file(analysis_folder, pet, "_desc-targetregions_tacs.tsv")
  pet_dir <- dirname(tac_file)

  use_model_weights <- isTRUE(model_config$use_model_weights)
  # mrtm1/mrtm2/srtm/srtm2 always use weights; refLogan only if requested.
  need_weights <- type != "refLogan" || use_model_weights
  region_data <- .load_region_tac(tac_file, region, pet_dir, join_weights = need_weights)

  reftac <- .load_reftac(pet_dir, region_data)
  subset <- .subset_bounds(model_config$subset)
  weights <- region_data$weights

  k2prime <- if (type %in% c("MRTM2", "refLogan", "SRTM2")) {
    .resolve_k2prime(model_config, pet_dir, region, ancillary_path, pet)
  } else NULL

  fit <- switch(type,
    "MRTM1"    = kinfitr::mrtm1(
                   t_tac = region_data$frame_mid, reftac = reftac, roitac = region_data$TAC,
                   weights = weights, dur = region_data$frame_dur,
                   tstar = .ref_tstar(model_config, "none")$tstar,
                   tstar_type = .ref_tstar(model_config, "none")$tstar_type,
                   frameStartEnd = subset$frameStartEnd, timeStartEnd = subset$timeStartEnd),
    "MRTM2"    = kinfitr::mrtm2(
                   t_tac = region_data$frame_mid, reftac = reftac, roitac = region_data$TAC,
                   k2prime = k2prime, weights = weights, dur = region_data$frame_dur,
                   tstar = .ref_tstar(model_config, "none")$tstar,
                   tstar_type = .ref_tstar(model_config, "none")$tstar_type,
                   frameStartEnd = subset$frameStartEnd, timeStartEnd = subset$timeStartEnd),
    "refLogan" = kinfitr::refLogan(
                   t_tac = region_data$frame_mid, reftac = reftac, roitac = region_data$TAC,
                   k2prime = k2prime,
                   weights = if (use_model_weights) weights else NULL,
                   dur = region_data$frame_dur,
                   tstar = .ref_tstar(model_config, "frames")$tstar,
                   tstar_type = .ref_tstar(model_config, "frames")$tstar_type,
                   frameStartEnd = subset$frameStartEnd, timeStartEnd = subset$timeStartEnd),
    "SRTM"     = .fit_srtm(model_config, region_data, reftac, weights, subset),
    "SRTM2"    = .fit_srtm2(model_config, region_data, reftac, weights, k2prime, subset)
  )

  .fit_result(fit, type, model_number, pet, region)
}


# ---- Shared helpers --------------------------------------------------------

.load_petfit_config <- function(analysis_folder) {
  config_path <- file.path(analysis_folder, "desc-petfitoptions_config.json")
  if (!file.exists(config_path)) {
    stop("No config file found at ", config_path)
  }
  config <- jsonlite::fromJSON(config_path)
  coerce_bounds_numeric(config)
}

.get_model_config <- function(config, model_number) {
  key <- .model_key(model_number)
  model_config <- config$Models[[key]]
  if (is.null(model_config) || is.null(model_config$type)) {
    stop(key, " is not configured.")
  }
  if (model_config$type %in% c("none", "No Model")) {
    stop(key, " is set to 'No Model'.")
  }
  model_config
}

.model_key <- function(model_number) {
  s <- tolower(gsub("[^0-9]", "", as.character(model_number)))
  if (!s %in% c("1", "2", "3")) stop("Invalid model number: ", model_number)
  paste0("Model", s)
}

# Find the TAC file for one PET measurement, matching the dropdown's pet identifier.
.resolve_measurement_file <- function(analysis_folder, pet, tac_pattern) {
  tac_files <- list.files(analysis_folder, pattern = tac_pattern,
                          recursive = TRUE, full.names = TRUE)
  if (length(tac_files) == 0) {
    stop("No TAC files found in the analysis folder. Run the Data Definition step first.",
         call. = FALSE)
  }
  pet_ids <- pet_key(tac_files, analysis_folder)
  idx <- which(pet_ids == pet)
  if (length(idx) == 0) {
    # Fall back to a filename-prefix match (covers single-measurement folders).
    idx <- which(startsWith(basename(tac_files), paste0(pet, "_")))
  }
  if (length(idx) == 0) {
    stop("Could not find data for PET measurement '", pet, "'.")
  }
  tac_files[idx[1]]
}

# Read one region's TAC (time in minutes), optionally joining its weights.
.load_region_tac <- function(tac_file, region, pet_dir, join_weights) {
  tac <- readr::read_tsv(tac_file, show_col_types = FALSE)

  region_data <- tac[tac$region == region, , drop = FALSE]
  if (nrow(region_data) == 0) {
    stop("Region '", region, "' not found in ", basename(tac_file), ".")
  }

  if (join_weights) {
    wfiles <- list.files(pet_dir, pattern = "_weights.tsv", full.names = TRUE)
    if (length(wfiles) == 0) {
      stop("This model requires weights, but no *_weights.tsv was found for ", basename(pet_dir),
           ". Run the Weights step first.")
    }
    # Weights are a single per-frame series (consistent across regions for every
    # region_type), so we join by frame. distinct() guards against any legacy file
    # that duplicated the series per region.
    w <- readr::read_tsv(wfiles[1], show_col_types = FALSE) %>%
      dplyr::select(dplyr::any_of(c("frame_start", "weights"))) %>%
      dplyr::distinct(.data$frame_start, .keep_all = TRUE)
    region_data <- dplyr::inner_join(region_data, w, by = "frame_start")
  }

  region_data %>%
    dplyr::mutate(
      frame_start = .data$frame_start / 60,
      frame_end   = .data$frame_end / 60,
      frame_dur   = .data$frame_dur / 60,
      frame_mid   = .data$frame_mid / 60
    )
}

# Reference TAC vector aligned to the region's frames by frame timing.
.load_reftac <- function(pet_dir, region_data) {
  reffile <- list.files(pet_dir, pattern = "_desc-ref_tacs.tsv", full.names = TRUE)
  if (length(reffile) == 0) {
    stop("No reference TAC (*_desc-ref_tacs.tsv) found for ", basename(pet_dir),
         ". Run the Reference TAC step first.", call. = FALSE)
  }
  ref <- readr::read_tsv(reffile[1], show_col_types = FALSE)
  if (!all(c("frame_start", "RefTAC") %in% colnames(ref))) {
    stop("Reference TAC file for ", basename(pet_dir),
         " is missing required columns (frame_start, RefTAC).", call. = FALSE)
  }
  # Align by frame timing rather than position (region_data frame_start is in
  # minutes; the reference file is in seconds), mirroring the reports' frame join.
  idx <- match(round(region_data$frame_start, 6), round(ref$frame_start / 60, 6))
  if (anyNA(idx)) {
    stop("Reference TAC frames do not match the target region frames for ",
         basename(pet_dir), ". Re-run the Reference TAC step.", call. = FALSE)
  }
  ref$RefTAC[idx]
}

.load_all_blood <- function(analysis_folder, bids_dir, blood_dir) {
  has_blood_dir <- !is.null(blood_dir) && length(blood_dir) > 0 &&
    is.character(blood_dir) && nzchar(blood_dir) && dir.exists(blood_dir)
  bd <- if (has_blood_dir) {
    kinfitr::bloodstream_import_inputfunctions(blood_dir)
  } else {
    src <- determine_blood_source(analysis_folder, bids_dir)
    if (src == "analysis_folder") {
      kinfitr::bloodstream_import_inputfunctions(analysis_folder)
    } else {
      stop("No blood input functions found for this analysis. Provide a blood directory, ",
           "or run the Fit Delay step first to generate input functions from the raw blood data.",
           call. = FALSE)
    }
  }
  dplyr::select(bd, -dplyr::any_of(c("measurement", "desc")))
}

.blood_for_measurement <- function(blood_data, tac_file) {
  attrs <- kinfitr::bids_filename_attributes(basename(tac_file))
  attrs <- attrs[, setdiff(colnames(attrs), c("measurement", "desc")), drop = FALSE]
  keys <- intersect(colnames(blood_data), colnames(attrs))
  if (length(keys) == 0) {
    stop("Cannot match a blood input function: no shared BIDS identifiers.", call. = FALSE)
  }
  # Use a join (NA-safe, like the reports) rather than vectorised `==`.
  matched <- dplyr::inner_join(blood_data, attrs[, keys, drop = FALSE], by = keys)
  if (nrow(matched) == 0) {
    stop("No blood input function matched ", basename(tac_file), ".", call. = FALSE)
  }
  matched$input[[1]]
}

.delay_for_measurement <- function(pet_dir) {
  df <- list.files(pet_dir, pattern = "_desc-delayfit_kinpar.tsv", full.names = TRUE)
  if (length(df) == 0) return(0)
  val <- tryCatch(
    readr::read_tsv(df[1], show_col_types = FALSE)$blood_timeshift,
    error = function(e) NULL
  )
  if (is.null(val) || length(val) == 0 || is.na(val[1])) 0 else val[1]
}

# TAC subsetting -> frameStartEnd / timeStartEnd (mirrors the reports' model-prep).
.subset_bounds <- function(subset_config) {
  out <- list(frameStartEnd = NULL, timeStartEnd = NULL)
  if (!is.null(subset_config) && !is.null(subset_config$type) &&
      (!is.null(subset_config$start) || !is.null(subset_config$end))) {
    if (identical(subset_config$type, "frame")) {
      out$frameStartEnd <- c(subset_config$start, subset_config$end)
    } else if (identical(subset_config$type, "time")) {
      out$timeStartEnd <- c(subset_config$start, subset_config$end)
    }
  }
  out
}

# Resolve the vB value (or NULL when the nonlinear model should fit vB).
.resolve_vB <- function(model_config, type, pet_dir, region) {
  nonlinear <- type %in% c("1TCM", "2TCM", "2TCM_irr")
  vB_source <- if (!is.null(model_config$vB_source)) {
    model_config$vB_source
  } else if (nonlinear) {
    # Model 1 nonlinear: vB is controlled by the vB$fit boolean, which the batch
    # reports default to TRUE (fit vB) when absent.
    if (isTRUE(model_config$vB$fit %||% TRUE)) "fit" else "set"
  } else {
    "set"
  }

  if (vB_source == "fit") return(NULL)

  if (vB_source == "set") {
    if (type %in% c("Logan", "Patlak")) {
      return(model_config$vB_value %||% 0.05)
    }
    return(model_config$vB$start %||% 0.05)
  }

  # Inheritance from a previous model's kinpar.
  .resolve_inherited(model_config$vB_source, pet_dir, region, param = "vB", default = 0.05)
}

# Resolve the k2prime value for refLogan/MRTM2/SRTM2.
.resolve_k2prime <- function(model_config, pet_dir, region, ancillary_path, pet) {
  source_val <- model_config$k2prime_source %||% "set"

  if (source_val == "set") {
    # The app saves a fixed k2prime as `k2prime_value`; fall back to `k2prime`
    # for backward compatibility. Matches the reference reports.
    return(model_config$k2prime_value %||% model_config$k2prime %||% 0.1)
  }

  if (startsWith(source_val, "ancillary_model")) {
    if (is.null(ancillary_path)) {
      stop("This model takes its k2prime from an ancillary analysis, but no ancillary ",
           "analysis folder is configured for this session.", call. = FALSE)
    }
    parsed <- parse_ancillary_k2prime_source(source_val)
    k2p <- tryCatch(
      read_ancillary_k2prime(ancillary_path = ancillary_path,
                             model_num = parsed$model_num,
                             aggregation = parsed$aggregation,
                             pet_ids = pet),
      error = function(e) NULL
    )
    if (is.null(k2p) || nrow(k2p) == 0) {
      stop("Could not read a k2prime value for this measurement from the ancillary ",
           "analysis. Check that the ancillary analysis has been run.", call. = FALSE)
    }
    return(k2p$k2prime[1])
  }

  .resolve_inherited(source_val, pet_dir, region, param = "k2prime", default = 0.1)
}

# Read an inherited parameter (vB or k2prime) from a previous model's kinpar.
.resolve_inherited <- function(source_string, pet_dir, region, param, default) {
  inh_model <- stringr::str_match(source_string, "inherit_(model\\d)")[, 2]
  inh_type  <- stringr::str_match(source_string, "inherit_model\\d_(\\w*)")[, 2]

  # Unparseable source string: fall back to the default rather than erroring.
  if (is.na(inh_model)) return(default)

  kpfile <- list.files(pet_dir, pattern = paste0("_desc-", inh_model, "_kinpar.tsv"),
                       full.names = TRUE)
  if (length(kpfile) == 0) {
    model_label <- sub("model", "Model ", inh_model)
    stop("This model inherits its ", param, " value from ", model_label,
         ", but ", model_label, " has not been fitted yet for this measurement. ",
         "Run ", model_label, " first (or change the ", param, " source to a fixed value).",
         call. = FALSE)
  }

  kp <- readr::read_tsv(kpfile[1], show_col_types = FALSE)
  if (!param %in% colnames(kp)) return(default)
  vals <- kp[[param]]

  if (identical(inh_type, "mean")) {
    return(mean(vals, na.rm = TRUE))
  }
  if (identical(inh_type, "median")) {
    return(stats::median(vals, na.rm = TRUE))
  }
  if (identical(inh_type, "regional")) {
    row <- kp[kp$region == region, , drop = FALSE]
    if (nrow(row) == 0) return(default)
    return(row[[param]][1])
  }
  default
}

# t* settings for reference models, with model-specific defaults.
.ref_tstar <- function(model_config, default_type) {
  tstar_type <- model_config$tstar_type %||% default_type
  if (default_type == "frames") {
    if (!tstar_type %in% c("frames", "frame", "time")) tstar_type <- "frames"
    tstar <- model_config$tstar %||% 10
  } else {
    tstar <- if (identical(tstar_type, "none")) NULL else model_config$tstar %||% NULL
  }
  list(tstar = tstar, tstar_type = tstar_type)
}

.bound <- function(model_config, par, field, default) {
  model_config[[par]][[field]] %||% default
}

.fit_onetcm <- function(model_config, region_data, input, inpshift, vB, subset) {
  args <- list(
    t_tac = region_data$frame_mid, tac = region_data$TAC, input = input,
    weights = region_data$weights, inpshift = inpshift,
    frameStartEnd = subset$frameStartEnd, timeStartEnd = subset$timeStartEnd,
    K1.start = .bound(model_config, "K1", "start", 0.1),
    K1.lower = .bound(model_config, "K1", "lower", 0),
    K1.upper = .bound(model_config, "K1", "upper", 1),
    k2.start = .bound(model_config, "k2", "start", 0.1),
    k2.lower = .bound(model_config, "k2", "lower", 0),
    k2.upper = .bound(model_config, "k2", "upper", 1),
    multstart_iter = model_config$multstart_iter %||% 1
  )
  if (is.null(vB)) {
    args <- c(args, list(vB.start = .bound(model_config, "vB", "start", 0.05),
                         vB.lower = .bound(model_config, "vB", "lower", 0),
                         vB.upper = .bound(model_config, "vB", "upper", 0.2)))
  } else {
    args$vB <- vB
  }
  do.call(kinfitr::onetcm, args)
}

.fit_twotcm <- function(model_config, region_data, input, inpshift, vB, subset) {
  args <- list(
    t_tac = region_data$frame_mid, tac = region_data$TAC, input = input,
    weights = region_data$weights, inpshift = inpshift,
    frameStartEnd = subset$frameStartEnd, timeStartEnd = subset$timeStartEnd,
    K1.start = .bound(model_config, "K1", "start", 0.1),
    K1.lower = .bound(model_config, "K1", "lower", 0),
    K1.upper = .bound(model_config, "K1", "upper", 1),
    k2.start = .bound(model_config, "k2", "start", 0.1),
    k2.lower = .bound(model_config, "k2", "lower", 0),
    k2.upper = .bound(model_config, "k2", "upper", 1),
    k3.start = .bound(model_config, "k3", "start", 0.1),
    k3.lower = .bound(model_config, "k3", "lower", 0),
    k3.upper = .bound(model_config, "k3", "upper", 1),
    k4.start = .bound(model_config, "k4", "start", 0.1),
    k4.lower = .bound(model_config, "k4", "lower", 0),
    k4.upper = .bound(model_config, "k4", "upper", 1),
    multstart_iter = model_config$multstart_iter %||% 1
  )
  if (is.null(vB)) {
    args <- c(args, list(vB.start = .bound(model_config, "vB", "start", 0.05),
                         vB.lower = .bound(model_config, "vB", "lower", 0),
                         vB.upper = .bound(model_config, "vB", "upper", 0.2)))
  } else {
    args$vB <- vB
  }
  do.call(kinfitr::twotcm, args)
}

.fit_twotcm_irr <- function(model_config, region_data, input, inpshift, vB, subset) {
  args <- list(
    t_tac = region_data$frame_mid, tac = region_data$TAC, input = input,
    weights = region_data$weights, inpshift = inpshift,
    frameStartEnd = subset$frameStartEnd, timeStartEnd = subset$timeStartEnd,
    K1.start = .bound(model_config, "K1", "start", 0.1),
    K1.lower = .bound(model_config, "K1", "lower", 0),
    K1.upper = .bound(model_config, "K1", "upper", 1),
    k2.start = .bound(model_config, "k2", "start", 0.1),
    k2.lower = .bound(model_config, "k2", "lower", 0),
    k2.upper = .bound(model_config, "k2", "upper", 1),
    k3.start = .bound(model_config, "k3", "start", 0.1),
    k3.lower = .bound(model_config, "k3", "lower", 0),
    k3.upper = .bound(model_config, "k3", "upper", 1),
    multstart_iter = model_config$multstart_iter %||% 1
  )
  if (is.null(vB)) {
    args <- c(args, list(vB.start = .bound(model_config, "vB", "start", 0.05),
                         vB.lower = .bound(model_config, "vB", "lower", 0.01),
                         vB.upper = .bound(model_config, "vB", "upper", 0.1)))
  } else {
    args$vB <- vB
  }
  do.call(kinfitr::twotcm_irr, args)
}

.fit_srtm <- function(model_config, region_data, reftac, weights, subset) {
  kinfitr::srtm(
    t_tac = region_data$frame_mid, reftac = reftac, roitac = region_data$TAC,
    weights = weights,
    frameStartEnd = subset$frameStartEnd, timeStartEnd = subset$timeStartEnd,
    R1.start = .bound(model_config, "R1", "start", 1),
    R1.lower = .bound(model_config, "R1", "lower", 0),
    R1.upper = .bound(model_config, "R1", "upper", 10),
    k2.start = .bound(model_config, "k2", "start", 0.1),
    k2.lower = .bound(model_config, "k2", "lower", 0),
    k2.upper = .bound(model_config, "k2", "upper", 1),
    bp.start = .bound(model_config, "BPnd", "start", 1.5),
    bp.lower = .bound(model_config, "BPnd", "lower", 0),
    bp.upper = .bound(model_config, "BPnd", "upper", 15),
    multstart_iter = model_config$multstart_iter %||% 1
  )
}

.fit_srtm2 <- function(model_config, region_data, reftac, weights, k2prime, subset) {
  kinfitr::srtm2(
    t_tac = region_data$frame_mid, reftac = reftac, roitac = region_data$TAC,
    weights = weights, k2prime = k2prime,
    frameStartEnd = subset$frameStartEnd, timeStartEnd = subset$timeStartEnd,
    R1.start = .bound(model_config, "R1", "start", 1),
    R1.lower = .bound(model_config, "R1", "lower", 0),
    R1.upper = .bound(model_config, "R1", "upper", 10),
    bp.start = .bound(model_config, "BPnd", "start", 1.5),
    bp.lower = .bound(model_config, "BPnd", "lower", 0),
    bp.upper = .bound(model_config, "BPnd", "upper", 15),
    multstart_iter = model_config$multstart_iter %||% 1
  )
}

# Assemble the return value, prettifying parameter names like the reports do.
.fit_result <- function(fit, type, model_number, pet, region) {
  if (length(fit) <= 1 || !is.list(fit)) {
    stop("Model fitting failed for ", pet, " / ", region, ".")
  }
  par <- .prettify_params(fit$par)
  par.se <- .prettify_params(fit$par.se)
  list(fit = fit, par = par, par.se = par.se, type = type,
       model_number = model_number, pet = pet, region = region)
}

.prettify_params <- function(df) {
  if (is.null(df)) return(df)
  names(df) <- names(df) %>%
    stringr::str_replace("^Vt$", "VT") %>%
    stringr::str_replace("^Vt\\.", "VT.") %>%
    stringr::str_replace("^bp$", "BPnd") %>%
    stringr::str_replace("^bp\\.", "BPnd.")
  df
}
