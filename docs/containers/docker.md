# Docker

## Getting the image

```bash
# Pull pre-built image
docker pull mathesong/petfit:latest

# Or build from source
git clone https://github.com/mathesong/petfit.git
cd petfit
docker build -f docker/Dockerfile -t mathesong/petfit:latest .
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

## Batch processing

```bash
for analysis in Analysis1 Analysis2 Analysis3; do
  docker run --rm \
    --user $(id -u):$(id -g) \
    -v /data/derivatives:/data/derivatives_dir \
    -v /data/blood:/data/blood_dir \
    mathesong/petfit:latest \
    --func modelling_plasma \
    --mode automatic \
    --analysis_foldername "$analysis"
done
```

## Development testing

A `docker-compose.yml` file is provided for development:

```bash
cd docker/
docker-compose up petfit-modelling-plasma
```

## Error codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Configuration or validation error |
| 2 | Missing required files or directories |
| 3 | Processing error |
