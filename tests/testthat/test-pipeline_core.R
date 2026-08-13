# A minimal datadef workspace: the combined TACs file the step reads, and a
# config supplying the Subsetting block. Both fit in a temp directory, and the
# cases below all return before any report is rendered.
setup_datadef_workspace <- function(subsetting, env = parent.frame()) {

  root <- tempfile("petfit-datadef-")
  petfit_dir <- file.path(root, "petfit")
  output_dir <- file.path(root, "analysis")
  dir.create(petfit_dir, recursive = TRUE)
  dir.create(output_dir, recursive = TRUE)
  withr::defer(unlink(root, recursive = TRUE), envir = env)

  tacs <- tibble::tibble(
    sub                   = rep(c("01", "02"), each = 2),
    ses                   = "test",
    trc                   = "pf974",
    rec                   = NA_character_,
    task                  = NA_character_,
    run                   = NA_character_,
    pet                   = rep(c("sub-01_ses-test", "sub-02_ses-test"), each = 2),
    InjectedRadioactivity = 180000,
    bodyweight            = 70,
    region                = rep(c("cortex", "amygdala"), times = 2),
    volume_mm3            = 1000,
    frame_start           = 0,
    frame_end             = 60,
    frame_dur             = 60,
    frame_mid             = 30,
    TAC                   = c(1, 2, 3, 4)
  )
  readr::write_tsv(tacs, file.path(petfit_dir, "desc-combinedregions_tacs.tsv"))

  config_path <- file.path(output_dir, "desc-petfitoptions_config.json")
  jsonlite::write_json(list(Subsetting = subsetting), config_path,
                       pretty = TRUE, auto_unbox = TRUE)

  list(config_path = config_path, output_dir = output_dir,
       petfit_dir = petfit_dir)
}

test_that("execute_datadef_step reports why subsetting failed", {

  ws <- setup_datadef_workspace(list(
    sub = "", ses = "", task = "", trc = "", rec = "", run = "",
    Regions = "cortex; amygdala, striatum"
  ))

  result <- execute_datadef_step(
    config_path = ws$config_path,
    output_dir  = ws$output_dir,
    petfit_dir  = ws$petfit_dir
  )

  expect_false(result$success)

  # The reason has to survive the tryCatch handler and reach the returned
  # result: the batch pipeline logs `step_result$message`, so an empty one means
  # "Step datadef failed" with nothing to act on.
  expect_match(result$message, "may not contain commas")
  expect_match(result$message, "amygdala, striatum")
})

test_that("execute_datadef_step reports an unmatched subsetting value", {

  ws <- setup_datadef_workspace(list(
    sub = "01; 99", ses = "", task = "", trc = "", rec = "", run = "",
    Regions = ""
  ))

  result <- execute_datadef_step(
    config_path = ws$config_path,
    output_dir  = ws$output_dir,
    petfit_dir  = ws$petfit_dir
  )

  expect_false(result$success)
  expect_match(result$message, "sub: \"99\"")
  expect_match(result$message, "Available \\(2\\): 01, 02")
})

test_that("execute_datadef_step applies an exclusion from the config", {

  # Excluding every subject leaves nothing, which proves the "-" survived the
  # trip from config JSON through parsing into the filter. Without negation
  # these same values would have matched everything.
  ws <- setup_datadef_workspace(list(
    sub = "-01;02", ses = "", task = "", trc = "", rec = "", run = "",
    Regions = ""
  ))

  result <- execute_datadef_step(
    config_path = ws$config_path,
    output_dir  = ws$output_dir,
    petfit_dir  = ws$petfit_dir
  )

  expect_false(result$success)
  expect_match(result$message, "No data matches the subsetting criteria")
})

# Every execute_*_step() wraps its body in tryCatch and reports failures by
# setting result$message from the error handler. `result$message <- v` inside a
# handler is a *local* assignment -- it rebinds a copy in the handler's own
# frame -- so the returned result kept message = "". notify() and cat() run
# inside that same handler and so looked correct, which is why this went
# unnoticed: only callers reading the return value saw the gap, and the batch
# runner (docker_functions.R) is the main one. It logged "Step <name> failed"
# with no reason attached.

test_that("every pipeline step returns why it failed", {

  missing_config <- file.path(tempdir(), "petfit-no-such-config.json")
  expect_false(file.exists(missing_config))

  # delay and model parse the config inside the outer tryCatch, so an
  # unreadable config reaches the handler
  delay <- execute_delay_step(missing_config, tempdir())
  expect_false(delay$success)
  expect_match(delay$message, "^Error generating delay report:")

  model <- execute_model_step(missing_config, "1", tempdir())
  expect_false(model$success)
  expect_match(model$message, "^Error fitting Model 1 :")

  # weights and reference TAC reach their handler via list.files() instead:
  # their report generation is caught by an inner tryCatch and handled in the
  # main body, so the outer handler only sees earlier failures.
  weights <- execute_weights_step(missing_config, NA)
  expect_false(weights$success)
  expect_match(weights$message, "^Could not generate weights report:")

  reftac <- execute_reference_tac_step(missing_config, NA)
  expect_false(reftac$success)
  expect_match(reftac$message, "^Could not generate reference TAC report:")
})
