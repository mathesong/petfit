# The SUV/SUVR estimator itself lives in kinfitr (kinfitr::suvr), and is tested
# there. What petfit owns is the cohort-wide decision about how SUV should be
# calculated, and the wiring of that decision into kinfitr::suvr().

test_that("suv_denominator follows the data definition report's rule", {
  # The body mass comes back in grams, so that dose/mass gives the conventional
  # g/mL SUV rather than a kg/mL one a thousand times smaller.
  both <- suv_denominator(c(100, 200), c(70, 80))
  expect_equal(both$mode, "SUV")
  expect_equal(both$bodymass, c(70000, 80000))

  dose_only <- suv_denominator(c(100, 200), c(70, NA))
  expect_equal(dose_only$mode, "SUV_bw70")
  expect_equal(dose_only$bodymass, 70000)

  no_dose <- suv_denominator(c(100, NA), c(70, 80))
  expect_equal(no_dose$mode, "none")
  expect_true(is.na(no_dose$bodymass))

  missing <- suv_denominator(NULL, NULL)
  expect_equal(missing$mode, "none")

  expect_equal(suv_denominator(c(100, 200), c(NA, NA), bodymass_default = 75)$bodymass, 75000)
})

test_that("suv_denominator explains its choice", {
  expect_match(suv_denominator(c(100, 200), c(70, 80))$label, "injected radioactivity and body weight")
  expect_match(suv_denominator(c(100, 200), c(70, NA))$label, "70 kg")
  expect_match(suv_denominator(c(100, NA), c(70, 80))$label, "the dose cancels")
})

test_that("the modes map onto kinfitr::suvr as the reports rely on", {
  t_tac <- c(0.5, 1.5, 3, 6)
  dur <- c(1, 1, 2, 4)
  roitac <- c(2, 4, 6, 8)
  reftac <- c(1, 2, 3, 4)

  # "none" leaves the dose arguments at 1, so the outcomes are in units of
  # radioactivity concentration. The report drops the SUV columns on the mode,
  # and SUV_denominator records that nothing was applied.
  no_dose <- suv_denominator(c(NA_real_), c(70))
  expect_equal(no_dose$mode, "none")

  fit_none <- kinfitr::suvr(t_tac, reftac, roitac, dur = dur,
                            injRad = 1, bodymass = 1)
  expect_equal(fit_none$par$SUV_denominator, 1)
  expect_true(is.finite(fit_none$par$SUVR))

  # "SUV_bw70" substitutes the assumed body mass.
  bw70 <- suv_denominator(c(150), c(NA_real_))
  fit_bw70 <- kinfitr::suvr(t_tac, reftac, roitac, dur = dur,
                            injRad = 150, bodymass = bw70$bodymass)
  expect_equal(fit_bw70$par$SUV_denominator, 150 / 70000)
  expect_equal(fit_bw70$par$SUV, fit_none$par$SUV / (150 / 70000))

  # The dose cancels, so the SUVR is the same either way.
  expect_equal(fit_bw70$par$SUVR, fit_none$par$SUVR)
})
