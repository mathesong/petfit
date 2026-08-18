# petfit 0.2.0

## Reproducibility and provenance

* **Reports set a fixed seed.** Model fitting uses `multstart`, which draws its
  starting parameter sets at random. `furrr_options(seed = TRUE)` made those
  draws parallel-safe but not reproducible — it derives its streams from
  whatever state the session happens to be in — so two runs of an identical
  configuration could differ. Measured on one PDE4B measurement, a region's
  V<sub>T</sub> moved 13.7% between runs, one of them converging with `k3`
  pinned at its upper bound and more than double the residual sum of squares.
  Every report now calls `set.seed(123)` alongside its library calls, which
  makes a re-run reproduce exactly and, because the streams are derived
  per-element, gives the same answer whatever `cores` is set to. **This changes
  numerical output once:** re-running an existing analysis will shift it
  slightly. Vary the seed deliberately if you want to know how seed-dependent a
  fit is.

* **petfit records which version wrote what, and says so when they disagree.**
  Saved configurations gain `petfit_version`, and
  `desc-combinedregions_tacs.json` gains a BIDS `GeneratedBy` entry. The data
  definition step checks both and warns — never stops — when either predates the
  running version or records no version at all, recommending that every step
  including region definition be re-run.

  This exists because measurement identifiers used to be derived from whichever
  entities varied across the cohort and are now built from each measurement's
  own entities. A combined TACs file written by an older version carries the old
  identifiers, nothing about it looks wrong, and a step that builds the new ones
  from the same file's path simply fails to match them.

## Cleanup safety

* **The data definition cleanup no longer follows filesystem links.**
  `list.files(recursive = TRUE)` descends *through* a linked directory and
  reports the files on the far side, so an analysis folder containing a link to
  an external source directory had that directory's contents deleted, and the
  link removed behind them. Enumeration now stops at a link: it is removed as a
  link, and whatever it points at is left alone. A linked
  `*_inputfunction.tsv` is kept exactly as a real one is.

  Classification is done through **fs** rather than base R, which cannot answer
  the question portably: `Sys.readlink()` is documented as reporting nothing on
  Windows even though NTFS has both symbolic links and junctions, and a
  junction presents to directory-walking code as an ordinary directory while
  redirecting traversal elsewhere. The rule is now positive -- an entry is
  descended into only once established as a real directory whose canonical path
  lies inside the analysis folder. Anything unresolvable, unclassifiable, or
  resolving outside it stops the cleanup with the folder untouched, and a link
  that will not delete is an error rather than a silent undercount. The policy
  is *never follow a link*, so a link to a sibling directory within the
  analysis is not followed either.

* **A directory holding only hidden files is no longer treated as empty.**
  `list.files()` hides dotfiles by default, so such a directory read as empty
  and was removed with a recursive delete that took the hidden files with it.
  Dotfiles are now enumerated and removed as the ordinary derived-folder
  entries they are, and only genuinely empty directories are pruned.


## Report warnings

* **Warnings from the fitting chunks now appear in the report.** They were
  routed to the console and left out of the document entirely. A warning such as
  "Fitted parameters are hitting upper or lower limit bounds" qualifies the
  numbers printed directly beneath it, so a reader looking at those numbers
  needs to see it there. Chunks opt in with `report_warnings = TRUE`; everything
  else — deprecation notices and the like — still goes to the console alone.

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

## Measurement identifiers

* **A measurement's identifier is now built from its own filename, and nothing
  else.** Identifiers were previously assembled from the attributes that varied
  across the analysis at hand, so identity depended on the cohort: the same
  scan was `sub-pfmdd08` in one analysis and `sub-pfmdd08_ses-test` in a larger
  one, growing a study orphaned the files written under the old name, and an
  analysis of a single measurement produced an identifier matching none of its
  own files — the empty PET dropdown. The new `pet_key()` derives the
  identifier from the measurement's own path; it is exactly the stem its output
  files are written under, so tying outputs back to measurements is no longer a
  lookup that can fail.

* **Display names are separate from identity.** `pet_label()` shortens a set of
  keys for display by dropping the parts they all share. It is cohort-dependent
  by design, which is safe only because it is never persisted: keys go into
  filenames, joins and saved configurations; labels only ever reach the screen.

* **The region-definition pipeline builds identifiers the same way.** It
  previously constructed the `pet` column — and with it the filename stems of
  every individual TACs file — from only the attributes that varied across the
  dataset, so the identifiers `pet_key()` reads back were themselves
  cohort-dependent at the point of writing. Identifiers are now built from
  each measurement's own entities, in BIDS filename order, whatever the rest
  of the dataset looks like. Filenames from earlier versions may therefore
  change on regeneration (a single-session study's files gain their `ses`),
  which rerunning the analysis start to finish resolves.

* `get_pet_identifiers()` is replaced by `pet_key()`, and
  `attributes_to_title()` is deprecated with a 2027 removal notice.

## Weights

* **Weights are now computed within each measurement.** *This changes numerical
  results.* Both weighting paths previously operated on the whole analysis at
  once: the predefined methods received every measurement's frames concatenated
  into a single curve, and the custom-formula path took its maximum, outlier
  check and minimum-weight correction across all measurements together. A
  subject's weights — and the delay fits and outcome parameters downstream —
  therefore depended on which other measurements were analysed alongside it.
  Weights are now identical whether a measurement is analysed alone or in a
  cohort.

## Data definition

* **Rerunning data definition clears the analysis folder's derived outputs.**
  A new data definition changes the data every later step consumes, so the
  individual TACs files, weights, delay fits, model results and reports are
  all removed and must be recalculated; only the analysis configuration is
  kept. Previously the cleanup compared filename stems against the
  measurements being kept, which deleted model outputs it did not understand
  on every run while sparing stale weights it did — and, when identifiers
  moved, could delete results for measurements still in the analysis.
  `cleanup_individual_tacs_files()` accordingly now takes only the folder to
  clear.

* **`*_inputfunction.tsv`/`.json` files survive the clearing.** They are a
  supported blood *source* — `determine_blood_source()` looks for them in the
  analysis folder, and they may have been placed there by hand — and the ones
  petfit writes itself derive from the BIDS blood data, which a data
  definition does not change. Either way they are not stale.

* **The clearing refuses a folder that does not look like an analysis
  folder** — one containing files but no `desc-*_config.json`. A mispointed
  path (the petfit derivatives root, `"."`) would otherwise be emptied
  wholesale.

## Bug fixes

* **Every pipeline step now returns the reason it failed** in `result$message`.
  All five `execute_*_step()` functions set that message from inside a
  `tryCatch` error handler, where `result$message <- ...` rebinds a copy local
  to the handler and leaves the returned value empty. `notify()` and `cat()` run
  in the same handler, so interactive use looked correct; only callers reading
  the return value were affected — chiefly the batch and Docker runners, which
  logged a failed step with no explanation attached.

* **`pet_key()` strips the analysis folder from paths literally rather than as
  a regular expression.** An analysis folder whose path contains a regex
  metacharacter — a `+`, `(` or `[` in a directory name — could previously
  produce wrong keys or an error.

* petfit now requires **dplyr >= 1.1.1**: the report templates declare join
  cardinality with `relationship = "many-to-one"`, which older dplyr versions
  reject as an unused argument.

* petfit now requires **kinfitr >= 0.9.3**, which supplies the parsers this
  version is built on (`bids_parse_derivatives()`, `bids_parse_filenames()`);
  an older kinfitr would install successfully and then fail at runtime.

* Region description summaries now use kinfitr's derivative parser instead of
  the raw-study parser, so they no longer carry entity values the old parser
  substituted for absent entities.

* **File attributes read `sub` and `ses` from directories as well as
  filenames.** petfit's derivatives put the session in the path but not the
  filename, and reducing a path to its basename merged two sessions of one
  subject into a single measurement. Only whole `sub-`/`ses-` path segments
  count — the entities BIDS names directories after — so unrelated path
  components cannot inject entities, and a directory contradicting the
  filename is an error rather than a silent pick.

## Reports

* **Warnings raised while rendering a report now reach the console (or the step
  log under `save_logs = TRUE`) instead of being discarded.** The templates set
  `warning = FALSE`, which — contrary to knitr's documentation, which says such
  warnings are "printed in the console instead of the output document" — throws
  them away entirely. This mattered because dplyr warns when a join finds an
  unexpected many-to-many relationship, which is exactly what a duplicated
  record silently multiplying TAC rows looks like.

  Warnings are *not* written into the reports, which would make them unreadable.
  A knitr hook (`divert_report_warnings()`, called from each template's setup
  chunk) diverts them to `stderr()` and puts nothing in the document.

* **The blood-derived joins declare their expected shape.** The joins onto
  blood, delay and blood-volume data state `relationship = "many-to-one"`, so a
  duplicated record now stops the run with a clear message instead of silently
  multiplying every region's TAC rows. Joins whose right-hand side legitimately
  holds several rows per measurement — weights, segmentations, reference TACs —
  are deliberately left unconstrained.

* **The model templates no longer assume every entity column exists.** kinfitr
  no longer substitutes `ses`, `task`, `trc`, `run` or `rec` for studies that
  do not use them, so the templates select entity columns tolerantly with
  `any_of()`; the genuinely required columns (`pet`, `region`, `inpshift`,
  `fitvals`) remain strict and still error if absent.

## Model artifact naming

* **Model artifacts are now named `model-2TCM` rather than `model_2TCM`.** The
  underscore form is not a BIDS entity at all -- an underscore separates
  entities, so a parser saw no `model` key and could not tie an artifact back to
  the model that produced it. Affects all 11 model report templates, at the
  study-level TSV and both per-pet artifacts (parameters and fitted TACs), plus
  their JSON sidecars.

* The irreversible two-tissue model is emitted as `model-2TCMirr`. It is called
  `2TCM_irr` everywhere else in petfit, but that cannot be a BIDS label for the
  same reason -- the underscore would split it.

* Artifacts written by an earlier version keep their old names. Nothing reads
  them, so they are inert; delete them if they get in the way.

## Containers

* Both containers now set a UTF-8 locale explicitly (`LC_ALL=C.UTF-8` and a
  matching `LANG`). The Apptainer definition set `LC_ALL=C`, which overrode the
  base image's UTF-8 setting and produced "strings not representable in native
  encoding" warnings for non-ASCII region names, participant fields and paths.
  The Dockerfile relied on whatever the base image happened to provide.
