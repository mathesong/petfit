# petfit 0.2.2

## Injected radioactivity

* **Fixed: an unlabelled dose was silently treated as kBq.** A TACs sidecar with
  `InjectedRadioactivity` but no `InjectedRadioactivityUnits` had its value
  passed through untouched. It is now automatically read as MBq, and warns once
  per measurement that it has assumed this.

* **That warning comes from the parent process.** Region definition combines its
  file groups in parallel, and a warning raised inside a furrr worker is
  deduplicated against nothing, so a measurement warned once per segmentation.
  The extractors report what they assumed in `AssumedDoseUnitsFor`, and the
  parent warns once for each measurement when the groups come back.

## Test data

* **The testing ds004869 dataset's `InjectedRadioactivityUnits` is corrected from `Bq`
  to `kBq`.** The dataset declares Bq but the values are kBq, on the evidence of
  its own `RadionuclideTotalDose` and `InjectedMass` × `SpecificRadioactivity`.
  `prepare_testdata.sh` applies the correction; remove it once the dataset is
  fixed upstream.

## Units in the JSON sidecars

* **Every output sidecar now states its units, in the BIDS data dictionary
  form**: each column is an object with a `Description` and, where it has them,
  under `Units`. The units are read from
  `desc-combinedregions_tacs.json` rather than asserted in each report;
  `petfit_tac_units()` is the accessor.

* **The frame times are not on the same base throughout, and now say so**: the
  TAC files record seconds, as BIDS does, while the models are fitted in minutes
  and write their fitted values out in minutes.

* **A sidecar is now produced for the target region TACs**, which previously had
  none.

* **The kinpar sidecars carry the units of the outcome parameters**: `mL/cm^3`
  for the distribution volumes, `1/min` for the rate constants, `mL/cm^3/min`
  for `K1` and `Ki`, minutes for the times. `BPnd`, `R1` and `SUVR` are ratios
  of like quantities and say so, as `unitless`; `vB` is a `fraction`, the blood
  volume of the tissue over its total volume, which is the percentage everyone
  quotes divided by 100. A standard error is a `fraction` too, whatever the
  parameter it belongs to, since kinfitr reports it as `|SE / estimate|`. The
  goodness-of-fit columns carry no quantity and are given no entry.

* **The delay sidecar states that its estimate is in minutes**, with its sign
  convention: a positive `blood_timeshift` shifts the blood data later. Thanks
  to @pwighton (#58).

* **Fixed: the model sidecars were a JSON array, not an object.** Every
  `_kinpar.json` and fitted-values sidecar was written as `[ { ... } ]`, which a
  parser expecting a BIDS sidecar would reject.

## Inherited parameter loading

* **Fixed: the analysis folder's own path was being read as BIDS entities.** The
  chunks which inherit a delay, a vB or a k2' handed a full path to
  `bids_filename_attributes()`, so every hyphenated directory above the analysis
  folder became a column — and one colliding with a real entity, `rec-test` say,
  produced a second `rec` which acted as a join key and could silently drop
  rows. They now read the basename.

* **The `model` entity of the inherited file no longer follows it out.**
  Inheriting k2' from an MRTM1 fit left a `model` column reading `MRTM1` in the
  MRTM2 kinpar, naming the wrong model.

## MRTM1 and MRTM2

* **`k2a` now appears in the parameter histograms.** It was written to the
  kinpar TSVs but never plotted, because the histograms select by name. MRTM1
  now shows `R1`, `k2`, `k2a`, `BPnd` and `k2prime`; MRTM2 shows `R1`, `k2a` and
  `BPnd` — not `k2`, which there is `R1` times the k2' prior.

## SUV and SUVR

* **New: `SUVR`, a reference-tissue outcome reporting both SUV and SUVR.** Where
  the kinetic models fit a curve, this one integrates: the target region's area
  under the TAC over a window, over the reference region's area over the same
  window. It needs no blood data, so it sits in the reference tissue app. The
  window is set under **TAC Subset Selection**, "None" integrating the whole TAC
  as static data wants, and includes **whole frames whose midpoint falls inside
  it**, following `kinfitr::suv()`. Thanks to @mnoergaard, whose PR (#37) this
  is built on.

* **SUVR is always available; SUV is not.** The ratio cancels the dose and body
  weight, but SUV needs them: it is reported only when the injected
  radioactivity is known for every measurement, falling back to an assumed 70 kg
  when only the dose is. Which case applied is recorded.

* **An assumed body weight is stated as a warning.** The 70 kg is applied to
  *every* measurement, including those whose weight is known, so that SUV means
  the same thing across the cohort. Both the SUVR and data definition reports
  now say so in bold.

* **The estimation is `kinfitr::suvr()`**, so the report, the sandbox and any
  downstream script resolve a window identically; petfit adds only
  `suv_denominator()`. The outcomes are `SUVR`; `SUV` and `SUV_ref`; `SUV_AUC`
  and `SUV_ref_AUC`, whose ratio is the SUVR; `SUV_denominator`; and
  `window_start`, `window_end`, `window_duration` and `n_frames`.

* **A SUVR which is not a number says why.** A reference region integrating to
  zero over the window gives `NaN` or `Inf` without raising an error, so the
  measurement was counted as unsuccessful above an empty table of reasons.

* **The report follows the shape of the model fitting reports**, with histograms
  and one window plot per region-measurement. The sandbox draws the target and
  reference TACs with the integrated frames shaded underneath, so a window can
  be checked by eye before running the cohort.

## Reference TAC fixes

* **The configured spline degrees of freedom now actually reach the fit.**
  `ReferenceTAC$spline_df` was displayed and written to the sidecar, but never
  passed to `spline_tac()`. An unset or negative value means "choose
  automatically", which the report now says instead of claiming 5. Thanks to
  @mnoergaard, who reported and fixed all three of these (#38, #39).

* **A reference TAC that cannot be splined falls back to the raw TAC.** Basis
  construction can fail on a steady-state TAC or one with too few frames, and a
  `spline_df` below 2 cannot form a basis at all. Such a measurement uses its
  measured TAC unsmoothed — the "raw" method the app already offers — is listed
  in a "Spline fitting fallbacks" table, and has `raw` recorded in its own
  sidecar.

* **Spline-fitted reference TACs are plotted and saved on the PET frame
  timing.** `spline_tac()` may add a frame at time zero, so joining its fitted
  values back by equality could drop rows, and plotting them drew a curve from
  zero for a delayed-start acquisition. They are now interpolated onto the
  original frame midpoints.

## Bug fixes

* **A saved TAC subset window is restored correctly in the reference tissue
  app.** The shared restore path called `updateRadioButtons()` on `subset_type`,
  which is a `selectInput`, so it silently did nothing.

* **A window is no longer recorded under a selection method of "None"**, in
  either modelling app. The shared config path wrote a `subset` whenever a start
  or end point had been typed, even with the method left at "None" — a setting
  the reports then ignore. The plasma app's shared path was still overwriting
  the correct value its own model branches had worked out.

# petfit 0.2.1

## Nested models

* **New: `nested2TCM`, a plasma-input two-tissue model whose regions are fitted
  jointly within each measurement.** The conventional 2TCM fits each region on
  its own, so every region carries its own estimate of quantities that are
  properties of the measurement rather than of the region — chiefly the
  non-displaceable distribution volume. Estimating them once per measurement,
  from all regions at once, is both more faithful to what they mean and better
  determined. `nested2TCM` fits all regions of a measurement together via
  `kinfitr::nested_2tcm()`, sharing either V<sub>ND</sub>, `k4`, or both across
  regions while `K1` and BP<sub>P</sub> stay regional.

  It is configured in the **macro parameterisation** — `K1`, `Vnd`, `BPp`, `k4`
  — rather than the micro rate constants, because that is the parameterisation
  in which the shared quantities are the ones you would want to share. vB is a
  fixed scalar (`vB_value`) and cannot be fitted: a blood volume estimated per
  region against a shared V<sub>ND</sub> is not identifiable in practice.
  `roiweights` chooses how much each region pulls on the shared estimate —
  `"volume"` (larger regions have less noisy mean TACs, so they count for more)
  or `"equal"`.

* **New: `nestedSRTM`, the reference-tissue counterpart.** Fitted via
  `kinfitr::nested_srtm()` in the SRTM2 parameterisation, with R1 and
  BP<sub>ND</sub> per region and a single k2' per measurement. The usual route to
  a shared k2' is to fit SRTM everywhere and then take a median or mean of the
  per-region estimates, which is a summary of noisy numbers rather than an
  estimate in its own right; here it is estimated directly from all the regions
  at once. Its `kinpar` output carries a `k2prime` column, so the existing
  `inherit_modelN_*` sources on SRTM2, refLogan and MRTM2 read it exactly as
  they read SRTM's.

* **New: nested delay estimation.** `FitDelay.model` accepts `nested_1tcm` and
  `nested_2tcm`, which fit all the chosen regions of a measurement jointly for a
  single shared delay, in place of taking the median of independent per-region
  delay estimates. The delay is a property of the measurement, so estimating one
  is the question actually being asked. Output files are named
  `model-nested1TCM` and `model-nested2TCM`.

  These run with `multstart_iter = 1` regardless of configuration: the nested
  objective refits every region at each evaluation of the delay, so multistart
  multiplies an already large cost, and the outer optimisation over the delay
  already searches the range. vB is likewise fixed — the "Fit vB parameter"
  checkbox is hidden for the nested methods, and saved as `FALSE`, so a
  configuration written after switching to them does not carry a stale `TRUE`.

* **Nested models require at least two regions per measurement**, since there is
  nothing to share across otherwise. The new `validate_min_regions_per_pet()`
  counts the regions of each measurement, warns about and drops those that fall
  short, and stops with an explanatory error if no measurement qualifies — most
  often because `Subsetting.Regions` was narrowed too far.

* **The nested reports differ from the per-region ones in what they can say.**
  A joint objective across regions makes the per-region AIC and BIC undefined —
  the effective number of parameters per region is ambiguous once parameters are
  shared — so the reports give the weighted residual sum of squares per region
  instead, alongside the measurement-level joint objective and the optimiser's
  convergence code. Standard errors on the shared parameters are approximate,
  derived from the curvature of the profiled objective at the optimum, and those
  on the derived parameters are conditional on the shared values.

* **The Interactive tab rejects nested models with an explanation.** The sandbox
  fits one TAC at a time, which is precisely what a nested model does not do, so
  `fit_single_measurement_plasma()` and `fit_single_measurement_ref()` stop with
  a message rather than fitting something other than what was asked for.

## Delay estimation

* **The delay step's "Regions for Multiple Regions Analysis" field now filters
  the regions it names.** *This changes numerical results.* The field was
  recorded in the configuration and printed in the report's configuration table,
  but never applied: every median-delay analysis ran on all regions whatever was
  typed there. It now subsets through the same code as the `Subsetting`
  configuration, and so inherits its validation, its `;` separator with the
  comma check, and the `-` exclusion prefix. A configuration that named regions
  there will give different delays — the ones it was asking for — on re-running.

## Bug fixes

* **`determine_pipeline_type()` recognises every model type.** Its fallback,
  used when a configuration declares neither a pipeline type nor a `Blood` or
  `ReferenceTAC` section, matched only against `1TCM`, `2TCM`, `Logan`, `MA1`,
  `SRTM`, `refLogan`, `MRTM1` and `MRTM2`. A configuration whose only models
  were `2TCM_irr`, `Patlak` or `SRTM2` matched nothing and was routed by
  whatever the remaining fallback decided. All model types are now listed,
  nested ones included.

* petfit now requires **kinfitr >= 0.9.4**, which supplies `nested_2tcm()`,
  `nested_srtm()`, `nested_1tcm_delay()` and `nested_2tcm_delay()`.

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
