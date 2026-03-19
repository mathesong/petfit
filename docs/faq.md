# FAQ and troubleshooting

## General questions

### What is PETFit?

PETFit is a BIDS App for fitting kinetic models to PET time activity curve data. It provides interactive Shiny web apps for configuring analyses and an automatic pipeline for batch processing.

### What is kinfitr?

[kinfitr](https://github.com/mathesong/kinfitr) is the R package that performs the actual kinetic model fitting. PETFit provides the pipeline infrastructure, interactive configuration, and reporting on top of kinfitr.

### What BIDS data do I need?

You need PET data preprocessed according to the [PET Preprocessing Derivatives BIDS specification](https://bids-specification.readthedocs.io/). This typically means TAC files and morphometry files from a preprocessing pipeline such as [PETPrep](https://petprep.readthedocs.io/). The TAC files must have `seg` or `label` BIDS entities in their filenames.

### Can I use PETFit without Docker?

Yes. You can install PETFit as an R package and use it directly. Docker and Singularity are provided for convenience but are not required.

### What preprocessing pipeline should I use?

PETFit works with any pipeline that produces TAC and morphometry files following the PET Preprocessing Derivatives BIDS specification. [PETPrep](https://petprep.readthedocs.io/) is one such pipeline.

## Common issues

### No TAC files found

**Symptom:** The region definition app shows no files.

**Cause:** TAC files are missing the `seg` or `label` BIDS entity in their filenames. PETFit filters out files that have neither.

**Fix:** Ensure your TAC filenames include a `seg-*` or `label-*` entity, e.g. `sub-01_seg-gtm_tacs.tsv`.

### TACs and morph file mismatch

**Symptom:** Regions are combined with equal weighting (volume = 1) instead of actual volumes.

**Cause:** No matching morph file was found. The `sub` and `seg`/`label` entities must match exactly (case-sensitive) between TAC and morph files.

**Fix:** Check that the morph file exists and has matching `sub` and `seg`/`label` values. PETFit will show a warning when falling back to equal weighting.

### Combined TACs not generated

**Symptom:** Error during region combination.

**Cause:** Likely a column name issue. If you see errors about columns like `volume.mm3`, this is a file reading issue — `readr::read_tsv()` preserves hyphens in column names (e.g. `volume-mm3`), while base R `read.table()` converts them to dots.

**Fix:** This should not occur with the current version of PETFit. If it does, please [report the issue](https://github.com/mathesong/petfit/issues).

### Subject IDs appear as numbers instead of strings

**Symptom:** Subject IDs like `01` are displayed as `1`.

**Cause:** This happens when files are read with base R functions that convert character columns to numeric.

**Fix:** PETFit uses `readr::read_tsv()` which preserves character types. If you see this issue, please report it.

### Report generation fails

**Symptom:** Error when generating HTML reports.

**Possible causes:**
- Missing template files in `inst/rmd/`
- Missing R dependencies (`rmarkdown`, `knitr`, `plotly`)
- Corrupt or incomplete data in the analysis folder

**Fix:** Check that all dependencies are installed. Try rendering the report manually:

```r
rmarkdown::render(
  system.file("rmd", "2tcm_report.Rmd", package = "petfit"),
  params = list(analysis_folder = "/path/to/analysis")
)
```

### Reference region not found in analysis data

**Symptom:** Error during reference TAC setup or model fitting.

**Cause:** The reference region specified in `ReferenceTAC.region` is not included in the data subsetting.

**Fix:** Make sure the Regions field in the Subsetting section includes your reference region. For example, if your reference region is "Cerebellum", then Regions must include "Cerebellum".

### BIDS entity ordering in petfit_regions.tsv

**Symptom:** Region definition fails to match files.

**Cause:** The description column in `petfit_regions.tsv` must use the correct BIDS entity ordering. PETFit gives priority to `seg`/`label`, then sorts remaining keys alphabetically.

**Fix:** Use `seg-gtm_desc-preproc` rather than `desc-preproc_seg-gtm`.

## Docker issues

### Output files owned by root

On Linux, Docker containers run as root by default. Add `--user $(id -u):$(id -g)` to your `docker run` command. See [Docker usage](containers/docker.md#file-permissions-on-linux).

### Port already in use

Map to a different host port: `-p 8080:3838` instead of `-p 3838:3838`.

## Singularity / HPC issues

### No internet access on compute nodes

Build the container on a login node, then transfer the `.sif` file to your project space.

### Home directory size limits

Set `SINGULARITY_CACHEDIR` to a scratch directory:

```bash
export SINGULARITY_CACHEDIR=/scratch/$USER/singularity_cache
```

### Finding the Singularity module

Common module names:

```bash
module load singularity
module load apptainer
module load singularity-ce
```

See [Singularity troubleshooting](containers/singularity.md#troubleshooting) for more details.
