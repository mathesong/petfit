# Nested models: implementation summary

Status for the morning review. Two working trees carry uncommitted changes, as requested:
`/home/granville/Repositories/petfit` (this repo, current branch `main`) and
`/home/granville/Repositories/kinfitr` (current branch `update_parser`). Nothing is committed.
The plan is in `nested_plan.md`.

Work was split across two Claude sessions: this session implemented everything in petfit and
reviewed the kinfitr changes; a second session ("kinfitr-e3") implemented the kinfitr fixes and,
on your direct instruction to it, reinstalled kinfitr into your library. petfit is NOT installed
into your library: test runs used a scratch-library build under this session's temp directory.

## What you can now do

- **Plasma app**: select `Nested 2TCM` as Model 1/2/3. Choose shared parameter(s) (Vnd, k4, or
  both), set start/lower/upper for K1, Vnd, BPp, k4 (macro parameterisation), a fixed vB, and
  volume-weighted or equal region weighting. One joint fit per measurement.
- **Delay step**: choose `Nested 1TCM Shared Delay` or `Nested 2TCM Shared Delay` — one shared
  delay per measurement estimated jointly across regions, instead of the median of per-region fits.
- **Reference app**: select `Nested SRTM` — SRTM2 parameterisation with a single shared k2'
  estimated across regions, R1/BPnd per region. Its kinpar output carries a `k2prime` column, so
  SRTM2/refLogan/MRTM2 configured with `inherit_modelN_*` pick the fitted k2' up automatically
  (verified end-to-end in the integration test).
- All nested fits require ≥2 regions per measurement: measurements below that are excluded with a
  rendered warning; if none qualify the report stops with a message pointing at
  `Subsetting.Regions`.

## petfit changes (this session)

| Area | Files |
|---|---|
| Plasma app: dropdown entries ×3, `nested_`-prefixed parameter panels ×3, capture/restore branches, nested delay dropdown entries (static + ancillary rebuild), fit-vB checkbox hidden for nested delay | `R/modelling_plasma_app.R` |
| Reference app: same pattern for `nestedSRTM` (R1/BPnd/k2prime limits, roiweights, own multstart input) | `R/modelling_ref_app.R` |
| New model templates (measurement-level nesting, ≥2-region guard, hand-rolled GoF/residuals since `$fit` is an `optim` result, shared-parameter tables ± approximate SE, `model-nested2TCM`/`model-nestedSRTM` output naming) | `inst/rmd/nested2tcm_report.Rmd`, `inst/rmd/nestedsrtm_report.Rmd` |
| Delay template: `nested_1tcm`/`nested_2tcm` branches (one shared delay per measurement, no median step, plots via the nested fit itself), explicit ModelName (`nested1TCM`/`nested2TCM`) instead of the regex scrape | `inst/rmd/delay_report.Rmd` |
| New exported helper `validate_min_regions_per_pet()` | `R/validation.R` |
| Template map entries for `nested2TCM`/`nestedSRTM` | `R/report_generation.R` |
| Pipeline-type fallback lists (also added the previously missing `2TCM_irr`, `Patlak`, `SRTM2`) | `R/docker_functions.R` |
| Interactive Sandbox rejects nested types with a clear message | `R/interactive_fitting.R` |
| Unit tests (template map, region validation) + integration fixtures/tests | `tests/testthat/test-report_generation.R`, `test-validation.R`, `test-integration-modelling-nested2tcm.R`, `test-integration-modelling-nestedsrtm.R`, `fixtures/integration/ds004869_nested2tcm_config.json`, `ds004869_nestedsrtm_config.json` |
| Docs | `CLAUDE.md` (nested models section), `man/`, `NAMESPACE` |

### Config schema (what the app writes / templates read)

```json
"Model1": {
  "type": "nested2TCM",
  "shared": "Vnd" | "k4" | "Vnd_k4",
  "K1":  {"start":0.1,"lower":0.0001,"upper":1},
  "Vnd": {"start":1,"lower":0.0001,"upper":10},
  "BPp": {"start":1,"lower":0.0001,"upper":50},
  "k4":  {"start":0.1,"lower":0.0001,"upper":0.5},
  "vB_value": 0.05,
  "roiweights": "volume" | "equal",
  "subset": {...}, "multstart_iter": 1
}
```
```json
"Model1": {
  "type": "nestedSRTM",
  "R1":      {"start":1,"lower":0.0001,"upper":5},
  "BPnd":    {"start":0.5,"lower":0.0001,"upper":5},
  "k2prime": {"start":0.1,"lower":0.001,"upper":1},
  "roiweights": "volume" | "equal",
  "subset": {...}, "multstart_iter": 1
}
```
`FitDelay.model` additionally accepts `"nested_1tcm"` and `"nested_2tcm"` with the existing
FitDelay fields (`fit_vB` does not apply: nested delay takes a fixed vB).

### Incidental fix

`FitDelay.multiple_regions` was displayed in the delay report's configuration table but never
actually filtered the loaded regions. It now does, for both the median and nested methods, with
the same parse/validate/negation semantics as `Subsetting.Regions` (via `parse_semicolon_values()`
+ `subset_combined_tacs()`).

## Design decisions taken in your absence

- `roiweights` defaults to **"volume"** (kinfitr's docs recommend ROI size; `volume_mm3` is in the
  combined TACs). Switchable to "Equal" in the UI.
- Nested 2TCM **vB is set-only** (`kinfitr::nested_2tcm()` cannot fit it); no inheritance dropdown
  in v1.
- Type strings `nested2TCM` / `nestedSRTM` (BIDS-safe in `model-` filename values); delay keys
  `nested_1tcm` / `nested_2tcm`; templates `nested2tcm_report.Rmd` / `nestedsrtm_report.Rmd`.
- **AIC/BIC are omitted** from the nested reports (the per-region parameter count is ill-defined
  with shared parameters). Reported instead: per-region weighted RSS, and per-measurement joint
  objective value + optimiser convergence code.
- Report tables show shared parameters per measurement with their approximate SEs, plus the usual
  per-region tables/histograms; fit plots are faceted by region (≤3 per page), residual plots are
  hand-rolled from `$tacs`.

## kinfitr: review verdict and what changed

I reviewed the nested implementations first-hand (all four files) before implementation, and
reviewed the second session's full diff afterwards. The original implementations were structurally
sound (correct profiled outer/inner optimisation, sensible roiweights handling, tests and docs in
place) with seven real defects, all now fixed:

1. `multstart_iter` as a vector crashed (scalar `if` on a vector); now validated and supported.
2. A region failing at the optimised shared parameters crashed in `coef(NULL)`; now a clear error
   naming the region. (In petfit this surfaces as `success = FALSE` for that measurement.)
3. Per-region frame weights were silently replaced by region 1's; now applied per region, and
   `out$weights` holds the full stacked vector.
4. No SEs for the shared parameters; now approximate profile-curvature SEs (`inpshift.se`,
   `k2prime.se`, `Vnd.se`, `k4.se`), relative (fraction of estimate) like all kinfitr SEs. A
   single-region nested delay fit reproduces `onetcm()`'s delay SE to ~2%.
5. Derived SEs (`Vt.se`, `BPnd.se`, `k2.se`, `k3.se`) were NA'd in some `shared` modes despite
   being derivable; now computed in every mode, so `par.se` columns are identical across modes.
6. Named `roiweights` missing a region silently produced NAs; now an error naming the region.
7. `plot()` past 3 regions silently returned an unprinted list; now a classed set that prints all
   pages.

Also package-wide (your separate request to the other session): `lhstype = "improved"` on all 27
`nls_multstart()` call sites, `nls.multstart (>= 2.0.0)` in DESCRIPTION, documentation updated,
NEWS.md entries added. kinfitr test suite: 794 pass / 0 fail (16 nested test blocks, 83 assertions).

**Three judgement calls the other session made, flagged for your decision** (I reviewed and agree
with all three; each is a small change to revert):

- Single-region input **warns** rather than errors (it reduces exactly to the unnested model, so an
  error would break mathematically valid code). petfit enforces its own ≥2-region policy anyway.
- A failed final-pass region **errors** rather than returning NA rows (an NA row would sit next to
  a shared estimate that a 1e10 penalty may have contaminated).
- The faceted plots' legend title is now "Type" rather than "Region" (the unnested plots' "Region"
  legends genuinely contain region-prefixed labels; the nested faceted ones do not).

Two minor kinfitr notes from my review, not fixed (cosmetic/edge-case, listed for completeness):

- `.nested_outer_se()`'s finite-difference Hessian can be contaminated if an inner fit fails at a
  perturbed point (the 1e10 penalty is finite, so the guards don't catch it) — worst case is a
  wrong shared-parameter SE, not a wrong estimate.
- `.nested_align_bounds()` silently renames a *named* bounds vector positionally when its names
  don't cover the parameters but its length matches.

## Test results

- petfit unit tests: **0 fail, 381 pass** (includes new template-map and region-validation tests).
- petfit nested integration tests (`PETFIT_INTEGRATION_TESTS=true`, bundled ds004869 test data):
  **0 fail, 45 pass** — full nested-2TCM pipeline with nested-1TCM delay (checks shared parameters
  constant within measurement, delay files one-row `blood_timeshift`, `model-nested2TCM` naming,
  fitted-TAC files), and full nested-SRTM pipeline with **SRTM2 inheriting k2' from the nested
  fit**.
- kinfitr: full suite 794 pass / 0 fail (run by the kinfitr session).
- Real-data run on `/home/granville/Repositories/OpenNeuro/ds004869`, `Nested_Test` analysis
  folder (sub-01, sub-02; nested 1TCM delay; Model 1 = nested 2TCM shared Vnd; Model 2 = nested
  2TCM shared Vnd+k4; blood from `derivatives/bloodstream/Primary_Analysis`): **SUCCESS**, all
  steps and reports. Numbers:
  - Nested shared delays agree with the original 1TCM-median delays to within 0.01 min on all
    four measurements (e.g. sub-01 baseline: −0.133 vs −0.129).
  - Model 1: Vnd constant within each measurement (0.67–1.07 across measurements) with tight
    relative SEs (0.007–0.046); k4 varies freely per region as configured.
  - Model 2: Vnd and k4 both constant within measurement, both with finite SEs; the shared Vnd
    values agree closely with Model 1's (e.g. 0.937 vs 0.943).
  - VT sanity vs the original per-region 2TCM (Primary_Analysis): r = 0.96 across the 48
    (measurement × region) pairs, median absolute relative difference 1.6%.
  - One caveat from the first attempt: the initial run failed mid-delay-report because I
    reinstalled petfit into the scratch test library while its report subprocess was rendering
    from that library (self-inflicted race, not a code issue); the clean rerun succeeded.
- Reference smoke test (`Nested_Ref_Test`, pseudo-reference **Occipital** since the 12 regions
  include no cerebellum — mechanically complete, statistically meaningless): **SUCCESS**. All
  steps and reports completed; 44 kinpar rows (4 measurements × 11 target regions); k2' constant
  within each measurement (0.065–0.213 across measurements) with finite relative SEs (0.07–0.16);
  SRTM2 (Model 2, `inherit_model1_median`) picked up exactly the nested medians. Some BPnd values
  sit at 0, as expected with a pseudo-reference that some regions underbind.

Note: `derivatives/petfit/desc-combinedregions_tacs.tsv` was an unfetched annex link; I ran
`datalad get` on it (the only change to the dataset outside the two new analysis folders).

## Not done / known limitations

- Nested 2TCM vB inheritance from a previous model (deferred; needs a scalar-per-measurement path).
- The delay step's nested methods use the same hardcoded internals as the median methods
  (`K1.upper = 2`, `k2.upper = 2`, `multstart_iter = 5`) — consistent with existing behaviour, not
  configurable.
- No roiweights option for the nested *delay* methods (no UI surface there; equal weights used).
- The Interactive Sandbox intentionally rejects nested types (single-TAC by design).
