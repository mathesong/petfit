# The container versions are written by hand — the Docker image's tag in the
# push script, the Apptainer image's Version label — and neither has any way of
# noticing when DESCRIPTION moves on, so a release can go out labelled as the
# version before it. These are the reminders.
#
# docker/ and apptainer/ are both in .Rbuildignore, so they are absent from a
# built package: the tests have nothing to check unless they are being run from
# the source tree.

package_version_in_description <- function(root) {
  unname(read.dcf(file.path(root, "DESCRIPTION"), fields = "Version")[1, 1])
}

test_that("the Docker push script's VERSION matches DESCRIPTION", {
  root <- test_path("..", "..")
  script <- file.path(root, "docker", "build_and_push.sh")
  skip_if_not(file.exists(script), "docker/ is not in the built package")

  version_line <- grep("^VERSION=", readLines(script), value = TRUE)
  expect_length(version_line, 1)

  # VERSION="v0.2.2" -> v0.2.2, whether or not it is quoted.
  tagged <- trimws(sub("^VERSION=", "", version_line))
  tagged <- gsub("^[\"']|[\"']$", "", tagged)

  # If this fails, set VERSION in docker/build_and_push.sh to the DESCRIPTION
  # version, with the leading "v" the image tags use.
  expect_equal(tagged, paste0("v", package_version_in_description(root)))
})

test_that("the Apptainer definition's Version label matches DESCRIPTION", {
  root <- test_path("..", "..")
  definition <- file.path(root, "apptainer", "petfit.def")
  skip_if_not(file.exists(definition), "apptainer/ is not in the built package")

  version_line <- grep("^\\s*Version\\s", readLines(definition), value = TRUE)
  expect_length(version_line, 1)

  # A %labels entry, so it is bare rather than tagged: "Version 0.2.2".
  labelled <- trimws(sub("^\\s*Version\\s+", "", version_line))

  # If this fails, set Version in the %labels block of apptainer/petfit.def to
  # the DESCRIPTION version.
  expect_equal(labelled, package_version_in_description(root))
})
