# Docker

For a quick introduction, see the [Quick start](../quickstart.md). This page covers advanced options and detailed reference.

## Getting the image

```bash
# Pull pre-built image
docker pull mathesong/petfit:latest

# Or build from source
git clone https://github.com/mathesong/petfit.git
cd petfit
docker build -f docker/Dockerfile -t mathesong/petfit:latest .
```

## Docker wrapper

PETFit also includes a lightweight Python wrapper, `petfit-docker`, inspired by
the PETPrep Docker wrapper (petprep-docker). It accepts a BIDS-App-like command line, maps host
directories into the container, checks whether the image exists locally, and then
runs the PETFit Docker image.
Interactive Shiny mode is the default; use `--automatic` or `--mode automatic`
to run a non-interactive pipeline.

Install it from PyPI:

```bash
pip install petfit-docker
```

Run `petfit-docker --help` to see all available options, including descriptions
of each app, the execution modes, and the analysis folder:

```bash
petfit-docker --help
```

Launch the default region definition app:

```bash
petfit-docker /path/to/your/bids /path/to/your/derivatives/petfit participant
```

The wrapper follows the BIDS App positional argument convention:

```text
petfit-docker <bids_dir> <output_dir> participant
```

Launch region definition:

```bash
petfit-docker /path/to/your/bids /path/to/your/derivatives participant \
  --app regiondef
```

The positional `output_dir` may be the derivatives root or the final PETFit
output folder. For example, `/path/to/derivatives` and
`/path/to/derivatives/petfit` both map to the container's derivatives root when
using the default `--petfit-output-foldername petfit`.

Launch plasma-input modelling:

```bash
petfit-docker /path/to/your/bids /path/to/your/derivatives participant \
  --app modelling_plasma \
  --blood-dir /path/to/your/blood
```

Run plasma-input modelling automatically:

```bash
petfit-docker /path/to/your/bids /path/to/your/derivatives participant \
  --app modelling_plasma \
  --blood-dir /path/to/your/blood \
  --automatic
```

Print the generated Docker command without executing it:

```bash
petfit-docker /path/to/your/bids /path/to/your/derivatives participant \
  --app modelling_ref \
  --dry-run
```

The published PETFit images are currently `linux/amd64` only. The wrapper
requests `--platform linux/amd64` by default so Docker does not emit a platform
mismatch warning on Apple Silicon. Override this with `--platform` if a native or
multi-architecture image is available.

Test a local petfit checkout without rebuilding the image with `--patch` (or
`-f`), mirroring the PETPrep Docker wrapper. The wrapper bind-mounts the source
into the container, where petfit is reinstalled from it at startup so it
overrides the version baked into the image:

```bash
petfit-docker /path/to/your/bids /path/to/your/derivatives participant \
  --app modelling_ref \
  --patch /path/to/your/petfit/checkout
```

## Interactive mode

Interactive mode launches a Shiny web app accessible in your browser at `http://localhost:3838`.

The examples below show the `petfit-docker` wrapper command first, followed by the equivalent raw `docker run` command.

**Region definition:**

```bash
pip install petfit-docker

petfit-docker /path/to/your/bids /path/to/your/derivatives participant \
  --app regiondef
```

```bash
docker run -it --rm \
  -v /path/to/your/bids:/data/bids_dir:ro \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  -p 3838:3838 \
  mathesong/petfit:latest \
  --func regiondef
```

**Modelling with plasma input:**

```bash
petfit-docker /path/to/your/bids /path/to/your/derivatives participant \
  --app modelling_plasma \
  --blood-dir /path/to/your/blood
```

```bash
docker run -it --rm \
  -v /path/to/your/bids:/data/bids_dir:ro \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  -v /path/to/your/blood:/data/blood_dir:ro \
  -p 3838:3838 \
  mathesong/petfit:latest \
  --func modelling_plasma
```

**Modelling with reference tissue:**

```bash
petfit-docker /path/to/your/bids /path/to/your/derivatives participant \
  --app modelling_ref
```

```bash
docker run -it --rm \
  -v /path/to/your/bids:/data/bids_dir:ro \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  -p 3838:3838 \
  mathesong/petfit:latest \
  --func modelling_ref
```

The container exits cleanly when you close the app.

## Automatic mode

Automatic mode runs the pipeline non-interactively. The container exits when processing is complete. As above, each example shows the `petfit-docker` wrapper command first, then the equivalent raw `docker run` command.

**Full pipeline:**

```bash
# Plasma input
petfit-docker /path/to/your/bids /path/to/your/derivatives participant \
  --app modelling_plasma \
  --blood-dir /path/to/your/blood \
  --automatic

# Reference tissue
petfit-docker /path/to/your/bids /path/to/your/derivatives participant \
  --app modelling_ref \
  --automatic
```

```bash
# Plasma input
docker run --rm \
  -v /path/to/your/bids:/data/bids_dir:ro \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  -v /path/to/your/blood:/data/blood_dir:ro \
  mathesong/petfit:latest \
  --func modelling_plasma \
  --mode automatic

# Reference tissue
docker run --rm \
  -v /path/to/your/bids:/data/bids_dir:ro \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  mathesong/petfit:latest \
  --func modelling_ref \
  --mode automatic
```

**Single step:**

```bash
petfit-docker /path/to/your/bids /path/to/your/derivatives participant \
  --app modelling_plasma \
  --blood-dir /path/to/your/blood \
  --automatic \
  --step weights
```

```bash
docker run --rm \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  -v /path/to/your/blood:/data/blood_dir:ro \
  mathesong/petfit:latest \
  --func modelling_plasma \
  --mode automatic \
  --step weights
```

**Custom analysis folder:**

```bash
petfit-docker /path/to/your/bids /path/to/your/derivatives participant \
  --app modelling_plasma \
  --blood-dir /path/to/your/blood \
  --automatic \
  --analysis-foldername Baseline_only
```

```bash
docker run --rm \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  -v /path/to/your/blood:/data/blood_dir:ro \
  mathesong/petfit:latest \
  --func modelling_plasma \
  --mode automatic \
  --analysis_foldername Baseline_only
```

**External config file:**

A config file which lives outside the dataset -- one shared between studies, or
kept under version control -- can be supplied directly. PETFit copies it into
the analysis folder as `desc-petfitoptions_config.json` and then runs exactly as
it would with a config created interactively, so the settings which produced the
outputs always sit beside them. The analysis folder is created if it does not
exist yet, which means an external config can start a fresh analysis:

```bash
petfit-docker /path/to/your/bids /path/to/your/derivatives participant \
  --app modelling_ref \
  --automatic \
  --analysis-foldername Shared_Settings \
  --config-file /path/to/your/petfit_config.json
```

```bash
docker run --rm \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  -v /path/to/your/petfit_config.json:/data/config.json:ro \
  mathesong/petfit:latest \
  --func modelling_ref \
  --mode automatic \
  --analysis_foldername Shared_Settings \
  --config_file /data/config.json
```

The console reports the copy, and says so explicitly when a config already in
that folder was replaced:

```
=== External config file ===
  Source:      /path/to/your/petfit_config.json
  Copied to:   /path/to/your/derivatives/petfit/Shared_Settings/desc-petfitoptions_config.json
  NOTE: this REPLACED the config file already in that folder.
```

The same option works in interactive mode, where the app opens with the external
config's settings already loaded.

**External regions file:**

The region definition app takes an external `petfit_regions.tsv` the same way,
copied into the petfit output folder:

```bash
petfit-docker /path/to/your/bids /path/to/your/derivatives participant \
  --app regiondef \
  --automatic \
  --regions-file /path/to/your/petfit_regions.tsv
```

```bash
docker run --rm \
  -v /path/to/your/bids:/data/bids_dir:ro \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  -v /path/to/your/petfit_regions.tsv:/data/petfit_regions.tsv:ro \
  mathesong/petfit:latest \
  --func regiondef \
  --mode automatic \
  --regions_file /data/petfit_regions.tsv
```

Each of the two belongs to one app: `--config-file` is ignored by `regiondef`,
and `--regions-file` is ignored by the modelling apps, with a note on the
console.

**Merging runs:**

Region definition pools a measurement's runs into a single measurement by
default, for the common case where `run-01` and `run-02` are two scanning
occasions from one injection. Pass `--no-merge-runs` (wrapper) or
`--no_merge_runs` (container) for datasets where each run is a separate
injection:

```bash
petfit-docker /path/to/your/bids /path/to/your/derivatives participant \
  --app regiondef \
  --automatic \
  --no-merge-runs
```

```bash
docker run --rm \
  -v /path/to/your/bids:/data/bids_dir:ro \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  mathesong/petfit:latest \
  --func regiondef \
  --mode automatic \
  --no_merge_runs
```

The option belongs to `regiondef` alone -- merging is decided there and is then a
property of the combined TACs -- so it is ignored by the modelling apps, with a
note on the console. See
[Merging runs](../usage/region-definition.md#merging-runs).

**Nothing is replaced until the external file has been checked.** A config is
rejected unless it is valid JSON, carries the `Subsetting` and `Models`
sections, and declares the `modelling_configuration_type` matching the app it
was given to -- so a reference tissue config handed to `modelling_plasma` is
refused rather than replacing the analysis config and then having plasma steps
run against it. A regions file is rejected unless it has all of `RegionName`,
`folder`, `description` and `ConstituentRegion`, defines at least one region,
and names at least one folder which exists in the derivatives directory. In
every case the file already in place is left untouched.

**A run which fails before doing any work puts the previous file back.** If the
run is abandoned during setup -- an absent ancillary folder, an undeterminable
pipeline type, a regions file which produces no TACs -- the config or regions
file that was replaced is restored, and the console says so. Where there was no
file to replace, the copy is removed again, so a failed run leaves the folder
exactly as it found it.

## Command-line options

| Option | Description |
|--------|-------------|
| `--func` | App to run: `regiondef`, `modelling_plasma`, or `modelling_ref` (required) |
| `--mode` | `interactive` (default) or `automatic` |
| `--step` | Specific step for automatic mode: `datadef`, `weights`, `delay`, `reference_tac`, `model1`, `model2`, `model3` |
| `--analysis_foldername` | Analysis subfolder name (default: `Primary_Analysis`) |
| `--petfit_output_foldername` | Name of petfit output folder within derivatives (default: `petfit`) |
| `--config_file` | External modelling config JSON, copied into the analysis folder (modelling apps only) |
| `--regions_file` | External `petfit_regions.tsv`, copied into the petfit output folder (`regiondef` only) |
| `--no_merge_runs` | Keep each run as a separate measurement instead of pooling a measurement's runs into one (`regiondef` only). Runs are merged by default |
| `--cores` | Number of cores for parallel processing (default: `1`) |

## Mount points

| Mount point | Access | Purpose |
|-------------|--------|---------|
| `/data/bids_dir` | Read-only | Your BIDS dataset |
| `/data/derivatives_dir` | Read-write | Derivatives directory (PETFit writes outputs here) |
| `/data/blood_dir` | Read-only | Blood data for plasma input models |
| `/data/config.json` | Read-only | External modelling config file (single-file mount) |
| `/data/petfit_regions.tsv` | Read-only | External regions file (single-file mount) |

You can mount directories flexibly:

```bash
# BIDS directory only (derivatives auto-created inside it)
-v /study/bids:/data/bids_dir

# Derivatives directory only (no BIDS needed for automatic mode)
-v /study/derivatives:/data/derivatives_dir

# Both directories (explicit control)
-v /study/bids:/data/bids_dir \
-v /analysis/derivatives:/data/derivatives_dir
```

## Port configuration

The container exposes port 3838 internally. Map it to any host port:

```bash
-p 3838:3838    # Standard
-p 8080:3838    # Custom port for server usage
-p 3839:3838    # Run multiple instances
```

The port you browse to is always the **host** port — the left-hand side of `-p`. To run several instances at once, give each a different host port (`-p 3839:3838`, `-p 3840:3838`, …); the container side can stay `3838`.

The entrypoint also checks that its internal port is free and, if not, scans upward to the next available one (printing the final `http://localhost:<port>` address). Within Docker's isolated network this rarely changes anything, but if you want to move the internal port — for example to match a custom `-p` target — set `SHINY_PORT`:

```bash
-e SHINY_PORT=8080 ... -p 8080:8080
```

## File permissions on Linux

On Linux, Docker containers run as root by default, which can cause permission issues with output files. Two solutions:

**Option 1 (recommended): Run as your user:**

```bash
docker run --user $(id -u):$(id -g) \
  # ... rest of your command
```

**Option 2: Fix permissions afterwards:**

```bash
sudo chown -R $(id -u):$(id -g) /path/to/derivatives
```
