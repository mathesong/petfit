#' Standardised uptake value and uptake value ratio
#'
#' @description
#' Estimates the standardised uptake value (SUV) and the target-to-reference
#' standardised uptake value ratio (SUVR) over a frame or time window, following
#' the regional TAC ratio approach of Turku PET Centre's `dftratio`.
#'
#' The integrals come from [kinfitr::SUV()], so the window is resolved exactly as
#' kinfitr resolves it: `timeStartEnd` selects whole frames whose **midpoint**
#' falls inside the window, never a partial frame. The window is normalised here
#' rather than left to kinfitr so that a one-sided window (only a start, or only
#' an end) is well defined, and so that the reported window bounds and duration
#' describe the frames that were actually integrated.
#'
#' SUVR is a ratio of two integrals over the same frames, so the injected
#' radioactivity and body mass cancel: it is identical whether it is computed
#' from radioactivity concentrations or from SUV. SUV itself is not, and is
#' returned as `NA` unless `injRad` is supplied.
#'
#' @param t_tac Numeric vector of frame midpoint times, in minutes.
#' @param reftac Numeric vector of radioactivity concentrations in the reference
#'   region for each frame.
#' @param roitac Numeric vector of radioactivity concentrations in the target
#'   region for each frame.
#' @param dur Numeric vector of frame durations, in minutes. Used for the
#'   integral, so that it is a frame-duration weighted sum rather than a
#'   trapezoidal approximation.
#' @param frame_start,frame_end Optional numeric vectors of frame start and end
#'   times in minutes, used to report the window bounds. Defaults to the range of
#'   the midpoints of the included frames.
#' @param injRad Injected radioactivity. `NA` (the default) means no dose
#'   information is available, and the SUV outcomes are returned as `NA`.
#' @param bodymass Body mass of the participant. `NA` (the default) means it is
#'   unavailable; see the `bodymass_default` argument of [suv_denominator()] for
#'   the 70 kg approximation used elsewhere in petfit.
#' @param frameStartEnd Optional length-2 vector giving the first and last frame
#'   number to include, e.g. `c(1, 20)`. Either element may be `NA` or `NULL` for
#'   a one-sided window.
#' @param timeStartEnd Optional length-2 vector giving the start and end time in
#'   minutes. Frames whose midpoint lies within the window are included. Either
#'   element may be `NA` for a one-sided window.
#'
#' @return An object of class `suvr`: a list with `par` (a one-row tibble of
#'   outcomes), `tacs` (the input TACs annotated with which frames were included)
#'   and `window` (the resolved frame indices). `par` contains:
#'   \describe{
#'     \item{SUVR}{Target integral divided by reference integral.}
#'     \item{SUV, SUV_ref}{Mean SUV over the window; `NA` without `injRad`.}
#'     \item{intSUV, intSUV_ref}{SUV integral; `NA` without `injRad`.}
#'     \item{meanTAC, meanTAC_ref}{Frame-duration weighted mean radioactivity
#'       concentration over the window.}
#'     \item{intTAC, intTAC_ref}{Radioactivity concentration integral.}
#'     \item{window_start, window_end, window_duration, n_frames}{The window that
#'       was actually integrated.}
#'   }
#'
#' @examples
#' \dontrun{
#' suvr(t_tac = tac$frame_mid, reftac = tac$RefTAC, roitac = tac$TAC,
#'      dur = tac$frame_dur, timeStartEnd = c(60, 90),
#'      injRad = 180, bodymass = 75)
#' }
#'
#' @export
suvr <- function(t_tac, reftac, roitac, dur,
                 frame_start = NULL, frame_end = NULL,
                 injRad = NA_real_, bodymass = NA_real_,
                 frameStartEnd = NULL, timeStartEnd = NULL) {

  n <- length(t_tac)
  if (n == 0) {
    stop("t_tac is empty.", call. = FALSE)
  }
  if (length(roitac) != n || length(reftac) != n || length(dur) != n) {
    stop("t_tac, reftac, roitac and dur must all be the same length.", call. = FALSE)
  }

  window <- .suvr_window(t_tac, n, frameStartEnd, timeStartEnd)
  frames <- window$start:window$end
  included <- seq_len(n) %in% frames

  # Delegate the integrals to kinfitr, passing the resolved frame window so that
  # what is integrated here and what is reported below cannot drift apart. The
  # denominator is applied afterwards, so injRad/bodymass are left at 1 and the
  # integrals come back as radioactivity concentration.
  int_roi <- kinfitr::SUV(tac = roitac, t_tac = t_tac, dur_tac = dur,
                          injRad = 1, bodymass = 1,
                          frameStartEnd = c(window$start, window$end))$par$intSUV
  int_ref <- kinfitr::SUV(tac = reftac, t_tac = t_tac, dur_tac = dur,
                          injRad = 1, bodymass = 1,
                          frameStartEnd = c(window$start, window$end))$par$intSUV

  # kinfitr sums tac * dur over the selected frames, so the matching duration is
  # the sum of those frames' durations.
  window_duration <- sum(dur[frames], na.rm = TRUE)

  window_start <- if (!is.null(frame_start)) {
    min(frame_start[frames], na.rm = TRUE)
  } else {
    min(t_tac[frames], na.rm = TRUE)
  }
  window_end <- if (!is.null(frame_end)) {
    max(frame_end[frames], na.rm = TRUE)
  } else {
    max(t_tac[frames], na.rm = TRUE)
  }

  denominator <- injRad / bodymass
  if (length(denominator) != 1 || is.na(denominator) || denominator <= 0) {
    denominator <- NA_real_
  }

  par <- tibble::tibble(
    SUVR = int_roi / int_ref,
    SUV = (int_roi / window_duration) / denominator,
    SUV_ref = (int_ref / window_duration) / denominator,
    intSUV = int_roi / denominator,
    intSUV_ref = int_ref / denominator,
    meanTAC = int_roi / window_duration,
    meanTAC_ref = int_ref / window_duration,
    intTAC = int_roi,
    intTAC_ref = int_ref,
    window_start = window_start,
    window_end = window_end,
    window_duration = window_duration,
    n_frames = length(frames)
  )

  tacs <- tibble::tibble(
    Time = t_tac,
    Duration = dur,
    Target = roitac,
    Reference = reftac,
    included = included,
    window_duration = dplyr::if_else(included, dur, 0)
  )
  if (!is.null(frame_start)) tacs$frame_start <- frame_start
  if (!is.null(frame_end)) tacs$frame_end <- frame_end

  structure(
    list(par = par, tacs = tacs, window = window, model = "SUVR"),
    class = c("suvr", "list")
  )
}

# Resolve a frame or time window down to a first and last frame index, matching
# kinfitr's convention that a time window selects whole frames by midpoint.
# Either end of the window may be missing, giving a one-sided window.
.suvr_window <- function(t_tac, n, frameStartEnd, timeStartEnd) {
  scalar <- function(x, i) {
    if (is.null(x) || length(x) < i) return(NA_real_)
    v <- suppressWarnings(as.numeric(x[[i]]))
    if (length(v) != 1 || is.na(v)) NA_real_ else v
  }

  start <- 1L
  end <- n

  if (!is.null(frameStartEnd)) {
    lo <- scalar(frameStartEnd, 1)
    hi <- scalar(frameStartEnd, 2)
    # A window of c(0, 0) is how the apps encode "no window"; treat it as all frames.
    if (!(is.na(lo) && is.na(hi)) && !isTRUE(all.equal(c(lo, hi), c(0, 0)))) {
      if (!is.na(lo) && lo >= 1) start <- as.integer(min(lo, n))
      if (!is.na(hi) && hi >= 1) end <- as.integer(min(hi, n))
    }
  } else if (!is.null(timeStartEnd)) {
    lo <- scalar(timeStartEnd, 1)
    hi <- scalar(timeStartEnd, 2)
    if (!(is.na(lo) && is.na(hi)) && !isTRUE(all.equal(c(lo, hi), c(0, 0)))) {
      if (is.na(lo)) lo <- -Inf
      if (is.na(hi)) hi <- Inf
      # kinfitr::SUV() converts a time window this way: frames whose midpoint is
      # inside the window, taking the first and last such frame.
      sel <- which(t_tac >= lo & t_tac <= hi)
      if (length(sel) == 0) {
        stop("No frames fall within the requested time window of ",
             lo, " to ", hi, " minutes. The frame midpoints run from ",
             round(min(t_tac), 2), " to ", round(max(t_tac), 2), " minutes.",
             call. = FALSE)
      }
      start <- min(sel)
      end <- max(sel)
    }
  }

  if (start > end) {
    stop("The requested window is empty: it starts at frame ", start,
         " and ends at frame ", end, ".", call. = FALSE)
  }

  list(start = as.integer(start), end = as.integer(end))
}

#' Resolve the SUV denominator for a set of measurements
#'
#' @description
#' Decides how SUV should be calculated for a set of measurements, following the
#' same rule the data definition report uses: a true SUV when injected
#' radioactivity and body weight are known for every measurement, a body weight
#' of 70 kg assumed when only the dose is known, and no SUV at all when the dose
#' is missing anywhere.
#'
#' The decision is deliberately made across all measurements rather than per
#' measurement, so that an outcome column means the same thing for every row of
#' the cohort.
#'
#' @param inj_rad Numeric vector of injected radioactivities.
#' @param bodyweight Numeric vector of body weights.
#' @param bodymass_default Body mass in kg to assume when body weight is missing
#'   but the dose is known. Defaults to 70.
#'
#' @return A list with `mode` (one of `"SUV"`, `"SUV_bw70"` or `"none"`),
#'   `bodymass` (the vector to use, or `NA`) and `label`, a sentence describing
#'   the choice for the report.
#'
#' @export
suv_denominator <- function(inj_rad, bodyweight, bodymass_default = 70) {
  if (is.null(inj_rad) || length(inj_rad) == 0 || any(is.na(inj_rad))) {
    return(list(
      mode = "none",
      bodymass = NA_real_,
      label = paste0("SUV is not reported because the injected radioactivity is ",
                     "not available for all measurements. SUVR is unaffected: it ",
                     "is a ratio, so the dose cancels.")
    ))
  }

  if (is.null(bodyweight) || length(bodyweight) == 0 || any(is.na(bodyweight))) {
    return(list(
      mode = "SUV_bw70",
      bodymass = bodymass_default,
      label = paste0("SUV is approximated from the injected radioactivity, assuming a ",
                     "body weight of ", bodymass_default, " kg for all individuals, ",
                     "because body weight is not available for all participants.")
    ))
  }

  list(
    mode = "SUV",
    bodymass = bodyweight,
    label = paste0("SUV is calculated from the injected radioactivity and body weight, ",
                   "because both are present for all measurements.")
  )
}

#' Plot a SUV/SUVR estimate
#'
#' @description
#' Shows the target and reference TACs, with the frames that contributed to the
#' ratio shaded underneath. The shaded area is what was integrated: its extent
#' shows the window, and its area is proportional to the integral whose ratio is
#' the SUVR.
#'
#' @param x A `suvr` object from [suvr()].
#' @param roiname Name of the target region, used in the legend.
#' @param refname Name of the reference region, used in the legend.
#' @param ... Unused, for consistency with the generic.
#'
#' @return A ggplot object.
#' @export
plot.suvr <- function(x, roiname = NULL, refname = "Reference", ...) {
  if (is.null(roiname) || is.na(roiname) || !nzchar(roiname)) roiname <- "Target"

  levels <- c(roiname, refname)

  tacs <- x$tacs
  long <- dplyr::bind_rows(
    tibble::tibble(Time = tacs$Time, Value = tacs$Target,
                   included = tacs$included, Region = roiname),
    tibble::tibble(Time = tacs$Time, Value = tacs$Reference,
                   included = tacs$included, Region = refname)
  )
  long$Region <- factor(long$Region, levels = levels)

  shaded <- long[long$included, , drop = FALSE]

  suvr_value <- x$par$SUVR
  subtitle <- paste0("SUVR = ", signif(suvr_value, 4),
                     "  |  window ", signif(x$par$window_start, 4), "\u2013",
                     signif(x$par$window_end, 4), " min (",
                     x$par$n_frames, " frames)")
  if (!is.na(x$par$SUV)) {
    subtitle <- paste0(subtitle, "  |  SUV = ", signif(x$par$SUV, 4))
  }

  ggplot2::ggplot(long, ggplot2::aes(x = .data$Time, y = .data$Value,
                                     colour = .data$Region)) +
    ggplot2::geom_ribbon(
      data = shaded,
      mapping = ggplot2::aes(ymin = 0, ymax = .data$Value, fill = .data$Region),
      alpha = 0.3, colour = NA
    ) +
    ggplot2::geom_line() +
    ggplot2::geom_point(size = 1.6) +
    ggplot2::expand_limits(y = 0) +
    ggplot2::labs(x = "Time (min)", y = "Radioactivity",
                  colour = "Region", fill = "Region",
                  subtitle = subtitle) +
    ggplot2::theme_light()
}
