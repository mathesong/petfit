# petfit-docker

`petfit-docker` is a lightweight Python wrapper that turns a BIDS-App-like
command line into the matching `docker run` invocation for PETFit.
Interactive Shiny mode is the default; use `--automatic` or
`--mode automatic` to run a non-interactive pipeline.

```bash
petfit-docker /path/to/bids /path/to/derivatives participant \
  --app modelling_plasma \
  --blood-dir /path/to/blood \
  --analysis-foldername Primary_Analysis
```

The command above runs:

```bash
docker run --rm -it \
  -p 3838:3838 \
  -v /path/to/bids:/data/bids_dir:ro \
  -v /path/to/derivatives:/data/derivatives_dir:rw \
  -v /path/to/blood:/data/blood_dir:ro \
  mathesong/petfit:latest \
  --func modelling_plasma --mode interactive
```

## Installation

```bash
pip install petfit-docker
```

Run `petfit-docker --help` at any time to see all available options, including
descriptions of each app and analysis folder:

```bash
petfit-docker --help
```

## Examples

Launch the default region definition app:

```bash
petfit-docker /path/to/bids /path/to/derivatives/petfit participant
```

The three positional arguments follow the BIDS App convention:

```text
petfit-docker <bids_dir> <output_dir> participant
```

Launch region definition:

```bash
petfit-docker /path/to/bids /path/to/derivatives participant --app regiondef
```

The positional `output_dir` can be either the derivatives root or the final
PETFit output directory. These are equivalent with the default output folder
name:

```bash
petfit-docker /path/to/bids /path/to/derivatives/petfit participant
petfit-docker /path/to/bids /path/to/derivatives participant --app regiondef
petfit-docker /path/to/bids /path/to/derivatives/petfit participant --app regiondef
```

Launch plasma-input modelling:

```bash
petfit-docker /path/to/bids /path/to/derivatives participant \
  --app modelling_plasma \
  --blood-dir /path/to/blood
```

Run plasma-input modelling automatically:

```bash
petfit-docker /path/to/bids /path/to/derivatives participant \
  --app modelling_plasma \
  --blood-dir /path/to/blood \
  --automatic
```

Open a shell in the image:

```bash
petfit-docker --shell -i mathesong/petfit:latest
```

## Patching a local petfit

Use `--patch` (or `-f`) to point the wrapper at a local petfit checkout and test
your local changes without rebuilding the image. The wrapper bind-mounts the
source into the container, where it is reinstalled from source at startup so it
overrides the petfit baked into the image:

```bash
petfit-docker /path/to/bids /path/to/derivatives participant \
  --app modelling_ref \
  --patch /path/to/your/petfit/checkout
```

This mirrors the `--patch` option of the PETPrep Docker wrapper. Because petfit
is an R package it is reinstalled (not run directly from source), so the first
few seconds of startup are spent installing the patched package. The patch
works with every mode, including `--shell`.

## Apple Silicon

The published PETFit Docker images are currently `linux/amd64` only. The
wrapper therefore requests `--platform linux/amd64` by default, which avoids
Docker's platform-mismatch warning on Apple Silicon while running under
emulation. If a native or multi-architecture image is published later, override
the platform with `--platform linux/arm64` or disable the explicit platform with
`--platform ""`.
