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



## Report content

Reports are not just visualisations — they are where the computational work takes place. 
You can visualise the R code used at each stage of the analysis if you would like to customise the analysis in R.


