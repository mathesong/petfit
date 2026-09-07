test_that("petfit_tac_units reads the units the region definition step wrote", {
  root <- withr::local_tempdir()
  analysis <- file.path(root, "Primary_Analysis")
  dir.create(analysis)

  jsonlite::write_json(
    list(radioactivity = list(Units = "kBq/mL"), time = list(Units = "s")),
    file.path(root, "desc-combinedregions_tacs.json"),
    auto_unbox = TRUE
  )

  expect_equal(petfit_tac_units(analysis),
               list(radioactivity = "kBq/mL", time = "s"))
})

test_that("petfit_tac_units falls back to the TAC column, then to the defaults", {
  root <- withr::local_tempdir()
  analysis <- file.path(root, "Primary_Analysis")
  dir.create(analysis)

  # An older sidecar without the dedicated radioactivity/time entries.
  jsonlite::write_json(
    list(TAC = list(Units = "Bq/mL"), frame_mid = list(Units = "s")),
    file.path(root, "desc-combinedregions_tacs.json"),
    auto_unbox = TRUE
  )
  expect_equal(petfit_tac_units(analysis)$radioactivity, "Bq/mL")

  # No sidecar at all: the units the region definition step standardises to.
  missing <- withr::local_tempdir()
  expect_equal(petfit_tac_units(file.path(missing, "Primary_Analysis")),
               list(radioactivity = "kBq/mL", time = "s"))
})

test_that("an analysis's own sidecar wins over the shared one", {
  # The data definition step converts an analysis whose TACs are not already
  # kBq, and records that beside the converted copies. The shared sidecar still
  # describes the units the TACs were combined in, so it must not be read in
  # preference to the analysis's own.
  root <- withr::local_tempdir()
  analysis <- file.path(root, "Primary_Analysis")
  dir.create(analysis)

  jsonlite::write_json(
    list(radioactivity = list(Units = "Bq/mL"), time = list(Units = "s")),
    file.path(root, "desc-combinedregions_tacs.json"),
    auto_unbox = TRUE
  )
  expect_equal(petfit_tac_units(analysis)$radioactivity, "Bq/mL")

  jsonlite::write_json(
    list(radioactivity = list(Units = "kBq/mL"), time = list(Units = "s")),
    file.path(analysis, "desc-combinedregions_tacs.json"),
    auto_unbox = TRUE
  )
  expect_equal(petfit_tac_units(analysis)$radioactivity, "kBq/mL")
})

test_that("bids_column_units gives every column a Description, and units only where they exist", {
  out <- bids_column_units(
    list(frame_mid = "Frame midpoint",
         TAC = "Tissue TAC",
         TAC_fitted = "Fitted values",
         weights = "Model weights",
         region = "Region name"),
    radioactivity_units = "kBq/mL",
    time_units = "min"
  )

  expect_named(out, c("frame_mid", "TAC", "TAC_fitted", "weights", "region"))
  expect_true(all(purrr::map_lgl(out, ~"Description" %in% names(.x))))

  expect_equal(out$frame_mid$Units, "min")
  expect_equal(out$TAC$Units, "kBq/mL")
  expect_equal(out$TAC_fitted$Units, "kBq/mL")

  # Dimensionless columns are described, not given invented units.
  expect_null(out$weights$Units)
  expect_null(out$region$Units)
})

test_that("the time base of the file is what is reported, not a fixed one", {
  # The TAC files are in seconds; a model's fitted values are in minutes.
  in_seconds <- bids_column_units(list(frame_start = "Frame start"),
                                  time_units = "s")
  in_minutes <- bids_column_units(list(frame_start = "Frame start"),
                                  time_units = "min")

  expect_equal(in_seconds$frame_start$Units, "s")
  expect_equal(in_minutes$frame_start$Units, "min")
})

test_that("the radioactivity units follow the data rather than being assumed", {
  out <- bids_column_units(list(TAC = "Tissue TAC"),
                           radioactivity_units = "Bq/cm^3")
  expect_equal(out$TAC$Units, "Bq/cm^3")
})

test_that("kinpar_units covers the dimensioned parameters and skips the rest", {
  out <- kinpar_units(c("K1", "k2", "k3", "k4", "k2a", "k2prime",
                        "VT", "Vnd", "BPp", "inpshift",
                        "BPnd", "R1", "vB", "SUVR",
                        "BPnd.se", "AIC", "BIC", "RSS", "region"))

  expect_equal(out$K1$Units, "mL/cm^3/min")
  expect_equal(out$k2$Units, "1/min")
  expect_equal(out$k2a$Units, "1/min")
  expect_equal(out$k2prime$Units, "1/min")
  expect_equal(out$VT$Units, "mL/cm^3")
  expect_equal(out$BPp$Units, "mL/cm^3")
  expect_equal(out$inpshift$Units, "min")

  # A ratio of like quantities says that it has no units, rather than staying
  # silent about them.
  expect_equal(out$BPnd$Units, "unitless")
  expect_equal(out$R1$Units, "unitless")
  expect_equal(out$SUVR$Units, "unitless")

  # vB is a volume over a volume: the percentage everyone quotes is this
  # multiplied by 100.
  expect_equal(out$vB$Units, "fraction")

  # A standard error is |SE / estimate|, so it is a fraction of the parameter
  # whatever that parameter's own units are. The written files name these
  # columns `-se`; the reports carry them as `.se` until then.
  expect_equal(out$BPnd.se$Units, "fraction")
  expect_equal(kinpar_units("K1-se")$`K1-se`$Units, "fraction")
  expect_equal(kinpar_units("VT-se")$`VT-se`$Units, "fraction")

  # Fit statistics and labels carry no quantity, and are left out rather than
  # given something made up.
  expect_false(any(c("AIC", "BIC", "RSS", "region") %in% names(out)))
})

test_that("the SUV outcomes are the conventional g/mL", {
  out <- kinpar_units(c("SUV", "SUV_ref", "SUV_AUC", "SUV_denominator"))

  # The dose is standardised to kBq and suv_denominator() puts the body mass in
  # grams, which is what makes the SUV the conventional g/mL.
  expect_equal(out$SUV$Units, "g/mL")
  expect_equal(out$SUV_ref$Units, "g/mL")
  expect_equal(out$SUV_AUC$Units, "g*min/mL")
  expect_equal(out$SUV_denominator$Units, "kBq/g")
})

test_that("the graphical analysis axes carry the units of their transformation", {
  out <- bids_column_units(
    list(Logan_x = "x", Logan_y = "y",
         refLogan_x = "x", refLogan_y = "y",
         Patlak_x = "x", Patlak_y = "y"),
    time_units = "min"
  )

  # Both Logan axes divide an integrated concentration by a concentration.
  expect_equal(out$Logan_x$Units, "min")
  expect_equal(out$Logan_y$Units, "min")
  expect_equal(out$refLogan_x$Units, "min")
  expect_equal(out$refLogan_y$Units, "min")

  # Patlak does that only on its x axis; its y axis is a volume ratio.
  expect_equal(out$Patlak_x$Units, "min")
  expect_equal(out$Patlak_y$Units, "mL/cm^3")
})

test_that("an analysis whose TACs are not kBq is converted, once", {
  root <- withr::local_tempdir()
  analysis <- file.path(root, "Primary_Analysis")
  pet_dir <- file.path(analysis, "sub-01", "pet")
  dir.create(pet_dir, recursive = TRUE)

  relative <- file.path("sub-01", "pet", "sub-01_desc-combinedregions_tacs.tsv")
  readr::write_tsv(
    tibble::tibble(region = c("Frontal", "Frontal"),
                   frame_mid = c(30, 90),
                   TAC = c(2000, 4000),
                   seg_meanTAC = c(1000, 3000)),
    file.path(analysis, relative)
  )

  # The shared sidecar, as the region definition step of an older petfit left it.
  jsonlite::write_json(
    list(radioactivity = list(Units = "Bq/mL"), time = list(Units = "s"),
         TAC = list(Description = "TAC", Units = "Bq/mL")),
    file.path(root, "desc-combinedregions_tacs.json"),
    auto_unbox = TRUE
  )

  first <- standardise_analysis_tac_units(analysis, relative)
  expect_true(first$converted)
  expect_equal(first$from_units, "Bq")

  converted <- readr::read_tsv(file.path(analysis, relative), show_col_types = FALSE)
  expect_equal(converted$TAC, c(2, 4))
  expect_equal(converted$seg_meanTAC, c(1, 3))

  # The analysis now describes itself as kBq, and everything downstream reads
  # that rather than the shared sidecar.
  expect_equal(petfit_tac_units(analysis)$radioactivity, "kBq/mL")

  # Running the step again must not divide by a further thousand.
  second <- standardise_analysis_tac_units(analysis, relative)
  expect_false(second$converted)
  expect_equal(
    readr::read_tsv(file.path(analysis, relative), show_col_types = FALSE)$TAC,
    c(2, 4)
  )
})

test_that("an analysis already in kBq is left alone", {
  root <- withr::local_tempdir()
  analysis <- file.path(root, "Primary_Analysis")
  pet_dir <- file.path(analysis, "sub-01", "pet")
  dir.create(pet_dir, recursive = TRUE)

  relative <- file.path("sub-01", "pet", "sub-01_desc-combinedregions_tacs.tsv")
  readr::write_tsv(tibble::tibble(TAC = c(2, 4)), file.path(analysis, relative))

  jsonlite::write_json(
    list(radioactivity = list(Units = "kBq/mL"), time = list(Units = "s")),
    file.path(root, "desc-combinedregions_tacs.json"),
    auto_unbox = TRUE
  )

  out <- standardise_analysis_tac_units(analysis, relative)
  expect_false(out$converted)
  # No sidecar of its own is written when there was nothing to record.
  expect_false(file.exists(file.path(analysis, "desc-combinedregions_tacs.json")))
  expect_equal(
    readr::read_tsv(file.path(analysis, relative), show_col_types = FALSE)$TAC,
    c(2, 4)
  )
})
