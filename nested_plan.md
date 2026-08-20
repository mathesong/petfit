# Nested models in petfit (nested 2TCM, nested delay, nested SRTM) + kinfitr review fixes

## Context

kinfitr (local repo, v0.9.3 installed = source) now has `nested_2tcm()`, `nested_1tcm_delay()`, `nested_2tcm_delay()`, `nested_srtm()` (+ plot/predict methods, tests, docs) which fit all TACs of one examination jointly with shared parameter(s): Vnd/k4/both for 2TCM, inpshift for delay, k2prime for SRTM. The goal is to expose these in petfit: users pick "shared" parameters and set start/lower/upper limits as usual in the Shiny apps, and new report templates run the fits (with a ≥2-regions-per-examination guard). Also: review the kinfitr implementations and fix defects found. Test end-to-end on `/home/granville/Repositories/OpenNeuro/ds004869` (27 subs × 2 ses, 12 regions/PET, blood in `derivatives/bloodstream/Primary_Analysis`; all per-session TAC/weights/inputfunction files readable; only the *top-level* `derivatives/petfit/desc-combinedregions_tacs.tsv` is an unfetched annex link — fetch with `datalad get` or regenerate via regiondef with `datalad unlock`).

User is away overnight; decisions below were made autonomously and flagged where they're judgement calls.

---

## Part A — kinfitr fixes (verified first-hand in source)

Branch off current HEAD (`update_parser`, clean tree), e.g. `nested_fixes`. Files: `R/kinfitr_nested_2tcm.R`, `R/kinfitr_nested_delay.R`, `R/kinfitr_nested_srtm.R`, `R/kinfitr_nested_utils.R`, tests in `tests/testthat/test-nested.R`.

1. **`multstart_iter` vector crash**: all 4 callers use `if (multstart_iter > 1)` while `.nested_fit_region` supports vectors via `prod()`. Change callers to `prod(multstart_iter) > 1` (nested_2tcm.R:151, delay.R:117/327, srtm.R:102).
2. **Final-pass NULL fit → `coef(NULL)` crash** (nested_2tcm.R:252, delay.R:179/389, srtm.R:176): if final fit is NULL for a region, emit a warning naming the region and produce an NA parameter/SE/tacs row for it instead of crashing (a failed region contributes `1e10` to the objective, so this case genuinely reaches the final pass).
3. **≥2 regions check**: `stop()` in all four functions if `length(unique(region)) < 2` — nesting is meaningless otherwise.
4. **Per-region weights silently discarded**: `weights_per_region <- weights[region == regions[1]]` is applied to every region. Use each region's own weights (`weights[region == r]`) in objective + final pass; keep `out$weights` as the full per-observation vector (document).
5. **SEs for shared parameters**: call `optim(..., hessian = TRUE)`; compute SEs for outer params from the profiled objective: `se = sqrt(2 * sigma2 * diag(solve(H)))` with `sigma2 = RSS_w / (n_total - p_total)`. Add as `Vnd.se`/`k4.se`/`k2prime.se`/`inpshift.se` columns in `par.se` (value repeated per region) — this is the number users most want from a nested fit. Guard `solve()` with tryCatch → NA.
6. **Inconsistent/over-conservative delta-method SEs in `nested_2tcm`**: the `shared=="Vnd"` branch NAs `Vt.se/BPnd.se/k2.se` that the `shared=="k4"` branch computes. Compute all derivable SEs in every branch by embedding the shared value as a constant in the `get_se()` expression (the `format(x, digits = 10)` trick already used in nested_srtm.R:188). Make `par.se` columns identical across `shared` modes (NA only where truly underivable).
7. **Named `roiweights` with missing regions → silent NAs** (`.nested_roiweights` line 69): `stop()` if any region name is absent from a named roiweights vector.
8. **Plot polish**: legend title `"Region"` on the Type aesthetic → fix in `plot_nested_2tcmfit` (:431) and `plot_nested_srtmfit` (:299) (check what the unnested plots use and match). Delay plots: x-axis spans the full AIF even when only 0–5 min was fitted — clamp x to the fitted data range ×1.1 via `coord_cartesian`.
9. Extend `test-nested.R` to cover: vector multstart_iter, <2 regions error, per-region weights, shared-param SEs present, named-roiweights validation.
10. `devtools::document()`, `devtools::test()`, install locally (`R CMD INSTALL` / `devtools::install()`) so petfit templates pick up the fixes. Commit on the branch; do not push.

Non-fix (disproved during review): the formula-string paste uses `as.character()` (~15 sig digits) — no meaningful precision loss.
Deliberately left as-is: `plot()` returning a list of pages for >3 regions (documented behaviour; petfit templates will walk the list).

---

## Part B — petfit: Nested 2TCM (plasma app)

**Naming decisions**: config `type = "nested2TCM"`; dropdown label `"Nested 2TCM (Non-linear, Reversible, shared parameters within PET measurement)"`; template `inst/rmd/nested2tcm_report.Rmd`; output files `model-nested2TCM_desc-model{N}_kinpar.tsv` (BIDS-safe, no underscore in value).

**Config schema** (Model1/2/3 section; nested object form like existing models):
```json
{ "type": "nested2TCM",
  "shared": "Vnd" | "k4" | "Vnd_k4",
  "K1":  {"start":0.1,"lower":0.0001,"upper":1},
  "Vnd": {"start":1,  "lower":0.0001,"upper":10},
  "BPp": {"start":1,  "lower":0.0001,"upper":50},
  "k4":  {"start":0.1,"lower":0.0001,"upper":0.5},
  "vB_value": 0.05,
  "roiweights": "volume" | "equal",
  "subset": {...}, "multstart_iter": 1 }
```
Scope decisions: vB is a fixed scalar in `nested_2tcm()` (cannot be fitted) → "set" only for v1, no inheritance dropdown. `roiweights` defaults to `"volume"` (kinfitr docs recommend ROI size; `volume_mm3` is in the combined TACs).

**App changes** (`R/modelling_plasma_app.R`), following the exact existing suffix pattern (`""`/`"2"`/`"3"`):
- Add the entry to the three model dropdowns (:602, :732, :872).
- New `conditionalPanel(condition = "input.button == 'nested2TCM'")` per model tab: `shared` selectInput (choices "Shared Vnd"="Vnd", "Shared k4"="k4", "Shared Vnd and k4"="Vnd_k4", default "Vnd"); start/lower/upper rows for K1, Vnd, BPp, k4 (macro parameterisation — all four always shown since non-shared ones are fitted per region); `vB_value` numericInput; `roiweights` select (Volume-weighted / Equal). Existing common tail already covers TAC subset + `multstart_iter`.
- `capture_model_params()` (:1689–1922): new `nested2TCM` branch writing the schema above with `%||%` defaults.
- `restore_model_params()` (:1152–1370): matching branch with `updateSelectInput`/`updateNumericInput` and `%||%` (backward-compat per CLAUDE.md).
- Interactive Sandbox: `R/interactive_fitting.R` `fit_single_measurement_plasma()` switch — clear `stop("Nested models fit all regions of a measurement jointly and are not supported in the single-TAC sandbox")`.

**Template** `inst/rmd/nested2tcm_report.Rmd`, cloned from `2tcm_report.Rmd` (948 lines) with these deltas:
- Same params/setup/config-table/cleanup/blood/delay/vB-free loading blocks; `has_config` gate on `type == "nested2TCM"`; keep the `desc` naming contract (`model1` etc.) so cleanup/inheritance/plot dirs line up.
- **Nest by measurement, not measurement×region**: drop `region` from the `group_by(across(intersect(...)))` key (keep `filename` for `output_stem`); keep `volume_mm3` inside the nested `tacs` (for roiweights).
- **≥2-regions guard** (new; nothing like it exists in petfit): after nesting, compute regions-per-measurement; render a warning table (via `divert_report_warnings` chunk, `report_warnings=TRUE`) listing measurements with <2 regions and drop them; `stop()` with a clear message if *no* measurement has ≥2 regions (points at `Subsetting.Regions`).
- Fit: `safe_nested_2tcm <- possibly(nested_2tcm, otherwise = NA)`, `future_pmap` over `(tacs, input, inpshift)` passing `t_tac = tacs$frame_mid, tac = tacs$TAC, region = tacs$region, weights = tacs$weights, roiweights = if(volume) tacs$volume_mm3, shared, vB = vB_value, inpshift`, the four limit triplets, `multstart_iter`, `frameStartEnd/timeStartEnd`.
- `fit$fit` is an **optim result, not nls** → compute GoF per region by hand from `fit$tacs` (RSS = Σ w·resid², reduced χ²); skip AIC/BIC (parameter count per region is ill-defined with shared params) but report the examination-level objective value. Hand-roll residual plots from `fit$tacs` (no `plot_residuals`).
- `par`/`par.se` are already one row per region → `unnest`; region comes from inside `par`, so re-check the downstream `select`/`join`/`group_by` idioms. Note `select(where(~ mean(is.na(.x)) < 1))`-style pruning must not drop the shared-SE columns.
- New content vs 2TCM report: a **shared-parameters table** (one row per measurement: Vnd/k4 ± SE) and histogram(s) of the shared estimates across measurements; note in prose which parameters were shared.
- Fit plots: `plot(fit, ...)` may return a *list* of ≤3-facet pages — flatten before `ggsave`, or build one page per region for the per-measurement plot directories.
- Fitted-TAC outputs: `predict.nested_2tcm(fit, newdata = list(t_tac = fine_grid, region = ...))` per region on 500 points (mirrors 2tcm), files `..._model-nested2TCM_desc-model{N}fitted_tacs.tsv`.
- Kinpar outputs: same 4 artefact families as 2tcm (cohort TSV, per-PET TSVs, JSON sidecars incl. `shared` in `AdditionalModelDetails`, fitted tacs); columns K1,k2,k3,k4,vB,inpshift,VT,Vnd,BPp,BPnd + `-se` (rename `.se`→`-se`, `Vt`→`VT`) — nested `par` already carries all derived params.

**Plumbing**:
- `R/report_generation.R` `get_model_template()`: `"nested2TCM" = "nested2tcm_report.Rmd"`.
- `R/docker_functions.R:391` `invasive_models` fallback list += `"nested2TCM"`.

## Part C — petfit: Nested delay (plasma app, delay step)

- Dropdown (`modelling_plasma_app.R:474`): add `"Nested 1TCM Shared Delay from Multiple Regions (Recommended, Slow)" = "nested_1tcm"` and `"Nested 2TCM Shared Delay from Multiple Regions (Very Slow)" = "nested_2tcm"`. Include both in the `delay_multiple_regions` conditionalPanel condition. No new FitDelay config fields (existing `time_window`, `vB_value`, `use_weights`, `inpshift_lower/upper`, `multiple_regions` all apply; `fit_vB` doesn't — nested delay takes fixed vB; hide/ignore for nested choices).
- `inst/rmd/delay_report.Rmd`: add `do_nested_1tcm`/`do_nested_2tcm` logicals + `is_nested` alongside `is_multiple_regions` for the loading path (combinedregions + weights, same as median methods, honouring `multiple_regions` region filter); new eval-gated fit chunks calling `nested_1tcm_delay`/`nested_2tcm_delay` per measurement (`future_map2(tacs, input, ...)`, `timeStartEnd = c(0, time_window)`, `weights = if(use_weights)`, `vB = vB_value`, `inpshift.lower/upper`, hardcoded `K1.upper = 2, k2.upper = 2, multstart_iter = 5` matching the existing delay chunks). ≥2-regions guard as in Part B.
- Extraction: one `inpshift` per measurement directly from `fit$par$inpshift[1]` — no median step.
- Diagnostics: use `plot(fit)` (`plot_nested_*_delayfit`) directly instead of the refit-at-pooled-delay dance; keep the per-measurement inpshift histogram out (single shared value — nothing to histogram; optionally show inpshift ± SE table across measurements once Part A#5 lands).
- **Set `method_display` (switch at :98–106) and `ModelName` explicitly** (`"nested1TCM"`/`"nested2TCM"`) — the current regex scrape (`str_match(method_display, "^(\\w*) ")`) would yield `"Nested"`. Downstream contract is only `*_desc-delayfit_kinpar.tsv` with a `blood_timeshift` column, unchanged.
- Restore/capture in the app need no structural change (model string round-trips through existing FitDelay code).

## Part D — petfit: Nested SRTM (reference app)

- `type = "nestedSRTM"`, label `"Nested SRTM (Non-linear, shared k2prime within PET measurement)"`, template `inst/rmd/nestedsrtm_report.Rmd`, outputs `model-nestedSRTM_...`.
- Config: `{"type":"nestedSRTM", "R1":{...def 1/0/10}, "BPnd":{...def 1.5/0/15}, "k2prime":{...def 0.1/0.001/1}, "roiweights":"volume"|"equal", "subset", "multstart_iter"}`. No `shared` selector — k2prime sharing is inherent.
- `R/modelling_ref_app.R`: dropdown entries ×3 (:652, :811, :975); conditionalPanel with R1/BPnd/k2prime limit rows + roiweights select; `capture_model_params` (:1837–2075) and `restore_model_params` (:1297–1520) branches (map `BPnd` ↔ kinfitr `bp.*` in the template like srtm does); sandbox guard in `fit_single_measurement_ref()`.
- Template cloned from `srtm_report.Rmd` (637 lines): reads `*_desc-targetregions_tacs.tsv` + `*_desc-ref_tacs.tsv`; nest by measurement keeping region+`RefTAC`+`volume_mm3` inside `tacs`; ≥2-regions guard; call `nested_srtm(t_tac = tacs$frame_mid, roitac = tacs$TAC, reftac = tacs$RefTAC, region = tacs$region, weights, roiweights, ...)` (note argument order: region 4th). Hand-rolled GoF/residuals as in Part B. Shared-k2prime table ± SE + histogram across measurements. Kinpar table includes a `k2prime` column → **SRTM2/refLogan/MRTM2 `inherit_modelN_*` k2prime inheritance works on it automatically** (they glob `*_desc-modelN_kinpar.tsv` and read `k2prime`) — state this in the report prose.
- Plumbing: `get_model_template()` += `"nestedSRTM"`; `docker_functions.R:392` `reference_models` += `"nestedSRTM"`. Do **not** add nestedSRTM to the `k2prime_models` ancillary list in `report_generation.R:204` (it estimates k2prime, doesn't consume it).

## Part E — Tests

- **petfit unit tests**: extend `tests/testthat/test-report_generation.R` with the two new template mappings; small tests for the ≥2-region helper if factored into `R/` (prefer a tiny exported/internal helper `validate_min_regions_per_pet()` so it's unit-testable and shared by all three templates).
- **Integration fixtures** (`tests/testthat/fixtures/integration/`): `ds004869_nested2tcm_config.json` (Model1 = nested2TCM shared "Vnd_k4", FitDelay = "nested_1tcm", sub subset "01;02") and `ds004869_nestedsrtm_config.json` — **use the nested `{"K1":{"start":...}}` schema**, not the flat `K1_lower` form the old fixtures use (that form is silently ignored). New test files `test-integration-modelling-nested2tcm.R` / `-nestedsrtm.R` per the template in `tests/README.md`; run with `PETFIT_INTEGRATION_TESTS=true`.

## Part F — End-to-end validation on ds004869

1. Make top-level combined TACs available: `datalad get derivatives/petfit/desc-combinedregions_tacs.tsv` (fallback: `datalad unlock` + regenerate via `petfit_auto(app="regiondef")` — all 54 petprep tacs + 27 morph files verified readable).
2. Create `derivatives/petfit/Nested_Test/desc-petfitoptions_config.json` (plasma): Subsetting sub "01;02", Weights as in Primary_Analysis, FitDelay `nested_1tcm`, Model1 `nested2TCM` shared "Vnd", Model2 shared "Vnd_k4", Model3 none. Run `petfit_auto(app="modelling_plasma", bids_dir=..., blood_dir=".../derivatives/bloodstream/Primary_Analysis", analysis_foldername="Nested_Test")`.
3. Reference smoke test: `Nested_Ref_Test` config using a pseudo-reference (dataset has no cerebellum among the 12 regions — use e.g. `ReferenceTAC$region = "Occipital"`, Subsetting.Regions including it; statistically meaningless, mechanically complete). Run reference pipeline with Model1 `nestedSRTM`, Model2 `SRTM2` with `k2prime_source = "inherit_model1_median"` to prove the inheritance path.
4. Verify: reports render without errors; shared params constant within measurement in kinpar TSVs; delay TSVs have one `blood_timeshift` per measurement; nested2TCM VT values broadly comparable to Primary_Analysis 2TCM VT (sanity, not equality); warnings section clean.
5. `Rscript -e "devtools::test()"` in both repos; `devtools::document()` where roxygen changed. Time permitting, `devtools::check()` on petfit.

## Part G — Housekeeping

- Commit petfit work on a feature branch (e.g. `feat/nested-models`); kinfitr on `nested_fixes`. No pushes.
- Update petfit CLAUDE.md briefly (new model types, template names, ≥2-region requirement, nested config schema gotcha).
- Leave a written summary for the morning: kinfitr review findings (incl. what was fixed vs deliberately left), design decisions taken (vB set-only, roiweights default "volume", naming), test results, and anything unfinished.

## Judgement calls to flag to the user
- `roiweights` default **"volume"** (UI-changeable to "equal").
- Nested 2TCM vB: **fixed value only** in v1 (kinfitr can't fit it; inheritance from Model 1 deferred).
- Type strings `nested2TCM`/`nestedSRTM`; delay model keys `nested_1tcm`/`nested_2tcm`.
- kinfitr NULL-final-fit behaviour: warn + NA row rather than hard error.
- AIC/BIC omitted from nested reports (ill-defined per-region parameter count); RSS/reduced-χ² + examination objective reported instead.
