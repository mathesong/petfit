#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @import shiny
## usethis namespace: end

NULL

# Column names used non-standardly inside dplyr and ggplot2 calls. R CMD check
# cannot tell these apart from undefined variables, so they are declared here.
utils::globalVariables(c(
  ".", ".data", "AIF", "Blood", "ConstituentRegion", "InjectedRadioactivity",
  "ParentFraction", "Plasma", "RegionName", "TAC", "Time", "bodyweight",
  "desc_from_path", "description", "description_parsed", "descriptions",
  "filedata", "folder", "foldername", "frame_dur", "frame_end", "frame_mid",
  "frame_num", "frame_start", "key_value_pairs", "label", "mappings",
  "match_key", "measurement", "morph_filename", "morph_path", "name",
  "participant_id", "path", "pet", "plasma_radioactivity", "region", "run",
  "run_score", "seg", "seg_meanTAC", "segmentation", "ses", "ses_score",
  "tacs_attrs", "tacs_basename", "tacs_filedescription", "tacs_filename",
  "tacs_path", "task", "time", "volume-mm3", "volume_mm3",
  "whole_blood_radioactivity"
))

# Packages the report templates need at render time. The templates live in
# inst/rmd/ and are knitted in a subprocess, so R CMD check cannot see that
# these are used and reports them as unused Imports. They are hard
# requirements -- a missing one fails the report, not an optional feature --
# so they belong in Imports rather than Suggests, and this reference is what
# keeps the declaration honest.
#
# scales, ggplot2, dplyr, tidyr, readr, purrr, tibble and stringr are also
# loaded by the templates but are referenced from R/ as well.
#
# @noRd
petfit_template_dependencies <- function() {
  crosstalk::bscols
  ggbeeswarm::geom_quasirandom
  htmltools::tagList
  plotly::ggplotly
  scales::comma
  invisible(NULL)
}
