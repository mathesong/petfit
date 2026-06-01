# Supported models

All model fitting is performed by the [kinfitr](https://github.com/mathesong/kinfitr) package. You can configure up to three models simultaneously for comparison.

Models are either **nonlinear** (compartmental models fitted by nonlinear least squares) or **linear** (graphical or multilinear methods fitted by linear regression).

## Plasma input models

Invasive models requiring an arterial blood input function. Available in the **Modelling App with Plasma Input**.

| Model | Description | Type |
|-------|-------------|------|
| 1TCM | One tissue compartment model | Nonlinear |
| 2TCM | Two tissue compartment model | Nonlinear |
| 2TCM_irr | Two tissue compartment model, irreversible (k4 = 0) | Nonlinear |
| Logan | Logan graphical analysis (VT) | Linear |
| MA1 | Multilinear analysis 1 (VT) | Linear |
| Patlak | Patlak graphical analysis (Ki, irreversible tracers) | Linear |

## Reference tissue models

Non-invasive models using a reference brain region instead of blood data. Available in the **Modelling App with Reference Tissue**.

| Model | Description | Type |
|-------|-------------|------|
| SRTM | Simplified reference tissue model | Nonlinear |
| SRTM2 | Simplified reference tissue model 2 (fixed k2prime) | Nonlinear |
| refLogan | Reference Logan analysis (BPND) | Linear |
| MRTM1 | Multilinear reference tissue model | Linear |
| MRTM2 | Multilinear reference tissue model 2 (fixed k2prime) | Linear |
| refPatlak | Reference Patlak analysis (irreversible tracers) | Linear |

The constrained models (SRTM2, MRTM2, refLogan) take a fixed `k2prime` value, which can come from a fixed value, another model in the same analysis (e.g. MRTM1), or an ancillary analysis.
