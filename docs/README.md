# PETFit Documentation

This directory contains the source files for the PETFit documentation site, built with [Sphinx](https://www.sphinx-doc.org/) and the [MyST](https://myst-parser.readthedocs.io/) Markdown parser.

## Building the documentation locally

### Install dependencies

```bash
pip install -r docs/requirements.txt
```

### Build

```bash
cd docs
make html
```

The built site will be at `docs/_build/html/index.html`. Open it in your browser to preview.

### Clean and rebuild

```bash
cd docs
make clean
make html
```

## File structure

| File | Page |
|------|------|
| `index.md` | Homepage and main navigation |
| `installation.md` | Installation guide |
| `quickstart.md` | Quick start tutorial |
| `models.md` | Supported kinetic models reference |
| `outputs.md` | Output file descriptions |
| `troubleshooting.md` | Troubleshooting guide |
| `contributing.md` | Contributing and testing guide |
| `api.md` | API reference for exported R functions |
| `changes.md` | Changelog |
| `citation.md` | Citation information |
| `license.md` | Licence |
| `usage/index.md` | Usage guide overview |
| `usage/folder-structure.md` | PETFit folder structures and workflow |
| `usage/region-definition.md` | Region definition app |
| `usage/modelling-plasma.md` | Plasma input modelling app |
| `usage/modelling-reference.md` | Reference tissue modelling app |
| `usage/reports.md` | Parameterised HTML reports |
| `containers/index.md` | Container overview |
| `containers/docker.md` | Docker usage |
| `containers/singularity.md` | Singularity/Apptainer usage |

## Adding a new page

1. Create a new `.md` file in the appropriate directory.
2. Add the filename (without extension) to the `toctree` directive in the parent index file. For example, to add a page under the User Guide, edit `usage/index.md`:

   ````markdown
   ```{toctree}
   :maxdepth: 2

   folder-structure
   region-definition
   modelling-plasma
   modelling-reference
   reports
   your-new-page
   ```
   ````

3. Build and check that the page appears in the navigation.

## MyST Markdown syntax

The documentation uses [MyST](https://myst-parser.readthedocs.io/) extensions. Here are the key patterns used throughout:

### Admonitions

```markdown
```{note}
This is a note.
```

```{important}
This is important.
```

```{warning}
This is a warning.
```
```

### Tabbed content

````markdown
`````{tab-set}

````{tab-item} R
```r
# R code here
```
````

````{tab-item} Docker
```bash
# Docker commands here
```
````

`````
````

### Grid cards (used on the homepage)

```markdown
::::{grid} 2
:gutter: 3

:::{grid-item-card} Card Title
:link: page-name
:link-type: doc

Card description text.
:::

::::
```

### Definition lists

```markdown
**Term**
: Definition text here.
```

### Cross-references

```markdown
See [Page title](page-name.md) for details.
See [Section title](page-name.md#section-anchor) for a specific section.
```

## Configuration

- `conf.py` — Sphinx configuration (project name, version, theme, extensions)
- `requirements.txt` — Python dependencies for building
- `_static/custom.css` — Custom CSS overrides
- `_templates/` — Custom Sphinx templates (currently empty)

## Deployment

The documentation is built and deployed automatically by [Read the Docs](https://readthedocs.org/) on pushes to the `main` branch. Configuration is in `.readthedocs.yaml` at the repository root.


