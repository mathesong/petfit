# Usage guide

PETFit provides three independent Shiny web applications that together form a complete PET kinetic modelling pipeline.

## The two-step workflow

Every PETFit analysis follows two stages:

1. **Region definition** — Combine brain regions from PET preprocessing derivatives into analysis-ready TACs. This step runs once per dataset and the results are shared across all analyses.
2. **Kinetic modelling** — Configure and run kinetic models on the combined TACs. Choose either the plasma input app (for invasive models requiring blood data) or the reference tissue app (for non-invasive models using a reference region).

## The three apps

**Region Definition App**
: Creates combined regional TACs by reading segmentation and morphometry data from your PET preprocessing derivatives. Produces a single `desc-combinedregions_tacs.tsv` file containing all combined TACs with BIDS metadata. See [Region definition](region-definition.md).

**Modelling App with Plasma Input**
: Configures and runs invasive kinetic models that require an arterial blood input function. The pipeline steps are: data definition, weights, delay fitting, and model fitting. See [Modelling with plasma input](modelling-plasma.md).

**Modelling App with Reference Tissue**
: Configures and runs non-invasive kinetic models that use a reference brain region instead of blood data. The pipeline steps are: data definition, weights, reference TAC setup, and model fitting. See [Modelling with reference tissue](modelling-reference.md).

## Interactive vs automatic mode

Both modes produce identical results. The difference is how you interact with the pipeline. Docker is the recommended way to run both modes.

**Interactive mode** launches a Shiny web app in your browser. You configure each step visually, run steps individually, and review results as you go. The app automatically saves a JSON configuration file that records all your choices.

**Automatic mode** reads an existing JSON configuration file and runs the full pipeline (or a specific step) without any user interaction. This is designed for batch processing, HPC clusters, and reproducible workflows.

A common workflow is to use interactive mode once to set up and validate your configuration, then switch to automatic mode for production runs.

## Configuration files

The interactive apps automatically generate JSON configuration files (`desc-petfitoptions_config.json`) in each analysis folder. These files record every setting — subsetting, weights, delay/reference TAC options, model parameters, and bounds — so the analysis is fully reproducible.

You do not need to write configuration files by hand. Use the interactive app to create and validate your configuration, then use the same analysis folder in automatic mode. The configuration file will be read automatically.

When you reopen the interactive app and point it to an existing analysis folder, all settings are restored from the configuration file.

## Analysis folders

The modelling apps write outputs into analysis-specific subfolders within `derivatives/petfit/`. The default folder is called `Primary_Analysis`, but you can create as many as you like with descriptive names (e.g. `Baseline_only`, `High_binding_regions`, `Short_duration`).

This design means region definition results are shared across all analyses, while each analysis folder can use different data subsets, time windows, or modelling approaches. See [PETFit folder structures](folder-structure.md) for the full explanation.

```{toctree}
:maxdepth: 2

folder-structure
region-definition
modelling-plasma
modelling-reference
reports
```
