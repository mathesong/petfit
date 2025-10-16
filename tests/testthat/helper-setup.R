# Helper setup file that runs before all tests
# This ensures the here package is available and loaded

library(here)

# Set the root directory for here() to work properly
if (!here::here() == getwd()) {
  # If we're not in the package root, try to find it
  pkg_root <- here::here()
  if (file.exists(file.path(pkg_root, "DESCRIPTION"))) {
    setwd(pkg_root)
  }
}
