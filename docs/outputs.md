# Outputs

PETFit produces output files following BIDS derivatives conventions. All outputs go into the `derivatives/petfit/` directory.

## Directory structure

```
bids_directory/                           # Raw BIDS data
├── participants.tsv
├── code/petfit/
│   └── petfit_regions.tsv                # Region definitions
└── sub-*/ses-*/pet/

derivatives/                              # Processed outputs
└── petfit/                               # PETFit outputs
    ├── petfit_regions.tsv                # Region definitions (copy)
    ├── desc-combinedregions_tacs.tsv     # Combined TACs (all regions)
    └── Analysis_Name/                    # Analysis-specific folder
        ├── desc-petfitoptions_config.json
        ├── sub-01/
        │   ├── sub-01_desc-combinedregions_tacs.tsv
        │   ├── sub-01_desc-weights_weights.tsv
        │   └── sub-01_model-2TCM_desc-model1_kinpar.tsv
        ├── sub-02/
        │   └── ...
        └── reports/
            ├── data_definition_report.html
            ├── weights_report.html
            ├── delay_report.html
            ├── model1_report.html
            └── ...
```

## Region definition outputs

These files are shared across all analyses.

### petfit_regions.tsv

The region definition file listing all combined regions and their constituents. This file can be transferred between studies that use the same preprocessing pipelines and segmentations.

### desc-combinedregions_tacs.tsv

The combined TACs file containing all PET measurements and regions with BIDS metadata.

## Modelling outputs

These files are created within analysis-specific subfolders.

### Individual TAC files

One file per PET measurement, named `{pet_id}_desc-combinedregions_tacs.tsv`.


### Weight files

One file per PET measurement, named `{pet_id}_desc-weights_weights.tsv`. Contains per-frame weights for each region.

### Kinetic parameter files

One file per PET measurement per model, named `{pet_id}_model-{MODEL}_desc-{MODEL_NUMBER}_kinpar.tsv`. 
Contains the fitted kinetic parameters for each region._
There is also a global kinetic parameter file for all subjects in the analysis created in the main analysis folder, named `model-{MODEL}_desc-{MODEL_NUMBER}_kinpar.tsv`.

For the [nested models](models.md#nested-models), `{MODEL}` is `nested2TCM` or `nestedSRTM`; the files have the same shape as for any other model, one row per region, with the shared parameters repeated across the regions of each measurement.

### Configuration file

`desc-petfitoptions_config.json` stores all analysis settings. This file is generated automatically by the interactive apps and read by the automatic pipeline.

### HTML reports

Generated in the `reports/` subdirectory. See [Parameterised reports](usage/reports.md) for details.

## BIDS metadata integration

PETFit automatically integrates data from your BIDS dataset into the combined TACs:

- **Participant data** — Reads `participants.tsv` and `participants.json` from the BIDS root. Maps `participant_id` format (`sub-01` to `01`) and extracts body weight for SUV calculations.
- **PET metadata** — Extracts `InjectedRadioactivity` from PET JSON sidecars and converts units to kBq.
