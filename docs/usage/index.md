# Usage guide

PETFit provides three independent Shiny web applications that together form a complete PET kinetic modelling pipeline.

## The two-step workflow

Every PETFit analysis follows two stages:

1. **Region definition** — Combine brain regions from PET preprocessing derivatives into analysis-ready TACs. This step is shared across all analyses of the same dataset.
2. **Kinetic modelling** — Configure and run kinetic models. Choose either the plasma input app (for invasive models requiring blood data) or the reference tissue app (for non-invasive models using a reference region).

## The three apps

**Region Definition App**
: Creates combined regional TACs by reading segmentation and morphometry data from your PET preprocessing derivatives. Produces a single `desc-combinedregions_tacs.tsv` file containing all combined TACs with BIDS metadata.

**Modelling App with Plasma Input**
: Configures and runs invasive kinetic models that require an arterial blood input function. The pipeline steps are: data definition, weights, delay fitting, and model fitting.

**Modelling App with Reference Tissue**
: Configures and runs non-invasive kinetic models that use a reference brain region instead of blood data. The pipeline steps are: data definition, weights, reference TAC setup, and model fitting.

## Interactive vs automatic mode

Both modes produce identical results. The difference is how you interact with the pipeline:

**Interactive mode** launches a Shiny web app in your browser. You configure each step visually, run steps individually, and review results as you go. The app saves a JSON configuration file that records all your choices.

**Automatic mode** reads an existing JSON configuration file and runs the full pipeline (or a specific step) without any user interaction. This is designed for batch processing, HPC clusters, and reproducible workflows.

A common workflow is to use interactive mode once to set up and validate your configuration, then switch to automatic mode for production runs.

## Analysis folders

The modelling apps write outputs into analysis-specific subfolders within `derivatives/petfit/`. The default folder is called `Primary_Analysis`, but you can create as many as you like with descriptive names (e.g. `Baseline_only`, `High_binding_regions`, `Short_duration`).

This design means region definition results are shared across all analyses, while each analysis folder can use different data subsets, time windows, or modelling approaches.

```{toctree}
:maxdepth: 2

folder-structure
region-definition
modelling-plasma
modelling-reference
reports
```
