# Parameterised reports

PETFit automatically generates HTML reports for every analysis step. These reports are designed for quality control — they contain interactive plots, data summaries, and diagnostic information to help you evaluate your results.

## Where reports are saved

Reports are saved in a `reports/` subdirectory within your analysis folder:

```
derivatives/petfit/<analysis_folder>/reports/
```

## Available reports

### Step reports

Generated after each pipeline step:

| Step | Report file | Contents |
|------|-------------|----------|
| Data definition | `data_definition_report.html` | Data subsetting summary, TAC overview |
| Weights | `weights_report.html` | Weights calculation details, per-frame weights plots |
| Delay fitting | `delay_report.html` | Delay estimates, blood-tissue alignment plots |
| Reference TAC | `reference_tac_report.html` | Reference region fitting, noise comparison |

### Model reports

Generated after each model fitting step. The template is chosen based on the model type, but the output file is always named by model number:

| Model slot | Output file |
|------------|------------|
| Model 1 | `model1_report.html` |
| Model 2 | `model2_report.html` |
| Model 3 | `model3_report.html` |

For example, if you configure 2TCM as Model 1 and Logan as Model 2, PETFit uses `2tcm_report.Rmd` to generate `model1_report.html` and `logan_report.Rmd` to generate `model2_report.html`.

Available model templates: 1TCM, 2TCM, 2TCM_irr, Logan, MA1, Patlak, SRTM, SRTM2, refLogan, MRTM1, MRTM2, refPatlak.

## Report features

All reports share a common structure:

- **Table of contents** with collapsible navigation
- **Analysis configuration summary** showing which parameters were used
- **Interactive Plotly plots** — hover for values, zoom, pan, and export
- **Cross-filtering** — hover over one plot to highlight corresponding data in others
- **Code folding** — implementation code is hidden by default but can be expanded
- **Session information** — full R session info for reproducibility
- **Timestamp** — when the report was generated

## Report content

Reports are not just visualisations — they perform actual computational work. Each template contains the analysis logic, making the reports both transparent and reproducible. If you re-render a report with the same data and configuration, you get the same results.

### Typical report sections

- Configuration and parameter summary tables
- Data quality diagnostics
- Model fit plots for each PET measurement and region
- Parameter estimate tables with uncertainties
- Summary statistics across measurements
- Recommendations for next steps

## Rendering reports manually

Reports are R Markdown templates stored in the package's `inst/rmd/` directory. You can render them manually if needed:

```r
rmarkdown::render(
  input = system.file("rmd", "2tcm_report.Rmd", package = "petfit"),
  params = list(
    analysis_folder = "/path/to/analysis/folder",
    config_path = "/path/to/config.json"
  ),
  output_dir = "/path/to/output"
)
```
