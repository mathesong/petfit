# The t* finder is a second subsetting path: it filters post-datadef individual
# files rather than the combined TACs table, so it needs its own validation.

tstar_measurements <- function(with_ses = TRUE) {
  m <- tibble::tibble(
    path = c("a.tsv", "b.tsv", "c.tsv"),
    stem = c("sub-01", "sub-02", "sub-03"),
    sub  = c("01", "02", "03")
  )
  if (with_ses) {
    m$ses <- c("test", "test", "retest")
  }
  m
}

test_that(".tstar_select_measurements errors on a partially unmatched filter", {

  m <- tstar_measurements()

  # Previously this silently returned only sub-01: the run went ahead on fewer
  # measurements than asked for, and only a completely empty result complained.
  expect_error(
    .tstar_select_measurements(m, "subset", "01;99", "", 5L),
    "sub: \"99\""
  )

  # The comma check applies here too
  expect_error(
    .tstar_select_measurements(m, "subset", "01, 02", "", 5L),
    "may not contain commas"
  )
})

test_that(".tstar_select_measurements errors when the entity is absent entirely", {

  # kinfitr::bids_filename_attributes() spreads only the entities a filename
  # carries, so a sessionless study yields no `ses` column at all. That used to
  # make the filter a silent no-op, quietly widening the selection.
  m <- tstar_measurements(with_ses = FALSE)

  expect_error(
    .tstar_select_measurements(m, "subset", "", "test", 5L),
    "no row in the data carries a ses value"
  )
})

test_that(".tstar_select_measurements selects matching measurements", {

  m <- tstar_measurements()

  result <- .tstar_select_measurements(m, "subset", "01;02", "", 5L)
  expect_equal(result$sub, c("01", "02"))

  result <- .tstar_select_measurements(m, "subset", "", "retest", 5L)
  expect_equal(result$sub, "03")

  # Both filters together
  result <- .tstar_select_measurements(m, "subset", "01;03", "test", 5L)
  expect_equal(result$sub, "01")
})

test_that(".tstar_select_measurements honours the exclusion prefix", {

  m <- tstar_measurements()

  result <- .tstar_select_measurements(m, "subset", "-02", "", 5L)
  expect_equal(result$sub, c("01", "03"))

  result <- .tstar_select_measurements(m, "subset", "", "-test", 5L)
  expect_equal(result$sub, "03")

  # An exclusion matching nothing warns, and excludes nothing
  expect_warning(
    result <- .tstar_select_measurements(m, "subset", "-99", "", 5L),
    "nothing was excluded"
  )
  expect_equal(result$sub, c("01", "02", "03"))
})

test_that(".tstar_select_measurements leaves the other selection modes alone", {

  m <- tstar_measurements()

  # Filters are ignored outside "subset" mode, including invalid ones
  expect_equal(nrow(.tstar_select_measurements(m, "all", "01, 02", "", 5L)), 3)

  expect_equal(nrow(.tstar_select_measurements(m, "random", "", "", 2L)), 2)
  expect_equal(nrow(.tstar_select_measurements(m, "random", "", "", 99L)), 3)
})
