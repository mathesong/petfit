# Region definition

The region definition app combines individual brain regions from PET preprocessing derivatives into analysis-ready TACs. This is always the first step in a PETFit workflow.

## Launching the app

`````{tab-set}

````{tab-item} R
```r
library(petfit)

# Interactive
launch_petfit_apps(
  app = "regiondef",
  derivatives_dir = "/path/to/derivatives"
)

# Automatic
petfit_regiondef_auto(
  derivatives_dir = "/path/to/derivatives"
)
```
````

````{tab-item} Docker
```bash
# Interactive
docker run -it --rm \
  -v /path/to/your/bids:/data/bids_dir:ro \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  -p 3838:3838 \
  mathesong/petfit:latest \
  --func regiondef

# Automatic
docker run --rm \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  mathesong/petfit:latest \
  --func regiondef \
  --mode automatic
```
````

`````

## The petfit_regions.tsv file

Region definitions are stored in a TSV file called `petfit_regions.tsv`. This file can live in either:

- `derivatives/petfit/petfit_regions.tsv`
- `bids_dir/code/petfit/petfit_regions.tsv`

Each row defines a combined region by listing its constituent parts. The interactive app helps you create this file, or you can write it manually.

Because this file is independent of the data, you can transfer it between studies that use the same preprocessing pipelines and segmentations.

## BIDS entity matching

PETFit uses BIDS entities to match TAC files with their corresponding morphometry (volume) files.

### Required entities

- **sub** — Subject identifier. Must match exactly between TACs and morph files.
- **seg** or **label** — Segmentation type (e.g. `seg-gtm`) or region label (e.g. `label-semiovale`). Must match exactly. Files must have one or the other.

### Hierarchical entities

- **ses** — Session identifier. If the morph file specifies a session, the TACs file must have the same session. If the morph file has no session, it matches all sessions for that subject.
- **run** — Run identifier. Same hierarchical logic as session.

This enables one-to-many relationships. For example, a single morph file without a session entity can serve all sessions for a subject:

```
sub-P3_ses-01_run-1_seg-gtm_tacs.tsv → sub-P3_seg-gtm_morph.tsv
sub-P3_ses-01_run-2_seg-gtm_tacs.tsv → sub-P3_seg-gtm_morph.tsv
sub-P3_ses-02_run-1_seg-gtm_tacs.tsv → sub-P3_seg-gtm_morph.tsv
```

### Ignored entities

The following entities are shown in the UI but not used for matching: `pvc` (partial volume correction), `desc`, `rec`, `task`.

## Volume-weighted combination

When combining regions, PETFit computes a volume-weighted average of the constituent TACs. Region volumes are read from the morph files.

If no matching morph file is found for a TAC, PETFit falls back to equal weighting (volume = 1 for all regions) and displays a warning.

## Segmentation mean TAC

During region combination, PETFit also calculates a `seg_meanTAC` column — a volume-weighted mean TAC across *all* regions within each segmentation. This is useful for weights calculation later in the pipeline, as it provides a representative whole-brain TAC without needing to access the original BIDS directory.

## Outputs

Region definition produces:

- **`petfit_regions.tsv`** — The region definition file listing all combined regions and their constituents.
- **`desc-combinedregions_tacs.tsv`** — The combined TACs file with all BIDS metadata, region volumes, frame timing, and the `seg_meanTAC` column.

Both files are written to the `derivatives/petfit/` directory and are shared across all subsequent analyses.
