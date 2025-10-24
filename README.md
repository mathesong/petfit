# PETFit: A BIDS App for PET Kinetic Modelling

PETFit is a BIDS App for fitting kinetic models to PET time activity curve data.
It performs a series of steps, accompanied by detailed HTML reports for quality
control.

It can be used in two ways:

- **Interactive Mode**: Use interactive graphical web applications to configure analyses, and either download the created configuration file, or individual steps one-by-one from the browser.
- **Automatic Mode**: Automated pipeline execution using pre-defined configuration files. This allows users to first define configuration files locally using interactive mode, and then execute the analysis automatically either locally or on a remote server.


**NOTE:** PETFit is currently in active development, and there may be bugs. Please report these to me on the Github issues. They are extremely valuable for making this pipeline robust for application to all datasets.


## Interactive Web Apps

The web apps allow users to graphically define configurations for the analysis.

- **Region Definition App**: Creates combined regional TACs from PET Preprocessing Derivative data
- **Modelling App with Plasma Input**: Configures invasive kinetic models (1TCM, 2TCM, 2TCM_irr, Logan, MA1, Patlak) requiring blood input
- **Modelling App with Reference Tissue**: Configures non-invasive kinetic models (SRTM, refLogan, MRTM1, MRTM2) using reference regions

The interactive apps allow you to:
- Configure analyses step-by-step with a graphical interface
- Execute each step individually and generate HTML reports
- Save configuration files for reproducible processing
- Run complete pipelines with the "Run All" button

## Installation

`PETFit` can be executed either from R, or through a Docker container:

- **[R Package Usage](#r-package-usage)**: Install and use directly from within R
- **[Docker Usage](#docker-usage)**: Use as a containerised BIDS app without installing R or dependencies locally

## Usage Summary

| Mode | R Usage | Docker Usage |
|------|---------|--------------|
| Interactive - Region Definition | `launch_apps(bids_dir = "/path/to/bids")` | `docker run -p 3838:3838 ... --func regiondef` |
| Interactive - Modelling with Plasma Input | `launch_apps(app = "modelling_plasma", bids_dir, blood_dir)` | `docker run -p 3838:3838 ... --func modelling_plasma` |
| Interactive - Modelling with Reference Tissue | `launch_apps(app = "modelling_ref", bids_dir)` | `docker run -p 3838:3838 ... --func modelling_ref` |
| Automatic - Region Definition | `petfit_regiondef_auto(derivatives_dir = "...")` | `docker run ... --func regiondef --mode automatic` |
| Automatic - Modelling | `petfit_modelling_auto(derivatives_dir = "...")` | `docker run ... --func modelling_plasma --mode automatic` |

## R Package Usage

### Installation

You can install the development version of petfit like so:

```r
# Install development version from GitHub
remotes::install_github("mathesong/petfit")
```

### Launch Apps

```r
library(petfit)

# Launch region definition app (default)
launch_apps(
  app = "regiondef",
  derivatives_dir = "/path/to/derivatives"
)

# Launch plasma input modelling app without preprocessing blood data
launch_apps(
  app = "modelling_plasma",
  bids_dir = "/path/to/your/bids/dataset",
  derivatives_dir = "/path/to/derivatives"
)

# Launch plasma input modelling app after producing derivative blood data
launch_apps(
  app = "modelling_plasma",
  bids_dir = "/path/to/your/bids/dataset",
  derivatives_dir = "/path/to/derivatives",
  blood_dir = "/path/to/blood/data"
)


# Launch reference tissue modelling app
launch_apps(
  app = "modelling_ref",
  derivatives_dir = "/path/to/derivatives",
)
```

### Automatic Pipeline Execution

**Two-Step Workflow:**

Automatic processing requires running region definition first, then modelling.

**Step 1: Region Definition**
```r
# Create combined TACs from preprocessing derivatives
# Searches for petfit_regions.tsv in either:
#   - derivatives_dir/petfit/petfit_regions.tsv
#   - bids_dir/code/petfit/petfit_regions.tsv

petfit_regiondef_auto(
  derivatives_dir = "/path/to/derivatives"
)

# Or with BIDS directory
petfit_regiondef_auto(
  bids_dir = "/path/to/bids"
)
```

**Step 2: Modelling Pipeline**
```r
# Execute complete modelling pipeline
# Uses "Primary_Analysis" subfolder by default

petfit_modelling_auto(
  derivatives_dir = "/path/to/derivatives",
  blood_dir = "/path/to/blood"
)

# Or using bids_dir (which will use bids_dir/derivatives)
petfit_modelling_auto(
  bids_dir = "/path/to/bids",
  blood_dir = "/path/to/blood"
)

# Specify a custom analysis subfolder
petfit_modelling_auto(
  analysis_subfolder = "Baseline_only",
  derivatives_dir = "/path/to/derivatives",
  blood_dir = "/path/to/blood"
)

# Execute specific modelling step
petfit_modelling_auto(
  derivatives_dir = "/path/to/derivatives",
  step = "weights"
)
```

## Docker Usage

### Pull Pre-built Image

```bash
docker pull mathesong/petfit:latest
```

Alternatively, build the container locally:

```bash
docker build -f docker/Dockerfile -t mathesong/petfit:latest .
```

### Interactive Mode

**Region Definition App**
```bash
docker run -it --rm \
  -v /path/to/your/bids:/data/bids_dir:ro \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  -p 3838:3838 \
  mathesong/petfit:latest \
  --func regiondef

# Then open http://localhost:3838 in your browser
```

**Modelling App with Plasma Input**
```bash
docker run -it --rm \
  -v /path/to/your/bids:/data/bids_dir:ro \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  -v /path/to/your/blood:/data/blood_dir:ro \
  -p 3838:3838 \
  mathesong/petfit:latest \
  --func modelling_plasma

# Then open http://localhost:3838 in your browser
```

**Modelling App with Reference Tissue**
```bash
docker run -it --rm \
  -v /path/to/your/bids:/data/bids_dir:ro \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  -p 3838:3838 \
  mathesong/petfit:latest \
  --func modelling_ref

# Then open http://localhost:3838 in your browser
```

### Automatic Processing Mode

**Two-Step Workflow:**

Automatic processing requires running region definition first, then modelling:

**Step 1: Region Definition**
```bash
# Create combined TACs from preprocessing derivatives
docker run --rm \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  mathesong/petfit:latest \
  --func regiondef \
  --mode automatic
```

*Note:* Region definition requires a `petfit_regions.tsv` file in either `derivatives/petfit/` or `bids_dir/code/petfit/`.

**Step 2: Modelling Pipeline**
```bash
# Run complete pipeline with plasma input models
docker run --rm \
  -v /path/to/your/bids:/data/bids_dir:ro \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  -v /path/to/your/blood:/data/blood_dir:ro \
  mathesong/petfit:latest \
  --func modelling_plasma \
  --mode automatic

# ... Or run complete pipeline with reference tissue models
docker run --rm \
  -v /path/to/your/bids:/data/bids_dir:ro \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  mathesong/petfit:latest \
  --func modelling_ref \
  --mode automatic

# Run specific analysis step
docker run --rm \
  -v /path/to/your/bids:/data/bids_dir:ro \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  -v /path/to/your/blood:/data/blood_dir:ro \
  mathesong/petfit:latest \
  --func modelling_plasma \
  --mode automatic \
  --step weights

# Use a custom analysis folder
docker run --rm \
  -v /path/to/your/bids:/data/bids_dir:ro \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  -v /path/to/your/blood:/data/blood_dir:ro \
  mathesong/petfit:latest \
  --func modelling_plasma \
  --mode automatic \
  --analysis_folder Baseline_only
```



### Docker Command Line Options

- `--func`: Application to run (`regiondef`, `modelling_plasma`, `modelling_ref`)
- `--mode`: Execution mode (`interactive` [default] or `automatic`)
- `--step`: Specific analysis step for automatic mode (optional)
- `--analysis_folder`: Analysis subfolder name for modelling outputs (default: `Primary_Analysis`)

### Docker Mount Points

- **BIDS Directory** (read-only): `/data/bids_dir:ro` - Your BIDS dataset
- **Derivatives Directory** (read-write): `/data/derivatives_dir:rw` - Folder into which a `petfit` directory will be created
- **Blood Directory** (read-only, optional): `/data/blood_dir:ro` - Blood data for plasma input models

### Docker File Permissions Note

On Linux systems, if you encounter permission issues where output files are owned by root, you have two options:

1. **Add the user flag** to run the container with your user ID:
   ```bash
   docker run --user $(id -u):$(id -g) \
     # ... rest of your docker command
   ```

2. **Fix permissions afterward** using chown:
   ```bash
   sudo chown -R $(id -u):$(id -g) /path/to/derivatives
   ```

## Outputs

The region definition apps create files in the main `derivatives/petfit` folder.

- **Region combination file**: `petfit_regions.tsv` contains all region combination names, and can be transferred to new studies and datasets with the same other pipelines.
- **Combined TACs file**: `desc-combinedregions_tacs.tsv` contains all the TACs after regional combinations.

The modelling apps generate the following outputs in `derivatives/petfit/<analysis_subfolder>/`:

- **Output file**: Parameters and outputs for each PET measurement are created in the relevant subject folders.
- **HTML reports**: Reports in `reports/` subfolder for each analysis step

## Directory Structure

PETFit uses a hierarchical directory structure:

- **bids_dir**: Your raw BIDS dataset containing source data
- **derivatives_dir**: The top-level derivatives folder (default: `{bids_dir}/derivatives`)
- **petfit directory**: `{derivatives_dir}/petfit/`
- **analysis_folder**: Analysis-specific subfolders within `{derivatives_dir}/petfit/{analysis_folder}` for modelling app outputs (default: `Primary_Analysis`).

The idea of the analysis folders is that the region definition app produces combined region TACs which are common to all analyses, and the analysis folders allow for using different data subsets (e.g. baseline-only), or measurement properties (e.g. restricting the TACs to a shorter duration) or different modelling approaches (e.g. plasma vs. reference tissue).
This allows the user to be flexible within the petfit directory and produce analyses with descriptive names.

```
bids_directory/                         # Raw BIDS data (bids_dir)
├── participants.tsv
├── code/petfit/
│   └── petfit_regions.tsv        # Region definitions
└── sub-*/ses-*/pet/

derivatives/                       # Processed outputs
└── petfit/                       # PETFit outputs
    ├── desc-combinedregions_tacs.tsv  # Combined TACs
    └── Analysis_Name/             # Analysis-specific folder
        ├── desc-petfitoptions_config.json
        ├── sub-01/sub-01_desc-combinedregions_tacs.tsv
        ├── sub-01/sub-01_model-1TCM_kinpar.tsv
        ├── ...
        └── reports/               # HTML reports
```

## Supported Models

### Invasive Models (Require Blood Input)
- **1TCM**: Single tissue compartment model
- **2TCM**: Two tissue compartment model
- **2TCM_irr**: Two tissue compartment model with irreversible binding
- **Logan**: Logan graphical analysis
- **MA1**: Multilinear analysis
- **Patlak**: Patlak graphical analysis

### Non-Invasive Models (Reference Region Based) (in development...)
- **SRTM**: Simplified reference tissue model
- **SRTM2**: Simplified reference tissue model 2
- **refLogan**: Reference Logan analysis
- **MRTM1**: Multilinear reference tissue model
- **MRTM2**: Multilinear reference tissue model 2
- **refPatlak**: Reference Patlak analysis

<!--## Workflow Overview-->
<!---->
<!--### Region Definition-->
<!--1. Specify BIDS directory and segmentation files-->
<!--2. Define custom regions from individual segments-->
<!--3. Generate volume-weighted combined TACs-->
<!--4. Export region configuration-->
<!---->
<!--### Modelling Apps-->
<!--1. **Data Definition**: Subset data by subject, session, tracer, and select regions-->
<!--2. **Weights Calculation**: Choose from predefined or custom weighting methods-->
<!--3. **Delay Estimation** (optional): Estimate blood-tissue temporal delays-->
<!--4. **Model Configuration**: Configure up to 3 models with parameter bounds and options-->
<!--5. **Interactive Exploration**: Test model configurations on individual measurements-->

## Citation

If you use PETFit in your research, please cite *kinfitr* for now:

An introduction to the package:

> Matheson, G. J. (2019). *Kinfitr: Reproducible PET Pharmacokinetic Modelling in R*. bioRxiv: 755751. https://doi.org/10.1101/755751

A validation study compared against commercial software:

> Tjerkaski, J., Cervenka, S., Farde, L., & Matheson, G. J. (2020). *Kinfitr – an open source tool for reproducible PET modelling: Validation and evaluation of test-retest reliability*. EJNMMI Res 10, 77 (2020). https://doi.org/10.1186/s13550-020-00664-8

## Contributing

Contributions are welcome! Please report issues or submit pull requests on GitHub at https://github.com/mathesong/petfit.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Built around the *kinfitr* package for PET kinetic modelling
- Uses the Shiny framework for interactive web applications
- Docker implementation based on rocker/shiny-verse
- Follows BIDS conventions for neuroimaging data organisation
