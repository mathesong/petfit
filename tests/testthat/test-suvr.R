test_that("suvr computes the frame-duration weighted ratio over all frames", {
  t_tac <- c(0.5, 1.5, 3, 6)
  dur <- c(1, 1, 2, 4)
  roitac <- c(2, 4, 6, 8)
  reftac <- c(1, 2, 3, 4)

  res <- suvr(t_tac = t_tac, reftac = reftac, roitac = roitac, dur = dur)

  int_roi <- sum(roitac * dur)
  int_ref <- sum(reftac * dur)

  expect_equal(res$par$intTAC, int_roi)
  expect_equal(res$par$intTAC_ref, int_ref)
  expect_equal(res$par$SUVR, int_roi / int_ref)
  expect_equal(res$par$window_duration, sum(dur))
  expect_equal(res$par$n_frames, 4L)
  expect_equal(res$par$meanTAC, int_roi / sum(dur))
  expect_true(all(res$tacs$included))
})

test_that("SUV is NA without a dose, and SUVR is unaffected by one", {
  t_tac <- c(0.5, 1.5, 3, 6)
  dur <- c(1, 1, 2, 4)
  roitac <- c(2, 4, 6, 8)
  reftac <- c(1, 2, 3, 4)

  no_dose <- suvr(t_tac = t_tac, reftac = reftac, roitac = roitac, dur = dur)
  with_dose <- suvr(t_tac = t_tac, reftac = reftac, roitac = roitac, dur = dur,
                    injRad = 200, bodymass = 80)

  expect_true(is.na(no_dose$par$SUV))
  expect_true(is.na(no_dose$par$intSUV))

  # The dose cancels in the ratio.
  expect_equal(no_dose$par$SUVR, with_dose$par$SUVR)

  denominator <- 200 / 80
  expect_equal(with_dose$par$SUV, no_dose$par$meanTAC / denominator)
  expect_equal(with_dose$par$intSUV, no_dose$par$intTAC / denominator)
})

test_that("a frame window restricts the integral to those frames", {
  t_tac <- c(0.5, 1.5, 3, 6)
  dur <- c(1, 1, 2, 4)
  roitac <- c(2, 4, 6, 8)
  reftac <- c(1, 2, 3, 4)

  res <- suvr(t_tac = t_tac, reftac = reftac, roitac = roitac, dur = dur,
              frameStartEnd = c(2, 3))

  expect_equal(res$par$intTAC, sum(roitac[2:3] * dur[2:3]))
  expect_equal(res$par$intTAC_ref, sum(reftac[2:3] * dur[2:3]))
  expect_equal(res$par$window_duration, sum(dur[2:3]))
  expect_equal(res$par$n_frames, 2L)
  expect_equal(res$tacs$included, c(FALSE, TRUE, TRUE, FALSE))
  # Excluded frames contribute no duration.
  expect_equal(res$tacs$window_duration, c(0, 1, 2, 0))
})

test_that("a time window selects whole frames by midpoint, as kinfitr does", {
  t_tac <- c(0.5, 1.5, 3, 6)
  dur <- c(1, 1, 2, 4)
  roitac <- c(2, 4, 6, 8)
  reftac <- c(1, 2, 3, 4)

  # Midpoints 1.5 and 3 fall within [1, 4]; 0.5 and 6 do not.
  res <- suvr(t_tac = t_tac, reftac = reftac, roitac = roitac, dur = dur,
              timeStartEnd = c(1, 4))

  expect_equal(res$tacs$included, c(FALSE, TRUE, TRUE, FALSE))
  expect_equal(res$par$intTAC, sum(roitac[2:3] * dur[2:3]))
  # The whole frame counts, so the duration is the frames' duration and not the
  # 3 minutes spanned by the requested window.
  expect_equal(res$par$window_duration, sum(dur[2:3]))
})

test_that("the integral agrees with kinfitr::SUV called directly", {
  t_tac <- c(0.5, 1.5, 3, 6, 10)
  dur <- c(1, 1, 2, 4, 4)
  roitac <- c(2, 4, 6, 8, 7)
  reftac <- c(1, 2, 3, 4, 3.5)

  res <- suvr(t_tac = t_tac, reftac = reftac, roitac = roitac, dur = dur,
              frameStartEnd = c(2, 4), injRad = 150, bodymass = 75)

  direct <- kinfitr::SUV(tac = roitac, t_tac = t_tac, dur_tac = dur,
                         injRad = 150, bodymass = 75,
                         frameStartEnd = c(2, 4))

  expect_equal(res$par$intSUV, direct$par$intSUV)
})

test_that("one-sided windows are honoured", {
  t_tac <- c(0.5, 1.5, 3, 6)
  dur <- c(1, 1, 2, 4)
  roitac <- c(2, 4, 6, 8)
  reftac <- c(1, 2, 3, 4)

  from_frame_2 <- suvr(t_tac = t_tac, reftac = reftac, roitac = roitac, dur = dur,
                       frameStartEnd = c(2, NA))
  expect_equal(from_frame_2$tacs$included, c(FALSE, TRUE, TRUE, TRUE))

  until_frame_2 <- suvr(t_tac = t_tac, reftac = reftac, roitac = roitac, dur = dur,
                        frameStartEnd = c(NA, 2))
  expect_equal(until_frame_2$tacs$included, c(TRUE, TRUE, FALSE, FALSE))

  after_2_min <- suvr(t_tac = t_tac, reftac = reftac, roitac = roitac, dur = dur,
                      timeStartEnd = c(2, NA))
  expect_equal(after_2_min$tacs$included, c(FALSE, FALSE, TRUE, TRUE))
})

test_that("a zero window means all frames, matching how the apps encode 'none'", {
  t_tac <- c(0.5, 1.5, 3, 6)
  dur <- c(1, 1, 2, 4)
  roitac <- c(2, 4, 6, 8)
  reftac <- c(1, 2, 3, 4)

  res <- suvr(t_tac = t_tac, reftac = reftac, roitac = roitac, dur = dur,
              timeStartEnd = c(0, 0))
  expect_true(all(res$tacs$included))
})

test_that("window bounds come from the frame edges when supplied", {
  t_tac <- c(0.5, 1.5, 3, 6)
  frame_start <- c(0, 1, 2, 4)
  frame_end <- c(1, 2, 4, 8)
  dur <- c(1, 1, 2, 4)
  roitac <- c(2, 4, 6, 8)
  reftac <- c(1, 2, 3, 4)

  res <- suvr(t_tac = t_tac, reftac = reftac, roitac = roitac, dur = dur,
              frame_start = frame_start, frame_end = frame_end,
              frameStartEnd = c(2, 3))

  expect_equal(res$par$window_start, 1)
  expect_equal(res$par$window_end, 4)
})

test_that("an empty time window is an error rather than a silent NaN", {
  t_tac <- c(0.5, 1.5, 3, 6)
  dur <- c(1, 1, 2, 4)
  roitac <- c(2, 4, 6, 8)
  reftac <- c(1, 2, 3, 4)

  expect_error(
    suvr(t_tac = t_tac, reftac = reftac, roitac = roitac, dur = dur,
         timeStartEnd = c(20, 30)),
    "No frames fall within"
  )
})

test_that("mismatched input lengths are rejected", {
  expect_error(
    suvr(t_tac = c(1, 2, 3), reftac = c(1, 2), roitac = c(1, 2, 3), dur = c(1, 1, 1)),
    "same length"
  )
})

test_that("suv_denominator follows the data definition report's rule", {
  both <- suv_denominator(c(100, 200), c(70, 80))
  expect_equal(both$mode, "SUV")
  expect_equal(both$bodymass, c(70, 80))

  dose_only <- suv_denominator(c(100, 200), c(70, NA))
  expect_equal(dose_only$mode, "SUV_bw70")
  expect_equal(dose_only$bodymass, 70)

  no_dose <- suv_denominator(c(100, NA), c(70, 80))
  expect_equal(no_dose$mode, "none")
  expect_true(is.na(no_dose$bodymass))

  missing <- suv_denominator(NULL, NULL)
  expect_equal(missing$mode, "none")
})

test_that("plot.suvr shades only the included frames", {
  t_tac <- c(0.5, 1.5, 3, 6)
  dur <- c(1, 1, 2, 4)
  roitac <- c(2, 4, 6, 8)
  reftac <- c(1, 2, 3, 4)

  res <- suvr(t_tac = t_tac, reftac = reftac, roitac = roitac, dur = dur,
              frameStartEnd = c(2, 3))
  p <- plot(res, roiname = "Putamen")

  expect_s3_class(p, "ggplot")
  # The ribbon layer carries only the two included frames, for each of the two
  # regions.
  ribbon_data <- p$layers[[1]]$data
  expect_equal(nrow(ribbon_data), 4)
  expect_true(all(ribbon_data$included))
  expect_setequal(as.character(unique(ribbon_data$Region)), c("Putamen", "Reference"))
})
