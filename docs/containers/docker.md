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

Install it from this checkout:

```bash
cd wrapper
python -m pip install -e .
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

**Region definition:**

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
docker run -it --rm \
  -v /path/to/your/bids:/data/bids_dir:ro \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  -p 3838:3838 \
  mathesong/petfit:latest \
  --func modelling_ref
```

The container exits cleanly when you close the app.

## Automatic mode

Automatic mode runs the pipeline non-interactively. The container exits when processing is complete.

**Full pipeline:**

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
docker run --rm \
  -v /path/to/your/derivatives:/data/derivatives_dir:rw \
  -v /path/to/your/blood:/data/blood_dir:ro \
  mathesong/petfit:latest \
  --func modelling_plasma \
  --mode automatic \
  --analysis_foldername Baseline_only
```

## Command-line options

| Option | Description |
|--------|-------------|
| `--func` | App to run: `regiondef`, `modelling_plasma`, or `modelling_ref` (required) |
| `--mode` | `interactive` (default) or `automatic` |
| `--step` | Specific step for automatic mode: `datadef`, `weights`, `delay`, `reference_tac`, `model1`, `model2`, `model3` |
| `--analysis_foldername` | Analysis subfolder name (default: `Primary_Analysis`) |
| `--petfit_output_foldername` | Name of petfit output folder within derivatives (default: `petfit`) |
| `--cores` | Number of cores for parallel processing (default: `1`) |

## Mount points

| Mount point | Access | Purpose |
|-------------|--------|---------|
| `/data/bids_dir` | Read-only | Your BIDS dataset |
| `/data/derivatives_dir` | Read-write | Derivatives directory (PETFit writes outputs here) |
| `/data/blood_dir` | Read-only | Blood data for plasma input models |

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
