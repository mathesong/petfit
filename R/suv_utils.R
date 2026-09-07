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
#' The result is passed to [kinfitr::suvr()], which does the estimation: a mode
#' of `"none"` corresponds to leaving its `injRad` and `bodymass` unset, which
#' makes its denominator 1, so that the SUV outcomes come back as
#' *radioactivity concentrations* rather than as SUVs or as `NA`. They are
#' meaningless as SUVs, and the callers drop them; do not test for them with
#' `is.na()`. The SUVR, in which the denominator cancels, is unaffected.
#'
#' `bodymass` is returned in **grams**, not the kilograms it is supplied in.
#' SUV is conventionally the tissue concentration over the dose per unit body
#' mass with the mass in grams, which for a concentration in kBq/mL and a dose
#' in kBq gives the usual g/mL. Dividing by kilograms instead would give an SUV
#' a thousand times smaller.
#'
#' @param inj_rad Numeric vector of injected radioactivities.
#' @param bodyweight Numeric vector of body weights, in kg.
#' @param bodymass_default Body mass in kg to assume when body weight is missing
#'   but the dose is known. Defaults to 70.
#'
#' @return A list with `mode` (one of `"SUV"`, `"SUV_bw70"` or `"none"`),
#'   `bodymass` (the body mass to divide the dose by, **in grams**, or `NA`) and
#'   `label`, a sentence describing the choice for the report.
#'
#' @export
suv_denominator <- function(inj_rad, bodyweight, bodymass_default = 70) {
  # Grams, so that dose/mass makes SUV the conventional g/mL. See @details.
  g_per_kg <- 1000
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
      bodymass = bodymass_default * g_per_kg,
      label = paste0("SUV is approximated from the injected radioactivity, assuming a ",
                     "body weight of ", bodymass_default, " kg for all individuals, ",
                     "because body weight is not available for all participants.")
    ))
  }

  list(
    mode = "SUV",
    bodymass = bodyweight * g_per_kg,
    label = paste0("SUV is calculated from the injected radioactivity and body weight, ",
                   "because both are present for all measurements.")
  )
}
