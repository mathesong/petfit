# Docker Implementation for PETFit Apps

This directory contains Docker implementation files for running the PETFit region definition and modelling apps in containerized environments.

## Quick Start

### Interactive Mode (Default)
```bash
# Modelling app with plasma input
docker run -it --rm \
  --user $(id -u):$(id -g) \
  -v /path/to/your/bids:/data/bids_dir \
  -v /path/to/your/blood:/data/blood_dir \
  -p 3838:3838 \
  mathesong/petfit:latest \
  --func modelling_plasma

# Modelling app with reference tissue
docker run -it --rm \
  --user $(id -u):$(id -g) \
  -v /path/to/your/bids:/data/bids_dir \
  -p 3838:3838 \
  mathesong/petfit:latest \
  --func modelling_ref

# Region definition app
docker run -it --rm \
  --user $(id -u):$(id -g) \
  -v /path/to/your/bids:/data/bids_dir \
  -p 3838:3838 \
  mathesong/petfit:latest \
  --func regiondef
```

Then open http://localhost:3838 in your browser.

### Automatic Mode
```bash
# Full pipeline execution with plasma input
docker run -it --rm \
  --user $(id -u):$(id -g) \
  -v /path/to/derivatives:/data/derivatives_dir \
  -v /path/to/blood:/data/blood_dir \
  mathesong/petfit:latest \
  --func modelling_plasma \
  --mode automatic

# Full pipeline execution with reference tissue
docker run -it --rm \
  --user $(id -u):$(id -g) \
  -v /path/to/derivatives:/data/derivatives_dir \
  mathesong/petfit:latest \
  --func modelling_ref \
  --mode automatic

# Single step execution
docker run -it --rm \
  --user $(id -u):$(id -g) \
  -v /path/to/derivatives:/data/derivatives_dir \
  mathesong/petfit:latest \
  --func modelling_plasma \
  --mode automatic \
  --step weights
```

## Command Line Arguments

### Required
- `--func`: Application function (`regiondef`, `modelling_plasma`, or `modelling_ref`)

### Optional
- `--mode`: Execution mode (`interactive` [default] or `automatic`)
- `--step`: Specific step for automatic mode (`datadef`, `weights`, `delay`, `model1`, `model2`, `model3`)
- `--petfit_output_foldername`: Output folder name (default: `petfit`)
- `--analysis_foldername`: Analysis subfolder name (default: `Primary_Analysis`)

## Volume Mounts

### Flexible Directory Mounting
You can mount directories in several ways:

```bash
# BIDS directory only (derivatives auto-created)
-v /study/bids:/data/bids_dir

# Derivatives directory only (no BIDS needed)
-v /study/derivatives:/data/derivatives_dir

# Both directories (explicit control)
-v /study/bids:/data/bids_dir \
-v /analysis/derivatives:/data/derivatives_dir

# With blood data (when required)
-v /study/bids:/data/bids_dir \
-v /study/blood:/data/blood_dir
```

### Blood Data Requirements
Blood data is required when using the plasma input app (`modelling_plasma`).

## Port Configuration

The container exposes port 3838 internally. You can map it to any external port:

```bash
# Standard mapping
-p 3838:3838

# Server usage
-p 8080:3838

# Multiple instances
-p 3839:3838
```

## Usage Examples

### Development Testing
```bash
# Use docker-compose for easy testing
cd docker/
docker-compose up petfit-modelling-plasma
```

### Production Usage
```bash
# Run modelling app with plasma input on server port 8080
docker run -d --name petfit-server \
  --user $(id -u):$(id -g) \
  -v /data/bids:/data/bids_dir \
  -v /data/blood:/data/blood_dir \
  -p 8080:3838 \
  mathesong/petfit:latest \
  --func modelling_plasma
```

### Batch Processing
```bash
# Process multiple analyses automatically
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

## Container Behavior

### Interactive Mode
- Container starts Shiny app
- Accessible via web browser
- **Container exits when app is closed** (clean shutdown)

### Automatic Mode
- Loads existing configuration from analysis folder
- Executes processing pipeline or specific step
- Generates reports
- **Container exits when processing complete**

## Error Codes

- **0**: Success
- **1**: Configuration/validation errors
- **2**: Missing required files/directories
- **3**: Processing errors

## Building from Source

```bash
# Build the image
docker build -f docker/Dockerfile -t petfit:local .

# Test with docker-compose
cd docker/
docker-compose build
docker-compose up petfit-modelling-plasma
```

## File Structure

```
docker/
├── Dockerfile              # Container definition
├── run_petfit.R           # Entry point script
├── docker-compose.yml      # Development testing
├── plan.md                 # Implementation plan
└── README.md              # This file
```
