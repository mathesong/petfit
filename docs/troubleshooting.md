# Troubleshooting

## Data and file issues

PETFit consumes the **TAC** (`*_tacs.tsv`) and **morphometry** (`*_morph.tsv`) outputs of a preprocessing step that produces BIDS PET preprocessing derivatives — i.e. regional time-activity curves and their region volumes (e.g. from the `gtm` segmentation) written out in the BIDS derivatives layout. [PETPrep](https://petprep.readthedocs.io/) is one tool that produces these, but any preprocessing pipeline that writes BIDS-compliant `*_tacs.tsv` and `*_morph.tsv` files will work. The issues below usually trace back to how that preprocessing step was run.

### No TAC files found

**Symptom:** The region definition app shows no files.

**Cause:** TAC files are missing the `seg` or `label` BIDS entity in their filenames. PETFit filters out files that have neither.

**Fix:** Ensure your TAC filenames include a `seg-*` or `label-*` entity, e.g. `sub-01_seg-gtm_tacs.tsv`. Tools like PETPrep name their files this way by default (e.g. `seg-gtm`); if you are using another tool, confirm it writes the segmentation/label entity into the filename.

### TACs and morph file mismatch

**Symptom:** Regions are combined with equal weighting (volume = 1) instead of actual volumes.

**Cause:** No matching morph file was found. The `sub` and `seg`/`label` entities must match exactly (case-sensitive) between TAC and morph files.

**Fix:** Check that the morph file exists and has matching `sub` and `seg`/`label` values. PETFit will show a warning when falling back to equal weighting.

The TACs and morph files should come from the **same preprocessing run and the same segmentation** — a tool like PETPrep emits both together, so a missing or mismatched morph file usually means the preprocessing was only partially run, the morphometry output was not copied across, or the two files were generated from different segmentations. Re-running (or completing) the preprocessing stage that produces the `*_morph.tsv` alongside the TACs normally resolves it.


## Reference tissue issues

### Reference region not found in analysis data

**Symptom:** Error during reference TAC setup or model fitting.

**Cause:** The reference region specified in `ReferenceTAC.region` is not included in the data subsetting.

**Fix:** Make sure the Regions field in the Subsetting section includes your reference region. For example, if your reference region is "Cerebellum", then Regions must include "Cerebellum".

### Poor R1 estimates from MRTM1 / MRTM2

**Symptom:** MRTM1 or MRTM2 return implausible, unstable, or otherwise poor `R1` (relative delivery) values.

**Cause:** These models tend to estimate `BPND` more reliably than they do `R1`. Poor `R1` can also indicate that a `t*` value needs to be set: `R1` is only estimable when the tracer can be adequately described by one-tissue kinetics, so in the case of two-tissue kinetics a `t*` value should be used.

**Fix:** Treat `R1` from MRTM1/MRTM2 with some degree of caution and rely on them primarily for `BPND`. If the tracer follows two-tissue kinetics, set an appropriate `t*` value (see the `t*` finder report). If `R1` is itself a parameter of interest, prefer a model better suited to estimating it (e.g. SRTM / SRTM2).

## Blood data issues

Plasma input models need an arterial input function. PETFit reads processed `*_inputfunction.tsv` files, and can fall back to raw `*_blood.tsv` files from the BIDS dataset. Processed input functions are typically produced by [bloodstream](https://github.com/mathesong/bloodstream), which — like PETFit — is also a BIDS App, in this case for modelling blood and metabolite data.

### Noisy or unreliable blood data

**Symptom:** Plasma input models fit poorly, and are dominated by scatter in the input function.

**Cause:** The raw blood/plasma measurements may be noisy — so the input function passed to the kinetic model is itself unreliable.

**Fix:** Consider modelling the blood data with [bloodstream](https://github.com/mathesong/bloodstream) before running PETFit. As a BIDS App, it fits the blood, plasma-to-whole-blood ratio, and parent fraction with configurable models, producing smooth, denoised `*_inputfunction.tsv` files in BIDS format that PETFit can read directly. This usually gives more stable model fits than feeding raw blood samples in.

### PETFit cannot find the blood / input function files

**Symptom:** The plasma input app or pipeline reports no blood data, or skips delay fitting because no input function is available.

**Cause:** PETFit is not looking in the right place for the `*_inputfunction.tsv` (or raw `*_blood.tsv`) files.

**Fix:** Check the following:

- **`blood_dir` was not supplied.** If your input functions live outside the BIDS raw data (for example in a bloodstream derivatives folder), you must point PETFit at them with `blood_dir` (or the container's `-v /path:/data/blood_dir` mount). Forgetting this is the most common cause.
- **`blood_dir` points too high up.** bloodstream writes its outputs into per-analysis subfolders (e.g. `derivatives/bloodstream/Primary_Analysis/`). Point `blood_dir` at the specific analysis folder — e.g. `.../derivatives/bloodstream/Primary_Analysis` — rather than the top-level `bloodstream/` directory, so PETFit picks up the intended set of `*_inputfunction.tsv` files.
- **The files are named differently.** PETFit matches `*_inputfunction.tsv` (processed) and `*_blood.tsv` (raw). Confirm the filenames follow these BIDS conventions and that the `sub`/`ses` entities match your TAC data.

## Model fitting issues

### Model fails to converge

**Symptom:** Model fitting produces `NA` values or error messages about convergence.

**Possible causes:**
- Parameter bounds too narrow or too wide
- Poor start values
- Noisy or unusual TAC data

**Fix:** Try adjusting parameter bounds, start values or weighting in the model configuration. For compartmental models, ensure bounds are physiologically reasonable. Check the TAC data in the interactive tab to verify it looks sensible before fitting.

### Unexpected parameter estimates

**Symptom:** Fitted parameters are at their boundary values or seem implausible.

**Cause:** The optimiser may be hitting parameter bounds, or the data may not support the chosen model.

**Fix:** Review the model fit plots in the HTML reports. Consider whether a simpler model might be more appropriate (e.g. 1TCM instead of 2TCM). Widen parameter bounds if estimates are consistently hitting limits. 
Or consider shrinking parameter bounds if the estimated parameters are implausible.
Another strategy is using multiple starting points when fitting nonlinear models to ensure that the model is less likely to land in local minima.

### Extremely high VT values

**Symptom:** A plasma input model returns implausibly high `VT` (total distribution volume) — far larger than expected for the tracer and region.

**Cause:** In the 2TCM this is most often caused by `k4` being driven too close to zero during fitting. Because `VT` scales with `k3/k4`, a vanishingly small `k4` inflates `VT` enormously, even when the fit to the TAC itself still looks acceptable.

**Fix:**

- Set a slightly **higher lower bound on `k4`** so the optimiser cannot push it down to near-zero. A small positive floor often stabilises `VT` dramatically.
- Use the **multiple starting points** functionality so the nonlinear fit is less likely to settle in this degenerate local minimum.
- Consider a **linearised model** (Logan or MA1). These estimate `VT` directly and tend to be more robust to this failure mode than the compartmental 2TCM.

### Logan / refLogan give lower estimates than the nonlinear models

**Symptom:** `VT` from the Logan plot (or `BPND` from refLogan) comes out noticeably lower than the corresponding nonlinear model (2TCM, SRTM), and you are wondering why there is a bias.

**Cause:** This is typically caused by **not setting an appropriate `t*` (t-star)** value. `t*` is the point on the curve after which the transformed values become linear; the graphical models fit a straight line only to the points from `t*` onwards. If `t*` is left too early, the still-curved early points are included in the linear fit and bias the slope — and hence `VT` / `BPND` — downward.

**Fix:** Choose `t*` carefully for each linearised model rather than leaving it at a default. Use the `t*` finder report to identify the time at which the transformed plot becomes linear, and confirm the chosen `t*` excludes the early, curved portion. Once `t*` is set appropriately, the graphical and nonlinear estimates should agree much more closely.

### Unstable or noisy binding estimates

**Symptom:** Binding outcomes (`VT`, `BPND`, `k2a`, etc.) vary wildly between subjects, regions, or repeated runs — in either plasma input or reference tissue models.

**Cause:** Nonlinear compartmental and reference tissue models (2TCM, SRTM, and similar) can be sensitive to noise, starting values, and local minima.

**Fix:** Switching to a **linearised model** often helps — Logan or MA1 for plasma input, and refLogan, MRTM1, or MRTM2 for reference tissue. The linearised (graphical and multilinear) models are generally more stable and less sensitive to noise and starting values than their nonlinear counterparts, at the cost of some bias. Adjusting the [weighting](usage/modelling-plasma.md#2-weights) and using multiple starting points for nonlinear fits can also improve stability.

### Nonlinear models unstable but linearised models stable

**Symptom:** The compartmental models (especially the 2TCM, and to a lesser degree the 1TCM) give unstable or implausible estimates, while the linearised models (Logan, MA1) on the *same* data are much more stable.

**Cause:** When the nonlinear models are uniquely unstable, a common underlying culprit is a **poorly estimated blood–tissue delay**. A misaligned input function distorts the early frames that the compartmental models rely on, whereas the linearised models lean more on later time points and are less affected.

**Fix:** Inspect the **delay fit reports extra carefully** and confirm the estimated delay looks sensible for each measurement. If the delay is unreliable, try a different delay-estimation method (e.g. fitting from multiple regions and taking the median), or estimate it from a small set of well-behaved regions using an [ancillary analysis](usage/folder-structure.md#ancillary-analysis-folders).

### Unreliable delay or k2prime estimates

**Symptom:** Delay fitting or `k2prime` estimation produces noisy or inconsistent values across regions, which then degrade the downstream model fits.

**Cause:** Estimating the delay or `k2prime` from noisy or atypical regions yields unreliable values, which propagate into every model that depends on them.

**Fix:** Estimate these parameters from a small set of clean, well-behaved regions using an **ancillary analysis folder**, then inherit the value into your primary analysis across all regions. This is exactly what ancillary folders are designed for — see [ancillary analysis folders](usage/folder-structure.md#ancillary-analysis-folders) for the delay-inheritance and k2prime-inheritance workflows.

## Ancillary analysis issues

### Ancillary folder not found

**Symptom:** Error message about missing ancillary analysis folder.

**Cause:** The `ancillary_analysis_folder` must be a sibling folder name (e.g. `"Ancillary_Analysis"`), not a full path. It must already exist under `derivatives/petfit/`.

**Fix:** Ensure the ancillary analysis has been run first and the folder exists. Pass only the folder name, not a path.

### Missing delay or k2prime files in ancillary folder

**Symptom:** Pipeline cannot find expected parameter files in the ancillary folder.

**Cause:** The ancillary analysis did not complete the relevant step (delay fitting or model fitting), or the files are named differently than expected.

**Fix:** Check that the ancillary analysis ran successfully by reviewing its reports. Delay files should match `*_desc-delayfit_kinpar.tsv` and model files should match `*_desc-model{N}_kinpar.tsv`.

## Performance

### Processing is too slow

**Symptom:** Fitting takes a long time, particularly on large datasets or when using the slower delay-estimation methods (e.g. 2TCM from multiple regions).

**Cause:** By default PETFit runs on a single core.

**Fix:** Increase the number of CPU cores with the `--cores` flag (Docker / Apptainer) or the `cores` argument (R). The computationally heavy steps — delay fitting and model fitting — are run in parallel across PET measurements, so allocating more cores can speed things up a great deal:

```bash
petfit-docker /path/to/bids /path/to/derivatives participant \
  --app modelling_plasma --automatic --cores 8
```

```r
petfit_auto(app = "modelling_plasma", derivatives_dir = "/path/to/derivatives",
            blood_dir = "/path/to/blood", cores = 8)
```

On HPC, match `--cores` to the number of cores requested in your job script.

## Docker issues

### Output files owned by root

On Linux, Docker containers run as root by default. Add `--user $(id -u):$(id -g)` to your `docker run` command. See [Docker usage](containers/docker.md#file-permissions-on-linux).

### Port already in use

Map to a different host port, e.g. `-p 8080:3838` instead of `-p 3838:3838`. The port you browse to is the host (left-hand) side. See [Port configuration](containers/docker.md#port-configuration).

## Apptainer / HPC issues

### Port already in use

Apptainer shares the host network, so a busy port 3838 on the node would clash. The container automatically binds the next free port (3838–3858) and prints the address to use; forward that port with SSH (`ssh -L <port>:localhost:<port>`). To pick the starting port yourself, pass `--env SHINY_PORT=<port>`. See [Apptainer usage](containers/apptainer.md#port-already-in-use).

### No internet access on compute nodes

Build the container on a login node, then transfer the `.sif` file to your project space.

### Home directory size limits

Set `APPTAINER_CACHEDIR` to a scratch directory:

```bash
export APPTAINER_CACHEDIR=/scratch/$USER/apptainer_cache
```

### Finding the Apptainer module

Common module names:

```bash
module load apptainer
module load singularity
module load singularity-ce
```

See [Apptainer troubleshooting](containers/apptainer.md#troubleshooting) for more details.
