# Interactive Tests

This directory contains interactive tests that launch Shiny applications and cannot be run in automated CI/CD environments.

## Purpose

These tests are designed to be run **manually** by developers to verify that:
- Shiny apps launch correctly
- UI elements render properly
- Basic functionality works in the interactive environment
- App parameter passing works correctly

## Running Interactive Tests

### Prerequisites
- R session with petfit package loaded
- Interactive environment (not headless server)
- Ability to view and interact with web browsers

### How to Run

```r
# From R console in the package directory:
source("tests/interactive/test-launch_apps_interactive.R")

# Or run individual test functions:
test_region_definition_app()
test_modelling_app()
test_both_apps_sequential()
test_docker_functions()  # Docker validation functions (no GUI)
```

### What to Expect

- **Browser Windows**: Tests will open browser windows/tabs with Shiny apps
- **Manual Interaction Required**: You may need to interact with the apps to verify functionality
- **Manual Verification**: Tests will prompt you to verify that apps loaded correctly
- **Console Output**: Look for success/error messages in the R console

## Test Coverage

- `test-launch_apps_interactive.R`: Interactive Shiny app launching and Docker function validation
- `test-apps_ui_interactive.R`: UI element verification (future)
- `test-apps_workflow_interactive.R`: End-to-end workflow testing (future)

## Important Notes

⚠️ **Never run these in CI/CD pipelines** - they require interactive environments  
⚠️ **Close apps manually** - Tests may leave browser windows/R sessions open  
⚠️ **Resource intensive** - Apps use significant memory and CPU  
⚠️ **Network dependent** - Some tests may require network access for dependencies
⚠️ **Docker functions** - Docker validation tests require Docker runtime (not available in GitHub Actions)

## Troubleshooting

**App doesn't launch:**
- Check that all package dependencies are installed
- Verify BIDS directory structure exists
- Check R console for error messages

**Browser doesn't open:**
- Check R session can open browser windows
- Try setting `options(browser = "your_browser")`
- Check firewall/security settings

**App crashes:**
- Check input data validity
- Verify file permissions
- Check available memory