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
        │   └── sub-01_model-2TCM_kinpar.tsv
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

**Column order:**

| Column | Description |
|--------|-------------|
| `sub` | Subject identifier |
| `ses` | Session |
| `trc` | Tracer |
| `rec` | Reconstruction |
| `task` | Task |
| `run` | Run |
| `segmentation` | Full preprocessing pipeline identifier (e.g. `petprep: seg-gtm_pvc-AGTM`) |
| `pet` | PET measurement identifier (only BIDS attributes that vary across the dataset) |
| `InjectedRadioactivity` | Injected radioactivity in kBq |
| `bodyweight` | Body weight in kg (for SUV calculations) |
| *(participant columns)* | Optional columns from `participants.tsv` (e.g. age, sex) |
| `region` | Combined region name |
| `volume_mm3` | Total region volume in mm³ |
| `frame_start` | Frame start time |
| `frame_end` | Frame end time |
| `frame_dur` | Frame duration |
| `frame_mid` | Frame midpoint |
| `TAC` | Volume-weighted average TAC |
| `seg_meanTAC` | Volume-weighted mean TAC for the entire segmentation |

All BIDS identifiers are preserved as character types (e.g. subject `"01"` stays as `"01"`, not numeric `1`).

## Modelling outputs

These files are created within analysis-specific subfolders.

### Individual TAC files

One file per PET measurement, named `{pet_id}_desc-combinedregions_tacs.tsv`.

**Column order:**

| Column | Description |
|--------|-------------|
| `pet` | PET measurement identifier |
| `region` | Region name |
| `volume_mm3` | Region volume in mm³ |
| `InjectedRadioactivity` | Injected radioactivity in kBq |
| `bodyweight` | Body weight in kg |
| `frame_start` | Frame start time |
| `frame_end` | Frame end time |
| `frame_dur` | Frame duration |
| `frame_mid` | Frame midpoint |
| `TAC` | TAC value |

### Weight files

One file per PET measurement, named `{pet_id}_desc-weights_weights.tsv`. Contains per-frame weights for each region.

### Kinetic parameter files

One file per PET measurement per model, named `{pet_id}_model-{MODEL}_kinpar.tsv`. Contains the fitted kinetic parameters for each region.

### Configuration file

`desc-petfitoptions_config.json` stores all analysis settings. This file is generated automatically by the interactive apps and read by the automatic pipeline.

### HTML reports

Generated in the `reports/` subdirectory. See [Parameterised reports](usage/reports.md) for details.

## BIDS metadata integration

PETFit automatically integrates data from your BIDS dataset into the combined TACs:

- **Participant data** — Reads `participants.tsv` and `participants.json` from the BIDS root. Maps `participant_id` format (`sub-01` to `01`) and extracts body weight for SUV calculations.
- **PET metadata** — Extracts `InjectedRadioactivity` from PET JSON sidecars and converts units to kBq.
