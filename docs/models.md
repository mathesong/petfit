# Supported models

All model fitting is performed by the [kinfitr](https://github.com/mathesong/kinfitr) package. You can configure up to three models simultaneously for comparison.

Models are either **nonlinear** (compartmental models fitted by nonlinear least squares) or **linear** (graphical or multilinear methods fitted by linear regression).

Most models are fitted to one region at a time. The **nested** models are the exception: they fit all the regions of a PET measurement together, sharing the parameters that belong to the measurement rather than to the region. See [Nested models](#nested-models) below.

## Plasma input models

Invasive models requiring an arterial blood input function. Available in the **Modelling App with Plasma Input**.

| Model | Description | Type |
|-------|-------------|------|
| 1TCM | One tissue compartment model | Nonlinear |
| 2TCM | Two tissue compartment model | Nonlinear |
| nested2TCM | Two tissue compartment model, all regions fitted jointly with V<sub>ND</sub> and/or k4 shared within each measurement | Nonlinear |
| 2TCM_irr | Two tissue compartment model, irreversible (k4 = 0) | Nonlinear |
| Logan | Logan graphical analysis (VT) | Linear |
| MA1 | Multilinear analysis 1 (VT) | Linear |
| Patlak | Patlak graphical analysis (Ki, irreversible tracers) | Linear |

## Reference tissue models

Non-invasive models using a reference brain region instead of blood data. Available in the **Modelling App with Reference Tissue**.

| Model | Description | Type |
|-------|-------------|------|
| SRTM | Simplified reference tissue model | Nonlinear |
| nestedSRTM | Simplified reference tissue model, all regions fitted jointly with a single k2prime shared within each measurement | Nonlinear |
| SRTM2 | Simplified reference tissue model 2 (fixed k2prime) | Nonlinear |
| refLogan | Reference Logan analysis (BPND) | Linear |
| MRTM1 | Multilinear reference tissue model | Linear |
| MRTM2 | Multilinear reference tissue model 2 (fixed k2prime) | Linear |
| refPatlak | Reference Patlak analysis (irreversible tracers) | Linear |

The constrained models (SRTM2, MRTM2, refLogan) take a fixed `k2prime` value, which can come from a fixed value, another model in the same analysis (e.g. MRTM1 or nestedSRTM), or an ancillary analysis.

## Nested models

Some of the quantities a kinetic model estimates are properties of the *measurement* rather than of the region: the non-displaceable distribution volume, the reference-region efflux rate k2prime, the delay between the blood input function and the tissue. Fitting each region independently produces one estimate of each per region, which then has to be reconciled — usually by taking a median or mean afterwards, which summarises noisy numbers rather than estimating anything.

Nested models estimate them once per measurement instead, from all of its regions at once. All the fitting is done by [kinfitr](https://github.com/mathesong/kinfitr)'s nested model functions.

| Model | Shared within each measurement | Fitted per region |
|-------|-------------------------------|-------------------|
| nested2TCM | V<sub>ND</sub>, k4, or both | K1, BP<sub>P</sub> |
| nestedSRTM | k2prime | R1, BP<sub>ND</sub> |

**nested2TCM** is configured in the macro parameterisation — `K1`, `Vnd`, `BPp`, `k4` — rather than the micro rate constants, because that is the parameterisation in which the shared quantities are the ones you would want to share. Unlike the ordinary 2TCM, `vB` is a fixed value and cannot be fitted.

**nestedSRTM** is fitted in the SRTM2 parameterisation. Its output carries a `k2prime` column, so SRTM2, refLogan and MRTM2 can inherit k2prime from it exactly as they inherit it from SRTM or MRTM1 — with the difference that the value they inherit was estimated jointly rather than summarised across independent fits.

Both take a **region weighting** setting, which controls how much each region pulls on the shared estimate:

- **Volume-weighted** (default) — larger regions have less noisy mean TACs, so they count for more.
- **Equal** — every region contributes equally.

```{important}
Nested models need **at least two regions per measurement**; there is nothing to share across otherwise. Measurements with fewer are dropped with a warning, and if no measurement qualifies the report stops with an error. Check the `Regions` field of your subsetting configuration if this happens.
```

Two consequences worth knowing about when reading a nested model's report:

- **No AIC or BIC per region.** A joint objective across regions makes the effective number of parameters per region ambiguous. The reports give the weighted residual sum of squares per region instead, along with the joint objective value and the optimiser's convergence code for each measurement.
- **Approximate standard errors on the shared parameters**, derived from the curvature of the profiled objective at the optimum. Standard errors on derived parameters are conditional on the shared values.

Nested models are also not available in the **Interactive** tab of either modelling app, which fits one TAC at a time — which is exactly what a nested model does not do.
