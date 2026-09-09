# Region definition

The region definition app combines individual brain regions from PET preprocessing derivatives into analysis-ready TACs. This is always the first step in a PETFit workflow.

## How it works

### The petfit_regions.tsv file

Region definitions are stored in a TSV file called `petfit_regions.tsv`. This file can live in either:

- `derivatives/petfit/petfit_regions.tsv`
- `bids_dir/code/petfit/petfit_regions.tsv`

Each row defines a combined region by listing its constituent parts. The interactive app helps you create this file, or you can write it manually.

Because this file is independent of the data, you can transfer it between studies that use the same preprocessing pipelines and segmentations. 
So groups who have typical combined region definitions (e.g. Frontal Cortex) can share `petfit_regions.tsv` files between studies provided they extract the same segmentations using BIDS preprocessing tools (e.g. the `gtm` segmentation from `PETPrep`).


### BIDS entity matching

PETFit uses BIDS entities to match TAC files with their corresponding morphometry (volume) files.

**Required entities:**

- **sub** — Subject identifier. Must match exactly between TACs and morph files.
- **seg** or **label** — Segmentation type (e.g. `seg-gtm`) or region label (e.g. `label-semiovale`). Must match exactly. Files must have one or the other.

**Hierarchical entities:**

- **ses** — Session identifier. If the morph file specifies a session, the TACs file must have the same session. If the morph file has no session, it matches all sessions for that subject.
- **run** — Run identifier. Same hierarchical logic as session.

This enables one-to-many relationships. For example, a single morph file without a session entity can serve all sessions for a subject:

```
sub-P3_ses-01_run-1_seg-gtm_tacs.tsv → sub-P3_seg-gtm_morph.tsv
sub-P3_ses-01_run-2_seg-gtm_tacs.tsv → sub-P3_seg-gtm_morph.tsv
sub-P3_ses-02_run-1_seg-gtm_tacs.tsv → sub-P3_seg-gtm_morph.tsv
```


### Merging runs

Some tracers are acquired as two scanning occasions from a single injection —
`run-01` and `run-02`, or `run-early` and `run-late` — with the subject out of
the scanner in between. Those runs are two windows onto the same bloodstream and
the same kinetics, and should be fitted together as one measurement. Other
datasets use runs for genuinely separate injections, which must stay apart.

PETFit cannot tell these apart from the filenames, so it is a choice you make
here. **Merging is on by default**, because the single-injection case is the more
common one. Untick **Merge runs of the same measurement** in the app, pass
`--no-merge-runs` to the wrapper, `--no_merge_runs` to the container, or
`merge_runs = FALSE` in R, for datasets where each run is its own injection.

The app shows the option only when at least one measurement actually has more
than one run. A dataset with no runs, or labelled `run-01` throughout, has
nothing to merge, so the control is left out rather than offered inertly, and
the run is recorded as unmerged — which it is.

When runs are merged:

- The frames of all of a measurement's runs become one measurement, and **the
  `run` entity is dropped from the outputs**. `sub-01_ses-test_run-01` and
  `sub-01_ses-test_run-02` become `sub-01_ses-test`, and that is the name every
  file downstream is written under.
- `run` is dropped from the measurements which were **actually merged**, and
  from those alone — a measurement with a single run keeps it, whatever the
  rest of the cohort did. This is the rule `bloodstream` uses, so the two tools
  name the same measurement the same way, and it keeps each measurement's
  identity built from its own entities rather than from what other subjects
  happened to have.
- The runs are placed on one clock by the difference between their `TimeZero`
  times — the same rule `bloodstream` applies to the blood samples of those
  runs, so a study which merges in one tool merges in the other. Runs sharing a
  `TimeZero` are already on one clock and are not moved; runs which each start
  again from zero are shifted onto the first run's.
- `TimeZero` lives in the raw `_pet.json`, so this needs a `bids_dir`. The
  preprocessing pipelines do not generally copy it into their `_tacs.json`, so a
  run given only a derivatives directory usually has none, and the frame times
  are then taken as already sharing a time zero. Either way the result is
  checked: if the frames of two runs still **overlap**, region definition stops
  rather than pooling rows into a TAC that doubles back on itself — telling you
  to supply `bids_dir` where no clock was available, or that the runs are not
  consecutive scans where one was.
- Blood data is pooled to match. When PETFit builds input functions from the raw
  BIDS `_blood.tsv` files, a merged measurement's runs give one
  `_inputfunction.tsv` spanning both, with the unsampled interval between them
  bridged by linear interpolation. If you supply already-processed input
  functions (from `bloodstream`, via `blood_dir` or the analysis folder), they
  must already be merged: a per-run input function against merged TACs is an
  error, not a silent pairing with one run's blood curve. The reverse is an
  error too — merging runs in `bloodstream` (its default) while keeping them
  apart here would pair one merged curve with every run of a measurement.
- Since there is no `run` left, **subsetting by run is no longer possible**; the
  subsetting error says so when you try.
- `desc-combinedregions_tacs.json` records `MergedRuns` — what actually
  happened, not what was asked for — so an empty `run` column can be told apart
  from a dataset that never had runs.

Runs which disagree about something a single injection fixes — the injected
radioactivity, the body weight, a region's segmented volume — are merged with a
warning, using the earliest run's value. That disagreement usually means the runs
are separate injections and should not have been merged.

### Volume-weighted combination

When combining regions, PETFit computes a volume-weighted average of the constituent TACs. Region volumes are read from the morph files.

If no matching morph file is found for a TAC, PETFit falls back to equal weighting (volume = 1 for all regions) and displays a warning.

### Segmentation mean TAC

During region combination, PETFit also calculates a `seg_meanTAC` column — a volume-weighted mean TAC across *all* regions within each segmentation. This is useful for weights calculation later in the pipeline, as it provides a representative whole-brain TAC without needing to access the original BIDS directory.

## Running region definition

`````{tab-set}

````{tab-item} Docker
```bash
# Interactive
petfit-docker /path/to/your/bids /path/to/your/derivatives participant \
  --app regiondef
# Then open http://localhost:3838

# Automatic
petfit-docker /path/to/your/bids /path/to/your/derivatives participant \
  --app regiondef --automatic

# Keep each run as a separate measurement
petfit-docker /path/to/your/bids /path/to/your/derivatives participant \
  --app regiondef --automatic --no-merge-runs
```

Install the wrapper with `pip install petfit-docker`; see the
[Docker guide](../containers/docker.md) for the equivalent raw `docker run` commands.
````

````{tab-item} Apptainer
```bash
# Interactive
apptainer run \
  --bind /path/to/your/bids:/data/bids_dir \
  --bind /path/to/your/derivatives:/data/derivatives_dir \
  petfit_latest.sif \
  --func regiondef
# Then open http://localhost:3838

# Automatic
apptainer run \
  --bind /path/to/your/derivatives:/data/derivatives_dir \
  petfit_latest.sif \
  --func regiondef \
  --mode automatic

# Keep each run as a separate measurement
apptainer run \
  --bind /path/to/your/derivatives:/data/derivatives_dir \
  petfit_latest.sif \
  --func regiondef \
  --mode automatic \
  --no_merge_runs
```
````

````{tab-item} R
```r
library(petfit)

# Interactive
petfit_interactive(
  app = "regiondef",
  derivatives_dir = "/path/to/derivatives"
)

# Automatic
petfit_auto(
  app = "regiondef",
  derivatives_dir = "/path/to/derivatives"
)

# Keep each run as a separate measurement
petfit_auto(
  app = "regiondef",
  derivatives_dir = "/path/to/derivatives",
  merge_runs = FALSE
)
```
````

`````

## Outputs

Region definition produces:

- **`petfit_regions.tsv`** — The region definition file listing all combined regions and their constituents.
- **`desc-combinedregions_tacs.tsv`** — The combined TACs file with all BIDS metadata, region volumes, frame timing, and the `seg_meanTAC` column. Its `run` column is empty when the runs were merged, and `desc-combinedregions_tacs.json` records that as `MergedRuns`.

Both files are written to the `derivatives/petfit/` directory and are shared across all subsequent analyses.
