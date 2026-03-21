# Supported models

PETFit supports a comprehensive set of kinetic models for PET data analysis. All model fitting is performed by the [kinfitr](https://github.com/mathesong/kinfitr) package.

You can configure up to three models simultaneously for comparison.

## Invasive models

These models require an arterial blood input function. They are available in the **Modelling App with Plasma Input**.

### 1TCM — One tissue compartment model

A simple model with one tissue compartment and two rate constants.

**Parameters:**

| Parameter | Description | Default bounds |
|-----------|-------------|---------------|
| K1 | Influx rate constant | 0.001 – 1 |
| k2 | Efflux rate constant | 0.001 – 1 |
| vB | Blood volume fraction | 0 – 0.1 |

### 2TCM — Two tissue compartment model

The standard model with two tissue compartments and four rate constants.

**Parameters:**

| Parameter | Description | Default bounds |
|-----------|-------------|---------------|
| K1 | Influx rate constant | 0.001 – 1 |
| k2 | Transfer rate (tissue 1 to plasma) | 0.001 – 1 |
| k3 | Transfer rate (tissue 1 to tissue 2) | 0.001 – 1 |
| k4 | Transfer rate (tissue 2 to tissue 1) | 0.001 – 1 |
| vB | Blood volume fraction | 0 – 0.1 |

### 2TCM_irr — Two tissue compartment model (irreversible)

A constrained 2TCM where k4 = 0, appropriate for irreversibly binding tracers.

**Parameters:** Same as 2TCM but with k4 fixed at zero.

### Logan — Logan graphical analysis

A linearised graphical method for estimating the total distribution volume (VT).

**Parameters:**

| Parameter | Description |
|-----------|-------------|
| t* | Start time for the linear phase |
| vB | Blood volume fraction (optional) |

### MA1 — Multilinear analysis

An alternative linearised method for estimating VT, sometimes more robust than Logan.

**Parameters:**

| Parameter | Description |
|-----------|-------------|
| t* | Start time for the linear phase |
| vB | Blood volume fraction (optional) |

### Patlak — Patlak graphical analysis

A graphical method for estimating the net influx rate constant (Ki) for irreversible tracers.

**Parameters:**

| Parameter | Description |
|-----------|-------------|
| t* | Start time for the linear phase |

## Non-invasive models

These models use a reference brain region instead of blood data. They are available in the **Modelling App with Reference Tissue**.

### SRTM — Simplified reference tissue model

The standard reference tissue model with three parameters.

**Parameters:**

| Parameter | Description | Default bounds |
|-----------|-------------|---------------|
| R1 | Relative delivery (target/reference) | 0 – 10 |
| k2 | Target efflux rate constant | 0 – 1 |
| k2a | Apparent efflux rate constant | 0 – 1 |

### SRTM2 — Simplified reference tissue model 2

A constrained version of SRTM that uses a fixed k2prime value, reducing the model to two free parameters.

**Parameters:**

| Parameter | Description |
|-----------|-------------|
| R1 | Relative delivery |
| k2prime | Fixed reference region efflux rate (provided as a prior) |

The k2prime value can come from a previous MRTM1 or SRTM fit, a fixed value, or an ancillary analysis.

### refLogan — Reference Logan analysis

A linearised graphical method for estimating the binding potential (BPND) using a reference region.

**Parameters:**

| Parameter | Description |
|-----------|-------------|
| t* | Start time for the linear phase |
| k2prime | Reference region efflux rate (optional prior) |

### MRTM1 — Multilinear reference tissue model

A multilinear reference tissue method with three parameters.

**Parameters:**

| Parameter | Description | Default bounds |
|-----------|-------------|---------------|
| R1 | Relative delivery | 0 – 10 |
| k2 | Target efflux rate constant | 0 – 1 |
| k2a | Apparent efflux rate constant | 0 – 1 |

### MRTM2 — Multilinear reference tissue model 2

A constrained version of MRTM1 using a fixed k2prime value.

**Parameters:**

| Parameter | Description |
|-----------|-------------|
| R1 | Relative delivery |
| k2prime | Fixed reference region efflux rate (provided as a prior) |

### refPatlak — Reference Patlak analysis

A graphical method for estimating the net influx rate using a reference region, appropriate for irreversible tracers.

**Parameters:**

| Parameter | Description |
|-----------|-------------|
| t* | Start time for the linear phase |

## Model configuration

For each model, you can configure:

- **Start values** — Initial parameter estimates for the optimiser.
- **Lower and upper bounds** — Constraints on parameter values during fitting.
- **Fit vB** — Whether to include blood volume fraction as a free parameter (invasive models).
- **Use weights** — Whether to apply frame-by-frame weights during fitting.

## Three-model comparison

PETFit lets you configure up to three models in a single analysis. Each model runs independently on the same data, producing separate output files (`model1_report.html`, `model2_report.html`, `model3_report.html`) for comparison.

This is useful for:
- Comparing different model complexities (e.g. 1TCM vs 2TCM)
- Evaluating graphical vs compartmental approaches (e.g. 2TCM vs Logan)
- Testing different reference tissue models (e.g. SRTM vs MRTM1)
