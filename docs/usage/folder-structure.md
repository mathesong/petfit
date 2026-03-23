# PETFit folder structures

PETFit organises its outputs in a structured hierarchy within the BIDS derivatives directory. Understanding this structure is key to running multiple analyses efficiently.

## Overview

A PETFit workflow has two levels:

1. **Region definition** — runs once per dataset and produces shared files at the `derivatives/petfit/` level.
2. **Modelling analyses** — each analysis creates its own subfolder under `derivatives/petfit/`, using the shared region definition outputs.

```
derivatives/
└── petfit/                                    # Shared petfit directory
    ├── petfit_regions.tsv                     # Region definitions (shared)
    ├── desc-combinedregions_tacs.tsv          # Combined TACs (shared)
    │
    ├── Primary_Analysis/                      # An analysis folder
    │   ├── desc-petfitoptions_config.json     # Analysis configuration
    │   ├── sub-01_ses-01_desc-combinedregions_tacs.tsv
    │   ├── sub-01_ses-01_desc-weights_weights.tsv
    │   ├── sub-01_ses-01_desc-delayfit_kinpar.tsv
    │   ├── sub-01_ses-01_desc-model1_kinpar.tsv
    │   └── reports/
    │       ├── data_definition_report.html
    │       ├── weights_report.html
    │       ├── delay_report.html
    │       └── model1_report.html
    │
    ├── Baseline_Only/                         # Another analysis folder
    │   ├── desc-petfitoptions_config.json
    │   ├── ...
    │   └── reports/
    │
    └── Ancillary_Delay/                       # Ancillary analysis folder
        ├── desc-petfitoptions_config.json
        ├── ...
        └── reports/
```

## Region definition: shared across all analyses

Region definition combines individual brain regions from your PET preprocessing derivatives into analysis-ready TACs. The outputs are written to the `derivatives/petfit/` directory and are shared by every analysis folder:

- **`petfit_regions.tsv`** — defines which brain regions to combine and how. This file can be reused across studies that share the same preprocessing pipeline and segmentation.
- **`desc-combinedregions_tacs.tsv`** — the combined TACs for all PET measurements, regions, and time frames, with integrated BIDS metadata (subject, session, tracer, injected radioactivity, body weight, etc.).

You only need to run region definition once. All subsequent analyses read from the same combined TACs file.

## Analysis folders

Each modelling analysis creates its own subfolder under `derivatives/petfit/`. The default folder is called `Primary_Analysis`, but you can create as many as you need with descriptive names.

### Why multiple analyses?

Different analyses let you explore your data in different ways without overwriting previous results:

- **Baseline only** — include only baseline measurements by filtering on session.
- **Shortened scans** — use only the first 60 minutes of data by restricting frame timing.
- **Plasma vs reference** — run invasive models on one subset and non-invasive models on another.
- **Different region subsets** — analyse high-binding regions separately from low-binding regions.
- **Different model configurations** — compare model parameter bounds, weighting approaches, or delay estimation methods.

Each analysis folder contains its own configuration file (`desc-petfitoptions_config.json`), individual TAC files, weight files, kinetic parameter files, and HTML reports. The configuration file records every choice so the analysis is fully reproducible.

### Creating an analysis folder

Analysis folders are created automatically when you launch a modelling app. Specify the folder name with the `analysis_foldername` parameter:

`````{tab-set}

````{tab-item} Docker
```bash
docker run -it --rm \
  -v /path/to/derivatives:/data/derivatives_dir:rw \
  -v /path/to/blood:/data/blood_dir:ro \
  -p 3838:3838 \
  mathesong/petfit:latest \
  --func modelling_plasma \
  --analysis_foldername Baseline_Only
```
````

````{tab-item} Apptainer
```bash
apptainer run \
  --bind /path/to/derivatives:/data/derivatives_dir \
  --bind /path/to/blood:/data/blood_dir \
  petfit_latest.sif \
  --func modelling_plasma \
  --analysis_foldername Baseline_Only
```
````

````{tab-item} R
```r
# Interactive
petfit_interactive(
  app = "modelling_plasma",
  derivatives_dir = "/path/to/derivatives",
  analysis_foldername = "Baseline_Only"
)

# Automatic
petfit_modelling_auto(
  derivatives_dir = "/path/to/derivatives",
  analysis_foldername = "Baseline_Only"
)
```
````

`````

## Up to three models per analysis

Within each analysis, you can configure up to three kinetic models to fit simultaneously. Each model runs independently on the same data, producing separate output files for comparison:

- `model1_report.html`, `model2_report.html`, `model3_report.html`
- `{pet_id}_desc-model1_kinpar.tsv`, `{pet_id}_desc-model2_kinpar.tsv`, etc.

### Model inheritance

Models within the same analysis can inherit parameter estimates from earlier models. This is particularly useful for reference tissue models that require a k2prime value:

- **Model 2** can inherit k2prime from Model 1 (e.g. mean or median across regions).
- **Model 3** can inherit k2prime from Model 1 or Model 2.

A typical workflow is to fit MRTM1 as Model 1 to estimate k2prime, then use that value in MRTM2 as Model 2 for a more constrained fit.

## Ancillary analysis folders

Sometimes you want to estimate a parameter (such as the blood-tissue delay or k2prime) from a subset of well-behaved regions, then use that estimate in your main analysis across all regions. This is the purpose of ancillary analysis folders.

### How it works

1. **Create an ancillary analysis** that includes only the regions you trust for parameter estimation. For example, select a few high-binding regions with clean TACs and good signal-to-noise.
2. **Run the pipeline** in the ancillary folder to estimate the parameter of interest (delay or k2prime).
3. **Create your primary analysis** and point it to the ancillary folder. The primary analysis inherits the parameter estimates instead of re-estimating them.

Ancillary and primary analyses are **sibling folders** under `derivatives/petfit/` — they sit at the same level in the directory hierarchy.

### Delay inheritance (plasma input)

For plasma input pipelines, you can estimate the blood-tissue delay in an ancillary analysis and inherit it in the primary analysis.

In the primary analysis configuration, set the delay model to `"ancillary_estimate"` so that the pipeline copies the delay values from the ancillary folder instead of fitting them.

`````{tab-set}

````{tab-item} Docker
```bash
# Step 1: Run ancillary analysis with well-behaved regions
docker run --rm \
  -v /path/to/derivatives:/data/derivatives_dir:rw \
  -v /path/to/blood:/data/blood_dir:ro \
  mathesong/petfit:latest \
  --func modelling_plasma --mode automatic \
  --analysis_foldername Ancillary_Delay

# Step 2: Run primary analysis, inheriting delay estimates
docker run --rm \
  -v /path/to/derivatives:/data/derivatives_dir:rw \
  -v /path/to/blood:/data/blood_dir:ro \
  mathesong/petfit:latest \
  --func modelling_plasma --mode automatic \
  --analysis_foldername Primary_Analysis \
  --ancillary_analysis_folder Ancillary_Delay
```
````

````{tab-item} Apptainer
```bash
# Step 1: Run ancillary analysis with well-behaved regions
apptainer run \
  --bind /path/to/derivatives:/data/derivatives_dir \
  --bind /path/to/blood:/data/blood_dir \
  petfit_latest.sif \
  --func modelling_plasma --mode automatic \
  --analysis_foldername Ancillary_Delay

# Step 2: Run primary analysis, inheriting delay estimates
apptainer run \
  --bind /path/to/derivatives:/data/derivatives_dir \
  --bind /path/to/blood:/data/blood_dir \
  petfit_latest.sif \
  --func modelling_plasma --mode automatic \
  --analysis_foldername Primary_Analysis \
  --ancillary_analysis_folder Ancillary_Delay
```
````

````{tab-item} R
```r
# Step 1: Run ancillary analysis with well-behaved regions
petfit_modelling_auto(
  derivatives_dir = "/path/to/derivatives",
  analysis_foldername = "Ancillary_Delay"
)

# Step 2: Run primary analysis, inheriting delay estimates
petfit_modelling_auto(
  derivatives_dir = "/path/to/derivatives",
  analysis_foldername = "Primary_Analysis",
  ancillary_analysis_folder = "Ancillary_Delay"
)
```
````

`````

### k2prime inheritance (reference tissue)

For reference tissue pipelines, you can estimate k2prime in an ancillary analysis and use it in constrained models (MRTM2, SRTM2, refLogan) in the primary analysis.

In the primary analysis configuration, set the k2prime source to values like `"ancillary_model1_median"` or `"ancillary_model1_mean"` to use the aggregated k2prime from the ancillary analysis.

`````{tab-set}

````{tab-item} Docker
```bash
docker run --rm \
  -v /path/to/derivatives:/data/derivatives_dir:rw \
  mathesong/petfit:latest \
  --func modelling_ref --mode automatic \
  --analysis_foldername Primary_Analysis \
  --ancillary_analysis_folder Ancillary_k2prime
```
````

````{tab-item} Apptainer
```bash
apptainer run \
  --bind /path/to/derivatives:/data/derivatives_dir \
  petfit_latest.sif \
  --func modelling_ref --mode automatic \
  --analysis_foldername Primary_Analysis \
  --ancillary_analysis_folder Ancillary_k2prime
```
````

````{tab-item} R
```r
petfit_modelling_auto(
  derivatives_dir = "/path/to/derivatives",
  analysis_foldername = "Primary_Analysis",
  ancillary_analysis_folder = "Ancillary_k2prime"
)
```
````

`````

### When to use ancillary analyses

- **Delay estimation**: When some regions have noisy TACs that produce unreliable delay estimates, estimate the delay from cleaner regions and apply it everywhere.
- **k2prime estimation**: When using constrained models (MRTM2, SRTM2), estimate k2prime from a subset of regions where the unconstrained model (MRTM1, SRTM) fits well.
- **Quality control**: Running a quick ancillary analysis first lets you validate parameter estimates before committing to a full analysis.
