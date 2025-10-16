# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This will include an R Shiny web application that creates customized petfit BIDS App configuration files for PET imaging analysis, which will be within a docker container. It will also include parameterised reports which will run using the parameters in the configuration files. The app will provide a user interface for configuring kinetic modeling parameters for Time Activity Curves (TACs) while delegating kinetic model fitting to the `kinfitr` package.

The system supports multiple usage modes:
1. **Non-interactive processing**: Run kinetic modelling using pre-existing .json configuration files without GUI
2. **GUI-assisted setup**: Use the Shiny apps to create configuration files, then run processing
3. **Interactive exploration**: Use the modelling app's interactive tab to test model fits on individual TACs

The three apps work independently:
- **Region Definition App**: Creates brain region definitions and combined TACs
- **Modelling App with Plasma Input**: Configures invasive kinetic models (1TCM, 2TCM, Logan, MA1) requiring blood input data
  - Includes an interactive tab for testing model fits on individual PET measurements and regions
  - Allows users to validate model specifications and parameter bounds before full processing
- **Modelling App with Reference Tissue**: Configures non-invasive kinetic models (SRTM, refLogan, MRTM1, MRTM2) using reference regions
  - Same interactive capabilities as the plasma input app

## Commands

### Running the Application
```r
# Load the package and launch apps
library(petfit)

# Launch specific app using launcher (regiondef is default)
launch_apps(bids_dir = "/path/to/bids")  # Launches regiondef by default
launch_apps(app = "modelling_plasma", bids_dir = "/path/to/bids", blood_dir = "/path/to/blood")
launch_apps(app = "modelling_ref", bids_dir = "/path/to/bids")

# Or launch apps directly
region_definition_app(bids_dir = "/path/to/bids")
modelling_plasma_app(bids_dir = "/path/to/bids", blood_dir = "/path/to/blood")
modelling_ref_app(bids_dir = "/path/to/bids")
```

### Container Usage

**Docker**: Interactive apps and automatic processing modes available
**Singularity**: HPC-compatible, use scripts in singularity/ folder

### Development
- This is a proper R package with DESCRIPTION file and roxygen documentation
- Three separate Shiny apps: `region_definition_app.R`, `modelling_plasma_app.R`, and `modelling_ref_app.R` in R/ directory
- Parameterised reports are Rmd files located in inst/rmd/ folder (following R package convention)
- Dependencies managed through DESCRIPTION file
- Modular code structure with separate files for utilities, validation, and UI modules

## Architecture

### Application Structure
- **Three-app system**:
  - `region_definition_app.R`: For defining brain regions and creating combined TACs
  - `modelling_plasma_app.R`: For invasive kinetic model configuration (1TCM, 2TCM, Logan, MA1)
  - `modelling_ref_app.R`: For non-invasive kinetic model configuration (SRTM, refLogan, MRTM1, MRTM2)
- **Package Structure**: Proper R package with R/, man/, data/, and inst/rmd/ directories
- **UI Layout**: All apps use `fluidPage` with sidebar layout
- **Server Logic**: Reactive expressions generate JSON configurations and process data
- **Launcher Function**: `launch_apps()` launches one app at a time with `match.arg()` validation

### Directory Structure
The system uses a standard BIDS (Brain Imaging Data Structure) directory layout:

- **bids_dir**: Root BIDS directory containing raw data and standard BIDS structure
  - `code/petfit/`: Contains region configuration files (`petfit_regions.tsv`)
  - Standard BIDS subject/session structure for source data
  
- **derivatives_dir**: Processed data following BIDS derivatives convention
  - Default: `{bids_dir}/derivatives/` when bids_dir is provided
  - Can be specified independently to any location for flexibility
  - Contains all processed outputs and analysis results
  
- **petfit folder**: `{derivatives_dir}/petfit/` - Contains shared petfit resources
  - `desc-combinedregions_tacs.tsv`: Combined TACs file from region definition app with seg_meanTAC column
  - Contains volume-weighted mean TAC for entire segmentations (seg_meanTAC column)
  - Shared across all analyses and accessed by modelling apps
  
- **analysis folder**: `{derivatives_dir}/petfit/{subfolder}/` - Analysis-specific outputs
  - Individual TACs files created by modelling apps subsetting
  - Configuration files for specific analyses (e.g., `desc-petfitoptions_config.json`)
  - **reports/** subfolder: Contains parameterised HTML reports for each analysis step
  - Default subfolder: "Primary_Analysis"
  - Each analysis gets its own subfolder to keep configurations separate

### Key Dependencies
- `shiny`: Core web application framework
- `shinythemes`: UI theming
- `bslib`: Bootstrap components
- `jsonlite`: JSON generation for config files
- `kinfitr`: Core kinetic modeling functionality used by petfit
- `readr`: Robust file reading/writing (replaces base R read.table/write.table)
- `rmarkdown`: Parameterised report generation
- `knitr`: Dynamic document generation for reports
- **Data manipulation**: `tidyverse` ecosystem (`dplyr`, `tibble`, `purrr`, `stringr`, `tidyr`) - preferred over base R equivalents
- Plotting: `ggplot2` (for report visualizations)
- Other utilities: `glue`, `magrittr`, `later`

### Core Functionality
1. **Region Configuration**: Define brain regions and segmentation parameters
2. **BIDS Integration**: Automatic integration of participant data and PET metadata into TACs files
3. **Data Subsetting**: Filter by subject, session, tracer, etc.
4. **Weights Definition**: Create weights for modelling
5. **Fit delay**: Estimate the delay between the blood and tissue curves
6. **t* Finder**: Determine optimal start time (t*) for linear kinetic models (coming soon)
7. **Enhanced Model Selection**: Choose between comprehensive kinetic models with full parameter configuration:
   - **Invasive Models**: 1TCM, 2TCM, Logan, MA1 (require blood input data)
   - **Non-invasive Models**: SRTM, refLogan, MRTM1, MRTM2 (use reference regions)
   - **Three Model Comparison**: Configure up to 3 models simultaneously for outcome comparison
8. **Advanced Parameter Configuration**: Set model-specific start/lower/upper bounds, fit options, and priors
9. **Comprehensive Config Generation**: Create detailed JSON configuration files with complete model specifications
10. **Interactive Data Exploration**: Manual data loading and visualization with model-aware plotting
11. **State Persistence**: Automatically save and restore complete app configuration including all model parameters
12. **Parameterised Reports**: Automatically generate HTML reports for each analysis step for quality control and review
13. **Segmentation Mean TACs**: Pre-calculated volume-weighted mean TACs for external segmentations to avoid BIDS directory access during weights calculation

### Region Definition and File Matching System

The region definition app uses a sophisticated seg/label-based matching system conforming to the PET Preprocessing Derivatives BIDS specification.

#### BIDS Entity-Based Matching

**Primary Matching Attributes** (required for matching):
- `sub`: Subject identifier (exact match required)
- `seg`: Segmentation type (e.g., "gtm", "wm") - exact match required
- `label`: Region label (e.g., "semiovale") - exact match required
- Files must have either `seg` OR `label` attribute

**Hierarchical Matching Attributes** (optional, hierarchical):
- `ses`: Session identifier - hierarchical match (morph without ses matches all ses values)
- `run`: Run identifier - hierarchical match (morph without run matches all run values)

**Ignored Attributes** (for matching purposes):
- `pvc`: Partial volume correction variant (e.g., "AGTM") - shown in UI but not used for matching
- `desc`: Description field - not used for matching
- `rec`: Reconstruction field - not used for matching
- `task`: Task field - not used for matching

#### Matching Logic

**Exact Match Requirements:**
1. Subject (`sub`) must match exactly between tacs and morph files
2. Segmentation (`seg`) OR label (`label`) must match exactly

**Hierarchical Match Behavior:**
- If morph file has `ses`, tacs file must have same `ses` value
- If morph file lacks `ses`, it matches ALL `ses` values for that subject
- Same logic applies to `run` attribute
- This enables one-to-many relationships: one morph file can serve multiple tacs variants

**Example Matching Scenarios:**
```
# One-to-many: Different pvc variants share same morph
sub-P3_pvc-AGTM_seg-gtm_tacs.tsv  → sub-P3_seg-gtm_morph.tsv
sub-P3_seg-gtm_tacs.tsv            → sub-P3_seg-gtm_morph.tsv

# Hierarchical: Morph without ses/run matches all variants
sub-P3_ses-01_run-1_seg-gtm_tacs.tsv → sub-P3_seg-gtm_morph.tsv
sub-P3_ses-01_run-2_seg-gtm_tacs.tsv → sub-P3_seg-gtm_morph.tsv
sub-P3_ses-02_run-1_seg-gtm_tacs.tsv → sub-P3_seg-gtm_morph.tsv

# Label-based matching
sub-P3_label-semiovale_tacs.tsv    → sub-P3_label-semiovale_morph.tsv
```

#### Directory Structure Support

**Flexible File Organization:**
- Supports both flat and hierarchical directory structures
- Recursive search within pipeline folders finds files in any subdirectory depth
- Common patterns:
  - `pet/` subdirectory for tacs files
  - `anat/` subdirectory for morph files
  - Flat structure with all files in same directory

#### Volume Fallback Behavior

**Missing Morph Files:**
- If no matching morph file found: uses `volume=1` for all regions (equal weighting)
- Warning message references "PET Preprocessing Derivatives BIDS specification"
- Region combination still proceeds successfully
- Files without `seg` or `label` attributes are silently filtered

#### Performance Optimization

**Efficient Bulk Matching:**
- One recursive file search per pipeline folder (not per file)
- `create_tacs_morph_mapping()` function creates complete mapping upfront
- Uses `dplyr` joins instead of loops for matching logic
- Handles thousands of files efficiently

**Key Functions:**
- `extract_bids_attributes_from_filename()`: Parses BIDS entities from filenames
- `create_tacs_morph_mapping()`: Bulk matching using dplyr joins
- `get_region_volumes_from_morph()`: Reads morph files with volume=1 fallback
- `combine_single_region_tac()`: Volume-weighted TAC combination with fallback support

### Interactive Data Exploration System

Both modelling apps include a dedicated Interactive tab for manual data exploration and validation:

#### Workflow
1. **Manual File Scanning**: "Scan Analysis Folder" button to populate available PET measurements and regions
2. **Selective Data Loading**: Choose specific PET measurement, region, and model configuration
3. **On-Demand Plotting**: "Load Data" button for controlled TAC visualization
4. **Model Preparation**: "Fit Model" button ready for future model testing functionality

#### Key Features
- **Manual Control**: No automatic data loading - user controls when to scan and load data
- **Pre-populated Options**: Automatically extracts available PET measurements and regions from analysis folder
- **Model-Aware Display**: Shows which model configuration is being used for the visualization
- **Professional Plotting**: ggplot2 with theme_light(), proper sizing (800x500px, 96 DPI) for clear display
- **Error Handling**: Clear validation messages when required selections are missing

#### Technical Implementation
- **File Detection**: Scans for `*_desc-combinedregions_tacs.tsv` files in analysis folder
- **Reactive Data Storage**: Uses `reactiveVal()` to store plot data independently from UI inputs
- **Non-Reactive Plotting**: Plot only updates when Load Data button is pressed, not on dropdown changes
- **Sidebar Layout**: Clean 1/3 controls, 2/3 plot layout for optimal user experience

### Parameterised Reports System

The petfit app includes a comprehensive parameterised reporting system that automatically generates HTML reports for each analysis step. These reports are designed for quality control, data visualization, and workflow documentation.

#### Report Structure
- **Location**: Reports are generated in `{analysis_folder}/reports/`
- **Format**: HTML documents with embedded plots and tables
- **Template Source**: R Markdown templates in `inst/rmd/` folder
- **Generation**: Automatic generation after each analysis step completion

#### Available Report Templates

**Step-Based Reports:**
- `data_definition_report.Rmd` → `data_definition_report.html`
- `weights_report.Rmd` → `weights_report.html`  
- `delay_report.Rmd` → `delay_report.html`

**Model-Specific Reports:**
- `1tcm_report.Rmd` → Used for 1TCM model fitting
- `2tcm_report.Rmd` → Used for 2TCM model fitting
- `logan_report.Rmd` → Used for Logan analysis
- `fit_delay_report.Rmd` → Used for delay-fitting models

**Procedure Reports:**
- `tstar_finder_report.Rmd` → `tstar_finder_report.html` (for future t* finder tab)

#### Dynamic Template Selection

The system uses **dynamic template selection** for model reports:
- Template chosen based on user's model selection (`input$button`, `input$button2`, `input$button3`)
- Output files always named consistently: `model1_report.html`, `model2_report.html`, `model3_report.html`
- Same template can generate different numbered reports depending on user choices

**Example**: If user selects "2TCM" for Model 1 and "Logan" for Model 2:
- `2tcm_report.Rmd` generates `model1_report.html`
- `logan_report.Rmd` generates `model2_report.html`

#### Report Generation Functions

Located in `R/report_generation.R`:

- `generate_step_report()`: Creates step-based reports (data definition, weights, delay)
- `generate_model_report()`: Creates model-specific reports with dynamic template selection
- `generate_tstar_report()`: Creates t* finder analysis reports
- `get_model_template()`: Maps model types to appropriate template files
- `generate_reports_summary()`: Creates summary page linking all generated reports

#### Integration with Shiny App

Reports are automatically generated by button handlers in the modelling apps (`modelling_plasma_app.R` and `modelling_ref_app.R`):
- **Data Definition**: Generated after "Create Analysis Data" button execution
- **Weights/Delay**: Generated after respective button executions
- **Model Reports**: Generated after "Fit Model X" button executions
- **User Notifications**: Success messages inform users when reports are generated

#### Report Content and Purpose

**Primary Purpose**: Quality control and data visualization for user review

**Standard Content**:
- Analysis configuration summary
- Data processing statistics  
- Visualization plots (TACs, fits, diagnostics)
- Quality control metrics
- Parameter estimates and uncertainties
- Next steps recommendations
- Session information

**Key Dependencies**: 
- `rmarkdown`: Report rendering engine
- `knitr`: Dynamic document generation
- Standard plotting libraries (`ggplot2`, etc.)

#### Interactive Plotly Reports

**IMPORTANT**: Reports perform actual computational work - templates contain analysis logic for transparency and reproducibility.

**Key Libraries**: `plotly`, `crosstalk`, `htmltools`

**Critical Patterns**:
- Render multiple plots: `htmltools::tagList(plot_list)` (not direct printing)
- Dimensions: Set in `layout(width = 800, height = 500)` not CSS
- Spacing: `htmltools::div(.x, style="margin: 20px 0 50px 0;")`
- Cross-filtering: `crosstalk::SharedData$new()` with `highlight(on = "plotly_hover", off = "plotly_doubleclick")`

##### Advanced R Markdown Patterns

**Conditional Chunk Evaluation:**
```r
# Dynamic chunk execution based on conditions
```{r, eval=condition_variable, echo=condition_variable}
# Code only runs when condition_variable is TRUE
```

**Dynamic Content Generation:**
```r
```{r, echo=FALSE}
#| results: asis

if(condition) {
  str_glue("Dynamic text based on data characteristics")
}
```

##### User Experience Best Practices

**Progressive Notification System:**
```r
# CORRECT: Progressive feedback for long operations
showNotification("Generating report...", duration = NULL, id = "generating_report")
# ... perform work ...
removeNotification(id = "generating_report")
showNotification("Report generated successfully", duration = 5)

# WRONG: Technical implementation details in notifications
showNotification("Created 15 files in analysis folder", ...)  # Too technical
```

**Professional Report Presentation:**
- **Table of Contents**: `toc: true, toc_depth: 2` in YAML header
- **Code Folding**: `code_folding: hide` to show results while hiding implementation
- **Timestamps**: `format(Sys.time(), "%Y-%m-%d %H:%M:%S")` for generation tracking
- **Session Info**: `sessionInfo()` for complete reproducibility

### File Management
- Generates config files: `desc-petfitoptions_config.json` in analysis folder
- **Combined TACs Files**: `desc-combinedregions_tacs.tsv` with integrated BIDS metadata
- **Individual TACs Files**: Created by modelling apps with `desc-combinedregions` naming convention
- **State Persistence**: Apps automatically save and restore configuration
  - On startup: Checks for existing config file in analysis folder
  - If found: Restores all UI inputs to previous state with user notification
  - If corrupted: Shows error message and uses defaults
  - On actions: Saves current state before executing operations

### Data Integration and Processing
**BIDS Participant Data Integration**: The system automatically integrates participant demographics and PET metadata into combined TACs files:

1. **Participant Data Loading**: 
   - Reads `participants.tsv` and `participants.json` files from BIDS root
   - Transforms participant_id format (sub-01 → 01) for consistency
   - Maps participant weight to `bodyweight` column for SUV calculations

2. **PET Metadata Extraction**:
   - Uses `kinfitr::bids_parse_study()` for robust BIDS parsing
   - Extracts `InjectedRadioactivity` from PET JSON sidecars
   - Automatically converts radioactivity units to kBq using `kinfitr::unit_convert()`

3. **Combined TACs Structure**:
   **Column order**: `sub, ses, trc, rec, task, run, segmentation, pet, InjectedRadioactivity, bodyweight, [participant_columns], region, volume_mm3, frame_start, frame_end, frame_dur, frame_mid, TAC, seg_meanTAC`

   *Note: Participant columns (e.g., age, sex) are inserted after bodyweight when available from participants.tsv*

   - **BIDS identifiers**: sub, ses, trc, rec, task, run, segmentation, pet (preserved as character types)
     - **segmentation**: Full preprocessing pipeline identifier (e.g., "petprep: seg-gtm_pvc-AGTM") - combines pipeline name with all segmentation attributes
     - **pet**: PET measurement identifier containing only BIDS attributes that vary across the dataset (from: sub, ses, trc, rec, task, run)
   - **Metabolic data**: InjectedRadioactivity (kBq), bodyweight (kg for SUV calculations)
   - **Participant data**: Optional columns from participants.tsv (e.g., age, sex, weight) - weight mapped to bodyweight
   - **Region data**: region (combined region name), volume_mm3 (total volume)
   - **Time series**: frame_start, frame_end, frame_dur, frame_mid, TAC (volume-weighted average), seg_meanTAC (segmentation-wide mean)

4. **Individual Analysis Files**:
   **Exact column order**: `pet, region, volume_mm3, InjectedRadioactivity, bodyweight, frame_start, frame_end, frame_dur, frame_mid, TAC`

   - Created by "Create Analysis Data" button in modelling apps
   - **pet column first**: Essential for data tracking and analysis identification
   - Essential kinetic modeling metadata positioned after volume_mm3, before frame timing
   - Use `desc-combinedregions` naming convention (not `desc-combinedtacs`)
   - Filename pattern: `{pet_id}_desc-combinedregions_tacs.tsv`

### File I/O Standards
**CRITICAL**: Use appropriate packages for different file types to ensure robust data handling:

#### Tabular Data (.tsv, .csv files)
- **Reading**: Use `readr::read_tsv()` instead of `read.table()`
  - Preserves character data types (prevents "01" → 1 conversion)
  - Handles various encoding and formatting issues robustly
  - Use `show_col_types = FALSE` to suppress column type messages

- **Writing**: Use `readr::write_tsv()` instead of `write.table()`
  - Consistent tab-separated output formatting
  - Proper handling of special characters and encoding

#### JSON Data (.json files)
- **Reading/Writing**: Use `jsonlite` functions as usual
  - `jsonlite::read_json()` and `jsonlite::write_json()`
  - `jsonlite::fromJSON()` and `jsonlite::toJSON()`
- **Critical JSON Formatting**: Always use `auto_unbox = TRUE` when writing JSON configuration files
  - Prevents single values from being wrapped in arrays: `"mean_combined"` instead of `["mean_combined"]`
  - Essential for proper configuration loading and template processing

**Example patterns:**
```r
# Reading/writing TSV files
data <- readr::read_tsv(file_path, show_col_types = FALSE)
readr::write_tsv(data, output_path)

# Reading/writing JSON files
config <- jsonlite::read_json(json_path)
jsonlite::write_json(config, output_path, pretty = TRUE, auto_unbox = TRUE)
```

This ensures consistent, reliable file operations and prevents data type conversion issues with tabular data while maintaining proper JSON handling.

### Delay Fitting System Architecture

**Blood Data Detection and Status Display**: The system provides Docker-compatible blood data detection with clean visual feedback:

#### Blood Data Detection Logic
The system detects blood data files using the pattern `"_(blood|inputfunction)\\.tsv$"` to find both:
- `*_blood.tsv` files (raw BIDS blood data)
- `*_inputfunction.tsv` files (processed input functions)

#### Status Display Scenarios

| Scenario | bids_dir | blood_dir | Blood Files Found | Display |
|----------|----------|-----------|-------------------|---------|
| **Explicit blood directory provided** | Any | ✓ Provided | ✓ Found | ✅ **Green tick**: "Blood data found" + file count |
| **Explicit blood directory provided** | Any | ✓ Provided | ✗ Not found | ❌ **Red cross**: "No blood data found in blood_dir" |
| **BIDS directory only** | ✓ Provided | ✗ Not provided | ✓ Found | ✅ **Green tick**: "Blood data found" + recommendation |
| **BIDS directory only** | ✓ Provided | ✗ Not provided | ✗ Not found | ❌ **Red cross**: "No blood data found in bids_dir" |
| **No directories provided** | ✗ Not provided | ✗ Not provided | N/A | ⚠️ **Warning**: "No blood data available" |

#### Key Features
- **Docker-compatible**: No directory paths shown (problematic in containers where paths may differ)
- **Comprehensive detection**: Handles both raw blood data and processed input functions
- **Visual feedback**: Clear green tick (✓) for success, red cross (✗) for missing data
- **Consistent logic**: Same detection used for both UI display and processing validation
- **User-friendly messaging**: File counts and helpful recommendations without technical details

#### Implementation Details
- Status display function: `delay_blood_status_display` (in both modelling apps)
- Processing validation: `run_delay` event handler (in both modelling apps)
- Helper function: `check_blood_files()` for consistent file detection logic

**Delay Estimation Approaches**: Comprehensive set of delay estimation methods ordered by computational speed:

- `"Set to zero (i.e. no delay fitting to be performed)"` - Skip delay estimation entirely
- `"1TCM Delay from Single Representative TAC (Quick)"` - Single region approach
- `"2TCM Delay from Single Representative TAC (Less Quick)"` - Complex model, single region  
- `"1TCM Median Delay from Multiple Regions (Recommended, Slow)"` - **Default**, multiple region analysis
- `"2TCM Median Delay from Multiple Regions (Very Slow)"` - Most comprehensive approach

**Note**: Linear 2TCM Profile method is commented out in the code for future implementation.

**Multiple Regions Analysis**: For "Multiple Regions" approaches:
- **Optional Region Subsetting**: `delay_multiple_regions` field allows semicolon-separated region specification
- **Default Behavior**: Leave blank to analyze all available regions
- **Conditional UI**: Text input only appears when multiple regions approaches are selected

**Configuration Fields**: FitDelay section includes:
- `blood_source`: Selected blood data source
- `model`: Delay estimation approach (default: `"1tcm_median"`)
- `time_window`: Minutes of data for fitting (default: 5, recommended for early phase sensitivity)
- `regions`: General region selection (legacy)
- `multiple_regions`: Region subset for multiple regions approaches
- `vB_value`, `fit_vB`, `use_weights`: Parameter settings
- `inpshift_lower`, `inpshift_upper`: Blood input time shift search limits in minutes (defaults: -0.5, 0.5)

**Blood Input Time Shift Controls**: The system provides user-configurable limits for the delay parameter search range:

- **UI Controls**: Two numeric inputs in the "Blood Time Shift Search Range" section of the delay fitting tab
  - Lower limit: Default -0.5 minutes (range: -5 to 0, step 0.1)
  - Upper limit: Default 0.5 minutes (range: 0 to 5, step 0.1)
- **Purpose**: Defines the search boundaries for the `inpshift` parameter during model fitting
- **Interpretation**: Time shift represents the degree to which blood input times are adjusted to align with tissue data
- **Implementation**: Added to all delay estimation model fitting functions (`onetcm`, `twotcm`) via `inpshift.lower` and `inpshift.upper` parameters
- **Report Display**: Time shift limits are shown in the delay report's Parameter Settings section for transparency

### Weights System Architecture

**External Segmentation Support**: The system now supports using volume-weighted mean TACs from entire segmentations for weights calculation through an optimized workflow:

1. **Region Definition App**: 
   - Calculates `seg_meanTAC` column during combined regions creation
   - Volume-weighted mean across ALL regions within each segmentation (desc) 
   - Added to `desc-combinedregions_tacs.tsv` as additional column

2. **Modelling App**:
   - Reads unique `segmentation` values from combined regions file to populate external segmentation dropdown
   - Default weights region type is now "Mean of external segmentation" (optimal approach)
   - Validates combined regions files exist before allowing weights calculation

3. **Weights Report Template**:
   - Uses pre-calculated `seg_meanTAC` for external segmentation weights
   - No longer requires access to original BIDS directory during weights calculation
   - Automatically saves individual weight files in BIDS structure alongside TACs files
   - Generates `{pet_id}_desc-weights_weights.tsv` in same directories as corresponding TACs files

**Configuration Management**: 
- JSON config now stores actual formulas in `formula` field (replaces `custom_formula`)
- For predefined methods: stores mathematical formula (e.g., "sqrt(frame_dur * tac_uncor)")
- For custom methods: stores user-provided formula
- Uses shorter variable names (`tac_uncor` instead of `tac_uncorrected`) for cleaner formulas

### Coding Standards

**IMPORTANT**: Follow tidyverse conventions throughout the codebase for consistency and maintainability.

#### Data Manipulation Standards
- **Use `tidyverse` over base R**: Import `library(tidyverse)` in reports and use tidyverse functions
- **Data structures**: Use `tibble()` instead of `data.frame()`
- **Functional programming**: Use `purrr` functions (`map()`, `walk()`, etc.) instead of `apply()` family
- **String manipulation**: Use `stringr` functions (`str_detect()`, `str_replace()`, etc.) instead of base R
- **Data transformation**: Use `dplyr` verbs (`mutate()`, `filter()`, `select()`, etc.)

#### Examples of Preferred Patterns
```r
# PREFERRED (tidyverse)
library(tidyverse)
data_df <- tibble(
  Parameter = names(config_section),
  Value = map_chr(config_section, as.character)
)

# AVOID (base R)
library(dplyr)
library(ggplot2) 
data_df <- data.frame(
  Parameter = names(config_section),
  Value = sapply(config_section, as.character)
)
```

#### Report Template Standards
- Always load `library(tidyverse)` instead of individual packages
- Use `tibble()` for creating data frames in reports
- Use `map_*()` functions for iteration instead of `sapply()` or `apply()`
- **Use British English spelling**: "visualisation" not "visualization", "colour" not "color", "analyse" not "analyze", etc.
- Maintain consistent code style across all templates

### Critical Implementation Details

#### File I/O Migration Issues
**IMPORTANT**: When migrating from `read.table()` to `readr::read_tsv()`, several column name handling assumptions must be updated:

1. **Column Name Preservation**: 
   - `read.table()` sometimes converts hyphens to dots (`"Left-Accumbens-area"` → `"Left.Accumbens.area"`)
   - `readr::read_tsv()` preserves original column names with hyphens
   - **Fix**: Remove any hyphen-to-dot conversion logic in region matching

2. **Morph File Columns**:
   - Old assumption: `volume.mm3` (with dot)  
   - Reality with readr: `volume-mm3` (with hyphen)
   - **Fix**: Use backticks for non-standard column names: `select(name, \`volume-mm3\`)`

3. **Character Type Preservation**:
   - `readr::read_tsv()` automatically maintains character types for BIDS identifiers
   - Subject IDs stay as "01", "02", "03" instead of converting to numeric 1, 2, 3
   - No additional `colClasses` specification needed

#### Common Migration Pitfalls
These specific code patterns needed fixing during the readr migration:

```r
# WRONG (old read.table assumptions)
constituent_regions_tacs <- str_replace_all(constituent_regions, "-", ".")
available_in_tacs <- constituent_regions[constituent_regions_tacs %in% colnames(tacs_data)]
region_volumes <- morph_data %>% select(name, volume.mm3)

# CORRECT (readr-compatible)  
available_in_tacs <- constituent_regions[constituent_regions %in% colnames(tacs_data)]
region_volumes <- morph_data %>% select(name, `volume-mm3`)
```

#### dplyr any_of() Function Syntax
**CRITICAL**: When using `any_of()` with multiple column names, always use vector syntax:

```r
# CORRECT: Use c() to create a vector of column names
select(-any_of(c("vB", "inpshift")))

# WRONG: Multiple string arguments without c()
select(-any_of("vB", "inpshift"))  # This will cause errors
```

This pattern is used throughout the report templates for excluding optional model parameters from output tables.

### Configuration Management
**CRITICAL DESIGN PRINCIPLE**: When adding new functionality to the modelling app, always ensure backward compatibility with existing JSON configuration files.

**Requirements for new features:**
1. **Safe Loading**: Use null coalescing (`%||%`) when accessing new config properties
2. **Default Values**: Provide sensible defaults for missing configuration sections
3. **Error Handling**: Gracefully handle missing or invalid configuration data
4. **User Feedback**: Inform users when config loading fails or succeeds
5. **State Restoration**: Add UI update logic for any new input fields

**Example pattern for new features:**
```r
# Safe restoration of new feature
if (!is.null(existing_config$NewFeature)) {
  updateTextInput(session, "new_input", value = existing_config$NewFeature$parameter %||% "default")
}
```

This ensures users can seamlessly continue work with existing configurations even after app updates.

#### JSON Configuration Best Practices
**Critical Implementation Details for Weights and Other Configuration Sections**:

1. **Conditional Field Management**: 
   - Set unused conditional fields to empty strings (`""`) in JSON
   - Convert empty strings to `NULL` in R templates/functions
   - Prevents confusion where irrelevant fields show values from other options

2. **Proper JSON Structure**:
   ```r
   # CORRECT: Conditional fields set appropriately
   Weights <- list(
     region_type = input$weights_region_type %||% "mean_combined",
     region = if(input$weights_region_type == "single") input$weights_region %||% "" else "",
     external_tacs = if(input$weights_region_type == "external") input$weights_external_tacs %||% "" else "",
     radioisotope = input$weights_radioisotope %||% "C11",
     halflife = if(input$weights_radioisotope == "Other") as.character(input$weights_halflife %||% 20.4) else "",
     method = input$weights_method %||% "2",
     custom_formula = if(input$weights_method == "custom") input$weights_custom_formula %||% "" else "",
     minweight = input$weights_minweight %||% 0.25
   )
   ```

3. **Template Processing**:
   ```r
   # CORRECT: Convert empty strings to NULL for function calls
   halflife <- if(halflife_raw == "" || is.null(halflife_raw)) NULL else as.numeric(halflife_raw)
   custom_formula <- if(custom_formula_raw == "" || is.null(custom_formula_raw)) NULL else custom_formula_raw
   ```

### Model Types Supported

#### Invasive Models (Require Blood Input Data)
- **1TCM**: Single tissue compartment model with K1, k2, vB parameters and bounds
- **2TCM**: Two tissue compartment model with K1, k2, k3, k4, vB parameters and bounds
- **Logan**: Logan graphical analysis with t* parameter and optional vB fitting
- **MA1**: Multilinear analysis with t* parameter and optional vB fitting

#### Non-Invasive Models (Use Reference Regions)
- **SRTM**: Simplified reference tissue model with R1, k2, k2a parameters and bounds
- **refLogan**: Reference Logan analysis with t* parameter
- **MRTM1**: Multilinear reference tissue model with R1, k2, k2a parameters and bounds  
- **MRTM2**: Multilinear reference tissue model 2 with R1 parameters and k2a prior value

#### Model Configuration Features
- **No Model Option**: Default selection allowing users to skip model fitting
- **Three Simultaneous Models**: Configure Models 1, 2, and 3 for comparison studies
- **Complete Parameter Control**: Start values, lower/upper bounds, and fit options for all parameters
- **Flexible Model Selection**: Mix invasive and non-invasive models as needed
- **State Persistence**: All model configurations saved and restored automatically


### UI Components
- Conditional panels that show/hide based on selected model
- Numeric inputs with validation (min/max bounds, step sizes)
- Text inputs for region names and filtering criteria
- Checkbox inputs for optional parameter fitting

## Troubleshooting

**No TACs Files Found**: Files missing `seg` or `label` attributes - add to filenames following BIDS specification

**TACs/Morph Mismatch**: Check exact case-sensitive match for `sub` and `seg`/`label` values; missing morph uses volume=1 fallback

**Combined TACs Not Generated**: Column name issues - use `readr::read_tsv()` (preserves hyphens) and backticks for non-standard names like `\`volume-mm3\``

**Character Conversion**: Subject IDs as numbers instead of strings - replace `read.table()` with `readr::read_tsv()`

**Report Generation Fails**: Check template files in `inst/rmd/`, verify dependencies (`rmarkdown`, `knitr`), test with `rmarkdown::render()`
