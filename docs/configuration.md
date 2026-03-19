# Configuration files

PETFit uses JSON configuration files to store all analysis settings. These files are created automatically by the interactive apps and read by the automatic pipeline.

## File location

Configuration files are saved as `desc-petfitoptions_config.json` in the analysis folder:

```
derivatives/petfit/<analysis_folder>/desc-petfitoptions_config.json
```

## Configuration structure

### Plasma input example

```json
{
  "modelling_configuration_type": "plasma input",
  "Subsetting": {
    "sub": "01;02",
    "ses": "",
    "trc": "",
    "rec": "",
    "task": "",
    "run": "",
    "Regions": ""
  },
  "Weights": {
    "region_type": "mean_combined",
    "region": "",
    "external_tacs": "",
    "radioisotope": "C11",
    "halflife": "",
    "method": "2",
    "formula": "sqrt(frame_dur * tac_uncor)",
    "minweight": 0.25
  },
  "FitDelay": {
    "blood_source": "1",
    "model": "1tcm_singletac",
    "time_window": 5,
    "regions": "",
    "multiple_regions": "",
    "vB_value": 0.05,
    "fit_vB": true,
    "use_weights": true,
    "inpshift_lower": -0.5,
    "inpshift_upper": 0.5
  },
  "Models": {
    "Model1": {
      "type": "2TCM",
      "K1_lower": 0.001, "K1_upper": 1, "K1_start": 0.1,
      "k2_lower": 0.001, "k2_upper": 1, "k2_start": 0.1,
      "k3_lower": 0.001, "k3_upper": 1, "k3_start": 0.1,
      "k4_lower": 0.001, "k4_upper": 1, "k4_start": 0.1,
      "vB_lower": 0, "vB_upper": 0.1, "vB_start": 0.05,
      "fit_vB": true,
      "use_weights": true
    },
    "Model2": { "type": "No Model" },
    "Model3": { "type": "No Model" }
  }
}
```

### Reference tissue example

```json
{
  "modelling_configuration_type": "reference tissue",
  "Subsetting": {
    "sub": "01;02",
    "ses": "",
    "trc": "",
    "rec": "",
    "task": "",
    "run": "",
    "Regions": "Frontal;Temporal;Cerebellum"
  },
  "Weights": {
    "region_type": "mean_combined",
    "region": "",
    "external_tacs": "",
    "radioisotope": "C11",
    "halflife": "",
    "method": "2",
    "formula": "sqrt(frame_dur * tac_uncor)",
    "minweight": 0.25
  },
  "ReferenceTAC": {
    "region": "Cerebellum",
    "method": "raw",
    "noise_approximation": false,
    "weights_method": "same",
    "custom_formula": ""
  },
  "Models": {
    "Model1": {
      "type": "SRTM",
      "R1_lower": 0, "R1_upper": 10, "R1_start": 1,
      "k2_lower": 0, "k2_upper": 1, "k2_start": 0.1,
      "k2a_lower": 0, "k2a_upper": 1, "k2a_start": 0.1,
      "use_weights": true
    },
    "Model2": { "type": "No Model" },
    "Model3": { "type": "No Model" }
  }
}
```

## Field reference

### Subsetting

| Field | Description |
|-------|-------------|
| `sub` | Subject identifiers, semicolon-separated (e.g. `"01;02;03"`) |
| `ses` | Session filter |
| `trc` | Tracer filter |
| `rec` | Reconstruction filter |
| `task` | Task filter |
| `run` | Run filter |
| `Regions` | Brain regions to include, semicolon-separated |

Empty strings mean "include all".

### Weights

| Field | Description |
|-------|-------------|
| `region_type` | `"mean_combined"`, `"single"`, or `"external"` |
| `region` | Region name (when `region_type` is `"single"`) |
| `external_tacs` | External segmentation name (when `region_type` is `"external"`) |
| `radioisotope` | `"C11"`, `"F18"`, `"O15"`, or `"Other"` |
| `halflife` | Custom half-life in minutes (when `radioisotope` is `"Other"`) |
| `method` | Weighting method number or `"custom"` |
| `formula` | The weighting formula |
| `minweight` | Minimum weight floor (default: 0.25) |

### FitDelay (plasma input only)

| Field | Description |
|-------|-------------|
| `blood_source` | Blood data source identifier |
| `model` | Delay estimation approach |
| `time_window` | Minutes of data for fitting (default: 5) |
| `regions` | Region selection |
| `multiple_regions` | Semicolon-separated regions for multi-region approaches |
| `vB_value` | Blood volume fraction value |
| `fit_vB` | Whether to fit vB |
| `use_weights` | Whether to use weights during delay fitting |
| `inpshift_lower` | Lower limit for blood time shift search (minutes) |
| `inpshift_upper` | Upper limit for blood time shift search (minutes) |

### ReferenceTAC (reference tissue only)

| Field | Description |
|-------|-------------|
| `region` | Reference region name |
| `method` | `"raw"`, `"feng_1tc"`, or `"spline"` |
| `noise_approximation` | Whether to estimate noise in reference region |
| `weights_method` | `"same"` or independent method |
| `custom_formula` | Custom weights formula for reference TAC |

### Models

Each model slot (`Model1`, `Model2`, `Model3`) contains:

| Field | Description |
|-------|-------------|
| `type` | Model name (e.g. `"2TCM"`, `"SRTM"`) or `"No Model"` |
| `*_lower`, `*_upper`, `*_start` | Parameter bounds and start values |
| `fit_vB` | Whether to fit blood volume fraction |
| `use_weights` | Whether to use weights during fitting |

The specific parameters depend on the model type. See [Supported models](models.md) for the parameters of each model.

## State persistence

The interactive apps save the configuration file whenever you perform an action (run a step, change settings, etc.). When you reopen the app and point it to the same analysis folder, all settings are automatically restored.

If a configuration file is corrupted or incompatible, the app shows an error message and falls back to defaults.

## Backward compatibility

New features are added with safe defaults so that existing configuration files continue to work. The apps use null coalescing (`%||%`) when reading config properties, falling back to sensible defaults for any missing fields.
