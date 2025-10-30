# petfit Test Suite

This directory contains a comprehensive test suite for the petfit R package, implementing best practices for R package testing using the testthat framework.

## Test Structure

```
tests/
├── testthat.R                    # Main test runner
├── testthat/
│   ├── fixtures/                 # Test data and setup utilities
│   │   ├── setup.R              # Test helper functions and BIDS structure creation
│   │   └── sample_configs/      # Sample JSON configuration files
│   ├── helper-setup.R           # Test environment setup (loads here package)
│   ├── test-bids_utils.R        # Tests for BIDS parsing functions
│   ├── test-blood_utils.R       # Tests for blood data management
│   ├── test-docker_functions.R  # Tests for validation and pipeline functions
│   ├── test-launch_petfit_apps.R # Tests for app launcher
│   ├── test-region_utils.R      # Tests for region processing functions
│   ├── test-report_generation.R # Tests for report generation (1TCM/2TCM focus)
│   └── test-subsetting_utils.R  # Tests for data filtering functions
└── README.md                    # This file
```

## Test Coverage

### Core Functions Tested

#### 1. Data Processing (test-region_utils.R)
- **`combine_single_region_tac()`**: Volume-weighted averaging of brain regions
- **`extract_bids_attributes_from_filename()`**: BIDS filename parsing
- **`load_participant_data()`**: Participant demographics integration
- **`extract_pet_metadata()`**: PET scan metadata extraction
- **`create_petfit_combined_tacs()`**: Full TACs file generation with BIDS integration
- **`calculate_segmentation_mean_tac()`**: Volume-weighted mean TAC calculation

#### 2. Data Subsetting (test-subsetting_utils.R)
- **`parse_semicolon_values()`**: String parsing with comprehensive edge cases
- **`subset_combined_tacs()`**: Data filtering by BIDS entities
- **`create_individual_tacs_files()`**: Individual TACs file generation

#### 3. BIDS Integration (test-bids_utils.R)
- **`attributes_to_title()`**: BIDS attribute string formatting
- **`get_pet_identifiers()`**: PET measurement ID extraction

#### 4. Blood Data Management (test-blood_utils.R)
- **`determine_blood_source()`**: Blood file detection and cataloging
- **`get_blood_data_status()`**: UI status reporting for blood data
- **`blooddata2inputfunction_tsv()`**: Blood data format conversion

#### 5. Validation & Pipeline (test-docker_functions.R)
- **`validate_directory_requirements()`**: Directory validation for Docker
- **`validate_blood_requirements()`**: Blood data requirement analysis
- **`petfit_modelling_auto()`**: Full modelling pipeline execution testing
- **`petfit_regiondef_auto()`**: Region definition pipeline execution testing
- **`execute_pipeline_step()`**: Individual step execution

#### 6. Report Generation (test-report_generation.R)
- **`get_model_template()`**: Template selection (1TCM/2TCM focus)
- **`generate_step_report()`**: Step-specific report creation
- **`generate_model_report()`**: Model-specific report generation
- **`generate_reports_summary()`**: Summary page creation

#### 7. App Integration (test-launch_petfit_apps.R)
- **`launch_petfit_apps()`**: Parameter validation and app launching logic

## Test Data Strategy

### Realistic Mini-Dataset
The test suite uses a scaled-down version of real PET data rather than synthetic data:

- **Base Data**: Uses existing `test_tac_data.csv` from the package data folder
- **BIDS Structure**: Creates minimal but complete BIDS directory structure:
  - 2-3 subjects (sub-01, sub-02, sub-03)
  - 1-2 sessions per subject
  - Realistic PET metadata (injection data, frame timing)
  - FreeSurfer-style segmentation data
  - Participant demographics integration

### Configuration Testing
- **1TCM configurations**: Complete parameter sets for 1-compartment models
- **2TCM configurations**: Complete parameter sets for 2-compartment models
- **Blood data scenarios**: With and without blood input data
- **Processing variants**: Different delay fitting, weights, and subsetting options

## Running Tests

### Standard testthat Execution
```r
# Install package first
devtools::install()

# Run all tests
devtools::test()

# Or run tests directly
testthat::test_dir("tests/testthat")
```

### Alternative Test Runner
For environments where the package installation is problematic:
```bash
Rscript run_tests.R
```

## Test Philosophy

### Comprehensive Coverage
- **Happy path testing**: Standard usage scenarios
- **Edge case handling**: Empty data, missing files, invalid inputs
- **Error conditions**: Graceful failure and meaningful error messages
- **Integration testing**: Full workflows from data input to report output

### Model Focus
Tests concentrate on the **1TCM and 2TCM models** as these have complete parameter configurations, avoiding incomplete model implementations.

### Validation Patterns
- Parameter validation and bounds checking
- File I/O robustness (readr vs base R compatibility)
- BIDS compliance verification
- Cross-platform compatibility

## Key Testing Scenarios

### 1. Data Processing Workflows
- Region combination with volume weighting
- BIDS metadata integration
- Participant data merging
- TACs file format validation

### 2. Configuration Management
- JSON configuration loading/saving
- Parameter validation across different model types
- State persistence and restoration

### 3. Error Handling
- Missing file scenarios
- Corrupted data handling
- Invalid parameter combinations
- Directory permission issues

### 4. Integration Testing
- Full pipeline: region definition → modelling → reporting
- Docker deployment validation
- Multi-subject, multi-session processing

## Dependencies

### Core Testing
- `testthat` (>= 3.0.0): Test framework
- `here`: Path management for test fixtures

### Data Handling
- `tibble`, `dplyr`, `readr`: Data manipulation
- `jsonlite`: JSON configuration handling
- `stringr`: String processing

### Domain-Specific
- `kinfitr`: Core kinetic modeling functions (mocked where needed)

## Maintenance Notes

### Adding New Tests
1. Follow the `test-[filename].R` naming convention
2. Use the setup functions from `fixtures/setup.R`
3. Include comprehensive edge case testing
4. Test both success and failure scenarios

### Test Data Updates
- Test data is self-contained in `fixtures/`
- BIDS structures are created programmatically
- No external data dependencies

### Performance Considerations
- Tests create temporary directories that are automatically cleaned up
- Large file operations use minimal realistic datasets
- Mock functions used where appropriate to avoid external dependencies

## Quality Assurance

The test suite aims for:
- **>90% code coverage** across all exported functions
- **Cross-platform compatibility** (Linux, macOS, Windows)
- **Deterministic results** (no random elements without seeding)
- **Clean test environment** (proper setup/teardown)

This comprehensive test suite ensures reliability and maintainability of the petfit package across different usage scenarios and deployment environments.
