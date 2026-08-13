# petfit (development version)

## Subsetting

* **Subsetting values are now validated.** A value in `sub`, `ses`, `task`,
  `trc`, `rec`, `run` or `Regions` that matches nothing in the data is an error
  naming the offending value and listing what is available, instead of silently
  filtering to nothing. This is a behaviour change: configurations that
  previously ran on a narrower dataset than requested will now stop and say so.

* **Commas are rejected in subsetting fields.** Values are separated by `;`, so
  `"H_Amygdala; H_Striatum, H_CerebellarWM"` was two values rather than three —
  the second matched no region and was dropped without comment, and only the
  amygdala was analysed. Such input now errors and suggests the intended split.

* **New: exclude rather than include by prefixing a field with `-`.** Writing
  `-test;retest` in `ses` selects every session except those two. The prefix
  applies to the whole field, so a field is either an inclusion or an exclusion,
  never a mixture; each field reads its own prefix. Note that measurements
  lacking the entity entirely are *kept* by an exclusion — a measurement with no
  session is indeed not `ses-test` — whereas an inclusion drops them.

* An excluded value matching nothing **warns** rather than errors: the analysis
  is complete rather than wrong, but you did not remove what you thought you had.

* The t\* finder's `sub`/`ses` filters get the same validation, exclusion syntax
  and comma checking. Previously a partially-matching filter there quietly
  reduced the selection, and a filter naming an entity absent from the study was
  ignored altogether.

## Bug fixes

* **Every pipeline step now returns the reason it failed** in `result$message`.
  All five `execute_*_step()` functions set that message from inside a
  `tryCatch` error handler, where `result$message <- ...` rebinds a copy local
  to the handler and leaves the returned value empty. `notify()` and `cat()` run
  in the same handler, so interactive use looked correct; only callers reading
  the return value were affected — chiefly the batch and Docker runners, which
  logged a failed step with no explanation attached.

## Containers

* Both containers now set a UTF-8 locale explicitly (`LC_ALL=C.UTF-8` and a
  matching `LANG`). The Apptainer definition set `LC_ALL=C`, which overrode the
  base image's UTF-8 setting and produced "strings not representable in native
  encoding" warnings for non-ASCII region names, participant fields and paths.
  The Dockerfile relied on whatever the base image happened to provide.
