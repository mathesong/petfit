#' Region Definition App
#'
#' @description Launch a separate Shiny app for defining brain regions
#'
#' @param bids_dir Character string path to the BIDS directory (default: NULL)
#' @param derivatives_dir Character string path to derivatives directory (default: bids_dir/derivatives if bids_dir provided)
#' @param petfit_output_foldername Character string name for petfit output folder within derivatives (default: "petfit")
#' @details Config files (petfit_regions.tsv) are saved to:
#'   - bids_dir/code/petfit if bids_dir provided
#'   - derivatives_dir/petfit_output_foldername if no bids_dir
#' @export
region_definition_app <- function(bids_dir = NULL, derivatives_dir = NULL, petfit_output_foldername = "petfit") {
  
  # Set derivatives directory logic
  if (is.null(derivatives_dir)) {
    if (is.null(bids_dir)) {
      stop("Either bids_dir or derivatives_dir must be provided", call. = FALSE)
    }
    # Default: bids_dir/derivatives
    derivatives_dir <- file.path(bids_dir, "derivatives")
  }
  
  # Validate directories
  if (!is.null(bids_dir) && !dir.exists(bids_dir)) {
    stop(paste("BIDS directory does not exist:", bids_dir), call. = FALSE)
  }
  
  # Set directories for reading and writing config files
  # Always write to derivatives/petfit (base petfit folder, same as combined_regions)
  write_config_dir <- file.path(derivatives_dir, "petfit")
  
  # For reading: check derivatives/petfit first, then BIDS code directory
  read_config_dirs <- c(write_config_dir)
  if (!is.null(bids_dir)) {
    read_config_dirs <- c(read_config_dirs, file.path(bids_dir, "code", "petfit"))
  }
  
  # Create write config directory if it doesn't exist
  if (!dir.exists(write_config_dir)) {
    dir.create(write_config_dir, recursive = TRUE)
    cat("Created config directory:", write_config_dir, "\n")
  }
  
  # Normalize paths
  if (!is.null(bids_dir)) {
    bids_dir <- normalizePath(bids_dir, mustWork = FALSE)
  }
  derivatives_dir <- normalizePath(derivatives_dir, mustWork = FALSE)
  write_config_dir <- normalizePath(write_config_dir, mustWork = FALSE)
  
  # Create derivatives directory if it doesn't exist
  if (!dir.exists(derivatives_dir)) {
    dir.create(derivatives_dir, recursive = TRUE)
    cat("Created derivatives directory:", derivatives_dir, "\n")
  }
  
  # Load participant data if BIDS directory is provided
  participant_data <- NULL
  if (!is.null(bids_dir)) {
    participant_data <- load_participant_data(bids_dir)
    if (!is.null(participant_data)) {
      cat("Found participants.tsv with", nrow(participant_data$data), "participants\n")
      if (!is.null(participant_data$metadata)) {
        cat("Found participants.json with metadata for", length(participant_data$metadata), "columns\n")
      }
    }
  }
  
  # Print configuration
  cat("Starting Region Definition App:\n")
  if (!is.null(bids_dir)) {
    cat("  BIDS directory:", bids_dir, "\n")
  }
  cat("  Derivatives directory:", derivatives_dir, "\n")
  cat("  Config write directory:", write_config_dir, "\n")
  cat("  Config read directories:", paste(read_config_dirs, collapse=", "), "\n")
  
  # Initialize petfit_regions.tsv file with read/write logic
  # Always write to write_config_dir
  write_regions_file <- file.path(write_config_dir, "petfit_regions.tsv")
  
  # Find existing regions file by checking read directories in order
  existing_write_regions_file <- NULL
  for (dir in read_config_dirs) {
    potential_file <- file.path(dir, "petfit_regions.tsv")
    if (file.exists(potential_file)) {
      existing_write_regions_file <- potential_file
      break
    }
  }
  
  file_was_empty <- FALSE
  if (is.null(existing_write_regions_file)) {
    # Create empty regions file with proper columns
    empty_regions <- tibble::tibble(
      RegionName = character(0),
      folder = character(0),
      description = character(0),
      ConstituentRegion = character(0)
    )
    readr::write_tsv(empty_regions, write_regions_file)
    file_was_empty <- TRUE
    cat("Created empty petfit_regions.tsv file:", write_regions_file, "\n")
  } else {
    # Check if existing file is empty
    existing_data <- readr::read_tsv(existing_write_regions_file, show_col_types = FALSE)
    file_was_empty <- nrow(existing_data) == 0
    cat("Found existing petfit_regions.tsv file:", existing_write_regions_file, "\n")

    # If reading from a different location than write location, copy it over
    # Normalize both paths before comparison to avoid false mismatches from path formatting
    normalized_existing <- normalizePath(existing_write_regions_file, mustWork = TRUE)
    normalized_write <- normalizePath(write_regions_file, mustWork = FALSE)

    if (normalized_existing != normalized_write) {
      file.copy(existing_write_regions_file, write_regions_file, overwrite = TRUE)
      cat("Copied regions file to write location:", write_regions_file, "\n")
    }
  }

  # Validate existing regions against available TACs files (if file not empty)
  if (!file_was_empty) {
    # Read the regions file from write location to get current state
    regions_to_validate <- tryCatch({
      readr::read_tsv(write_regions_file, show_col_types = FALSE)
    }, error = function(e) {
      NULL
    })

    if (!is.null(regions_to_validate) && nrow(regions_to_validate) > 0) {
      validated_mapping <- tryCatch({
        suppressMessages({
          create_petfit_regions_files(write_regions_file, derivatives_dir)
        })
      }, error = function(e) {
        NULL
      })

      if (!is.null(validated_mapping) && nrow(validated_mapping) > 0) {
        # Check if all regions in file were successfully matched
        existing_regions_count <- nrow(regions_to_validate)
        validated_regions_count <- nrow(validated_mapping)

        if (validated_regions_count < existing_regions_count) {
          cat("Warning: Not all segmentations from the existing region definition were found in the derivatives folder\n")
          cat("  Regions in file:", existing_regions_count, "\n")
          cat("  Regions matched:", validated_regions_count, "\n")
        } else {
          cat("Successfully loaded existing region definitions\n")
        }
      } else {
        cat("Warning: Not all segmentations from the existing region definition were found in the derivatives folder\n")
      }
    }
  }

  # Try to create TACs list, with error handling
  tacs_list <- tryCatch({
    create_tacs_list(derivatives_dir)
  }, error = function(e) {
    cat("Warning: Could not create TACs list:", e$message, "\n")
    cat("Creating empty TACs list for now.\n")
    tibble::tibble(
      tacs_filedescription = character(0),
      path = character(0),
      foldername = character(0),
      description = character(0)
    )
  })
  
  # UI for region definition app
  ui <- fluidPage(
    theme = shinythemes::shinytheme("flatly"),
    
    titlePanel("Region Definition"),
    
    sidebarLayout(
      sidebarPanel(
        h3("TACs File Selection"),
        p("Select from available TACs files to define regions"),
        
        conditionalPanel(
          condition = "output.has_tacs_files",
          selectInput("selected_tacs", 
                     "Available TACs Files:",
                     choices = NULL,
                     selected = NULL),
          br(),
          actionButton("load_tacs", "Load Selected Regions", class = "btn-primary"),
          br(), br(),
          actionButton("add_all_regions", "Add All Regions from TACs File", 
                      class = "btn-info"),
          br(), br()
        ),
        
        conditionalPanel(
          condition = "!output.has_tacs_files",
          div(class = "alert alert-warning",
              h4("No TACs Files Found"),
              p("No TACs files were found in the derivatives directory:", 
                derivatives_dir),
              p("Please ensure TACs files are present and try again.")
          )
        ),
        
        hr(),
        
        h3("Region Definition"),
        textInput("region_name", "Region Name:", value = ""),
        uiOutput("region_name_error"),
        
        br(),
        actionButton("add_region", "Add Region", 
                    class = "btn-success"),
        br(), br(),
        actionButton("remove_region", "Remove Region", 
                    class = "btn-danger"),
        br(), br(), br(), br(),
        actionButton("remove_all_regions", "Remove All Regions", 
                    class = "btn-danger", style = "background-color: #8B0000; border-color: #8B0000;"),
        
        hr(),
        actionButton("generate_tacs", HTML("&#9654; Generate Combined TACs"), 
                    class = "btn-success", style = "font-weight: bold;"),
        
        conditionalPanel(
          condition = "input.load_tacs > 0",
          hr(),
          h4("TACs File Details"),
          verbatimTextOutput("tacs_info_sidebar")
        )
      ),
      
      mainPanel(
        tabsetPanel(
          tabPanel("Available Regions",
                   br(),
                   conditionalPanel(
                     condition = "output.has_morph_data",
                     h4("Available Regions"),
                     p("Select regions with non-zero volume:"),
                     br(),
                     div(
                       div(style = "margin-bottom: 10px;", 
                           strong("Filter regions by name:")),
                       div(class = "input-group",
                           tags$input(id = "region_filter", type = "text", class = "form-control",
                                     placeholder = "e.g., Caudate", value = ""),
                           div(class = "input-group-append",
                               actionButton("apply_filter", "Filter", 
                                          class = "btn btn-primary btn-sm"))
                       )
                     ),
                     br(),
                     uiOutput("region_checkboxes")
                   ),
                   conditionalPanel(
                     condition = "!output.has_morph_data",
                     div(class = "alert alert-info",
                         h4("No Regions Available"),
                         p("Select TACs file (left) to see available regions.")
                     )
                   )
          ),
          tabPanel("Defined Regions",
                   br(),
                   h4("Currently Defined Regions"),
                   p("Regions saved to petfit_regions.tsv:"),
                   tableOutput("defined_regions_table")
          )
        )
      )
    )
  )
  
  # Server logic for region definition app
  server <- function(input, output, session) {
    
    # Reactive value to store defined regions
    defined_regions_data <- reactiveVal(NULL)
    
    # Track if file was originally empty
    originally_empty <- reactiveVal(file_was_empty)
    
    
    # Load defined regions on startup
    observe({
      regions_data <- tryCatch({
        readr::read_tsv(write_regions_file, show_col_types = FALSE)
      }, error = function(e) {
        tibble::tibble(
          RegionName = character(0),
          folder = character(0),
          description = character(0),
          ConstituentRegion = character(0)
        )
      })
      defined_regions_data(regions_data)
    })
    
    # Clean up empty file on session end
    session$onSessionEnded(function() {
      # Read file directly instead of using reactive
      current_data <- tryCatch({
        readr::read_tsv(write_regions_file, show_col_types = FALSE)
      }, error = function(e) {
        NULL
      })
      
      if (is.null(current_data) || nrow(current_data) == 0) {
        if (file.exists(write_regions_file)) {
          file.remove(write_regions_file)
          cat("Removed empty petfit_regions.tsv file on app close\n")
        }
      }
    })
    
    # Check if we have TACs files
    output$has_tacs_files <- reactive({
      nrow(tacs_list) > 0
    })
    outputOptions(output, "has_tacs_files", suspendWhenHidden = FALSE)
    
    # Check if we have morph data
    output$has_morph_data <- reactive({
      !is.null(morph_data()) && nrow(morph_data()) > 0
    })
    outputOptions(output, "has_morph_data", suspendWhenHidden = FALSE)
    
    # Generate checkboxes for regions
    output$region_checkboxes <- renderUI({
      full_morph_df <- morph_data()
      filtered_morph_df <- filtered_morph_data()
      
      if (is.null(full_morph_df) || nrow(full_morph_df) == 0) {
        return(NULL)
      }
      
      # Get currently selected regions from all data
      selected_region_names <- c()
      for (i in 1:nrow(full_morph_df)) {
        checkbox_id <- paste0("region_", i)
        if (!is.null(input[[checkbox_id]]) && input[[checkbox_id]]) {
          selected_region_names <- c(selected_region_names, full_morph_df$name[i])
        }
      }
      
      if (is.null(filtered_morph_df) || nrow(filtered_morph_df) == 0) {
        if (!is.null(input$region_filter) && input$region_filter != "") {
          if (length(selected_region_names) > 0) {
            # Show only selected regions when filter doesn't match anything new
            selected_checkboxes <- lapply(selected_region_names, function(region_name) {
              # Find the original index in full data
              orig_idx <- which(full_morph_df$name == region_name)
              checkbox_id <- paste0("region_", orig_idx)
              checkboxInput(
                inputId = checkbox_id,
                label = region_name,
                value = TRUE
              )
            })
            
            return(tagList(
              div(class = "alert alert-info", 
                  "No new regions match the filter '", input$region_filter, "'"),
              hr(),
              div(style = "background-color: #f8f9fa; padding: 10px; border-radius: 5px;",
                  h5("Currently Selected Regions:"),
                  do.call(tagList, selected_checkboxes))
            ))
          } else {
            return(div(class = "alert alert-info", 
                      "No regions match the filter '", input$region_filter, "'"))
          }
        }
        return(NULL)
      }
      
      # Separate filtered regions into unselected and selected
      filtered_names <- filtered_morph_df$name
      unselected_filtered_names <- setdiff(filtered_names, selected_region_names)
      
      # Count only unselected filtered regions for "Select all" button
      unselected_count <- length(unselected_filtered_names)
      
      # Create select all checkbox (only for unselected filtered regions)
      select_all_checkbox <- if (unselected_count > 0) {
        checkboxInput(
          inputId = "select_all_visible",
          label = paste0("Select all visible (", unselected_count, " unselected regions)"),
          value = FALSE
        )
      } else {
        div(class = "alert alert-success", "All visible regions are already selected!")
      }
      
      # Create checkboxes for UNSELECTED filtered regions only
      unselected_filtered_checkboxes <- if (length(unselected_filtered_names) > 0) {
        lapply(unselected_filtered_names, function(region_name) {
          # Find original index in full data
          orig_idx <- which(full_morph_df$name == region_name)
          checkbox_id <- paste0("region_", orig_idx)
          checkboxInput(
            inputId = checkbox_id,
            label = region_name,
            value = FALSE
          )
        })
      } else {
        NULL
      }
      
      # Create checkboxes for ALL selected regions (matching filter or not)
      selected_checkboxes <- if (length(selected_region_names) > 0) {
        lapply(selected_region_names, function(region_name) {
          # Find original index in full data
          orig_idx <- which(full_morph_df$name == region_name)
          checkbox_id <- paste0("region_", orig_idx)
          checkboxInput(
            inputId = checkbox_id,
            label = region_name,
            value = TRUE
          )
        })
      } else {
        NULL
      }
      
      # Build the result
      result_list <- list()
      
      # Add select all section
      result_list <- append(result_list, list(
        div(style = "border-bottom: 1px solid #ddd; padding-bottom: 10px; margin-bottom: 10px;",
            select_all_checkbox)
      ))
      
      # Add unselected filtered regions if they exist
      if (!is.null(unselected_filtered_checkboxes)) {
        result_list <- append(result_list, list(
          h5("Available Regions (matching filter):"),
          do.call(tagList, unselected_filtered_checkboxes)
        ))
      }
      
      # Add selected regions section if they exist
      if (!is.null(selected_checkboxes)) {
        result_list <- append(result_list, list(
          hr(),
          div(style = "background-color: #f8f9fa; padding: 10px; border-radius: 5px;",
              div(style = "display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px;",
                  h5(paste0("Selected Regions (", length(selected_region_names), " total):")),
                  actionButton("reset_selected", "Reset selected regions",
                              class = "btn-warning btn-sm",
                              style = "margin-left: 10px;")
              ),
              do.call(tagList, selected_checkboxes))
        ))
      }
      
      do.call(tagList, result_list)
    })
    
    # Update TACs file choices
    observe({
      if (nrow(tacs_list) > 0) {
        updateSelectInput(session, "selected_tacs",
                         choices = setNames(tacs_list$tacs_filedescription,
                                          tacs_list$tacs_filedescription))
      }
    })
    
    # Handle filter button click
    observeEvent(input$apply_filter, {
      full_morph_df <- morph_data()
      if (is.null(full_morph_df) || nrow(full_morph_df) == 0) {
        return()
      }
      
      if (is.null(input$region_filter) || input$region_filter == "") {
        # No filter - show all regions
        filtered_morph_data(full_morph_df)
      } else {
        # Apply filter
        filtered_df <- full_morph_df %>%
          dplyr::filter(stringr::str_detect(stringr::str_to_lower(name), 
                                           stringr::str_to_lower(input$region_filter)))
        filtered_morph_data(filtered_df)
      }
    })
    
    # Reactive to store loaded TACs data
    loaded_tacs_data <- reactiveVal(NULL)
    
    # Reactive to store morph data
    morph_data <- reactiveVal(NULL)
    
    # Reactive value to store filtered morph data (updated manually via button)
    filtered_morph_data <- reactiveVal(NULL)
    
    # Load selected TACs file
    observeEvent(input$load_tacs, {
      req(input$selected_tacs)

      # Find the selected TACs file info
      selected_info <- tacs_list[tacs_list$tacs_filedescription == input$selected_tacs, ]

      if (nrow(selected_info) > 0) {
        # Parse the key-value pairs back to get file details
        parsed_details <- interpret_bids_key_value_pairs(selected_info$description)

        # Get pre-computed file paths directly from tacs_list (no manual searching needed!)
        tacs_file <- selected_info$tacs_path[1]
        morph_file <- selected_info$morph_path[1]

        # Extract attributes from tacs file for console output
        tacs_attrs <- extract_bids_attributes_from_filename(tacs_file)

        # Console output - show file and seg/label information
        cat("Selected TACs file:", tacs_file, "\n")
        if (!is.na(morph_file)) {
          cat("Matched morph file:", morph_file, "\n")
        } else {
          cat("No matching morph file - using volume=1 fallback\n")
        }
        if (!is.na(tacs_attrs$seg)) {
          cat("Segmentation key: seg =", tacs_attrs$seg, "\n")
        } else if (!is.na(tacs_attrs$label)) {
          cat("Segmentation key: label =", tacs_attrs$label, "\n")
        }

        # Load morph data with volume=1 fallback
        morph_df <- get_region_volumes_from_morph(morph_file)

        if (!is.null(morph_df)) {
          # Filter for non-zero volume-mm3 values
          if ("volume-mm3" %in% colnames(morph_df) && "name" %in% colnames(morph_df)) {
            filtered_morph <- morph_df %>%
              dplyr::filter(`volume-mm3` != 0) %>%
              dplyr::select(name) %>%
              dplyr::arrange(name)

            morph_data(filtered_morph)
            filtered_morph_data(filtered_morph)  # Initialize filtered data with all data
            cat("Loaded", nrow(filtered_morph), "regions with non-zero volume\n")
          } else {
            cat("Warning: Expected columns 'name' and 'volume-mm3' not found in morph file\n")
            morph_data(NULL)
            filtered_morph_data(NULL)
          }
        } else {
          # NULL morph_df means volume=1 fallback
          # Read tacs file to get available region names for UI display
          cat("Using volume=1 for all regions (will be applied during region combination)\n")
          tryCatch({
            tacs_df <- readr::read_tsv(tacs_file, show_col_types = FALSE, n_max = 1)
            # Extract region names (exclude time columns)
            time_cols <- c("frame_start", "frame_end", "frame_dur", "frame_mid")
            region_cols <- setdiff(colnames(tacs_df), time_cols)

            if (length(region_cols) > 0) {
              # Create simple tibble with just region names (no volume-mm3 column)
              regions_for_display <- tibble::tibble(name = region_cols) %>%
                dplyr::arrange(name)

              morph_data(regions_for_display)
              filtered_morph_data(regions_for_display)
              cat("Loaded", nrow(regions_for_display), "regions from TACs file (volume=1 fallback)\n")
            } else {
              morph_data(NULL)
              filtered_morph_data(NULL)
            }
          }, error = function(e) {
            cat("Error reading TACs file for region names:", e$message, "\n")
            morph_data(NULL)
            filtered_morph_data(NULL)
          })
        }

        loaded_tacs_data(list(
          info = selected_info,
          details = parsed_details
        ))
      }
    })
    
    # Display TACs file information (only when TACs loaded)
    output$tacs_info <- renderText({
      req(input$load_tacs > 0)  # Only render when TACs loaded
      
      data <- loaded_tacs_data()
      if (is.null(data)) return("No file loaded")
      
      # info_text <- paste(
      #   "Selected File:", data$info$tacs_filedescription,
      #   "\nFolder:", data$info$foldername,
      #   "\nPath:", data$info$path,
      #   "\nDescription:", data$info$description,
      #   sep = ""
      # )
      
      return(info_text)
    })
    
    # Display TACs file information in sidebar
    output$tacs_info_sidebar <- renderText({
      data <- loaded_tacs_data()
      morph_df <- morph_data()

      if (is.null(data)) return("No file loaded")

      # Extract useful information from first row only
      pipeline <- data$info$foldername[1] %||% "Unknown"
      segmentation <- data$info$description[1] %||% "Unknown"

      # Count available regions
      n_regions <- if (!is.null(morph_df) && nrow(morph_df) > 0) {
        nrow(morph_df)
      } else {
        0
      }

      # Check if using volume=1 fallback (first row only)
      has_morph <- !is.na(data$info$morph_path[1])
      volume_info <- if (has_morph) "Matched morph file" else "Using volume=1 fallback"

      info_text <- paste(
        "Pipeline:", pipeline,
        "\nSegmentation:", segmentation,
        "\nAvailable regions:", n_regions,
        "\n", volume_info,
        sep = ""
      )

      return(info_text)
    })
    
    # Display parsed data (only when TACs loaded)
    output$parsed_data <- DT::renderDataTable({
      req(input$load_tacs > 0)  # Only render when TACs loaded
      
      data <- loaded_tacs_data()
      if (is.null(data) || is.null(data$details)) {
        return(data.frame(Message = "No data to display"))
      }
      
      DT::datatable(data$details, options = list(scrollX = TRUE))
    })
    
    # Display available columns
    output$available_columns <- renderText({
      req(input$load_tacs > 0)  # Only render when TACs loaded
      
      data <- loaded_tacs_data()
      if (is.null(data) || is.null(data$details)) return("No columns available")
      
      cols <- colnames(data$details)
      paste("Available columns:\n", paste(cols, collapse = ", "))
    })
    
    # Display defined regions in a simple table
    output$defined_regions_table <- renderTable({
      regions_data <- defined_regions_data()
      if (is.null(regions_data) || nrow(regions_data) == 0) {
        return(data.frame(Message = "No regions defined yet."))
      }
      
      # Sort by RegionName, then description, then ConstituentRegion
      sorted_data <- regions_data %>%
        dplyr::arrange(RegionName, description, ConstituentRegion) %>%
        dplyr::mutate(RegionName = paste0("<b>", RegionName, "</b>"))
      
      return(sorted_data)
    }, sanitize.text.function = function(x) x)
    
    # Show error message for duplicate names or missing names for combined regions
    duplicate_error <- reactiveVal(FALSE)
    multiple_regions_error <- reactiveVal(FALSE)
    
    output$region_name_error <- renderUI({
      if (duplicate_error() && !multiple_regions_error()) {
        div(style = "color: red; font-size: 12px; margin-top: 5px;",
            "⚠ This region name already exists!")
      } else if (multiple_regions_error()) {
        div(style = "color: red; font-size: 12px; margin-top: 5px;",
            "⚠ Please choose a new name for combined regions")
      } else {
        NULL
      }
    })
    
    # Add region
    observeEvent(input$add_region, {
      # Get selected checkboxes from ALL regions (both filtered and previously selected)
      full_morph_df <- morph_data()
      if (is.null(full_morph_df) || nrow(full_morph_df) == 0) {
        showNotification("No regions available to add", type = "warning")
        return()
      }
      
      selected_regions <- c()
      for (i in 1:nrow(full_morph_df)) {
        checkbox_id <- paste0("region_", i)
        if (!is.null(input[[checkbox_id]]) && input[[checkbox_id]]) {
          selected_regions <- c(selected_regions, full_morph_df$name[i])
        }
      }
      
      if (length(selected_regions) == 0) {
        showNotification("Please select at least one region", type = "warning")
        return()
      }
      
      # Determine region name: use input if provided, otherwise use original name for single selection
      region_name_to_use <- if (input$region_name == "" && length(selected_regions) == 1) {
        selected_regions[1]
      } else if (input$region_name == "") {
        # Show red error text for multiple regions without name
        multiple_regions_error(TRUE)
        duplicate_error(FALSE)
        return()
      } else {
        input$region_name
      }
      
      # Check for duplicate region names
      current_data <- defined_regions_data()
      if (!is.null(current_data) && nrow(current_data) > 0 && region_name_to_use %in% current_data$RegionName) {
        duplicate_error(TRUE)
        multiple_regions_error(FALSE)
        return()
      }
      
      # Clear any previous errors
      duplicate_error(FALSE)
      multiple_regions_error(FALSE)
      
      if (is.null(input$selected_tacs) || input$selected_tacs == "") {
        showNotification("Please select a TACs file first", type = "warning")
        return()
      }
      
      # Parse the selected TACs to extract folder and description
      tacs_parts <- stringr::str_split(input$selected_tacs, ": ", n = 2)[[1]]
      folder_name <- tacs_parts[1]
      description_part <- if(length(tacs_parts) > 1) tacs_parts[2] else ""
      
      # Create new rows for the TSV
      new_rows <- tibble::tibble(
        RegionName = rep(region_name_to_use, length(selected_regions)),
        folder = rep(folder_name, length(selected_regions)),
        description = rep(description_part, length(selected_regions)),
        ConstituentRegion = selected_regions
      )
      
      # Add to existing data
      if (is.null(current_data) || nrow(current_data) == 0) {
        updated_data <- new_rows
      } else {
        updated_data <- dplyr::bind_rows(current_data, new_rows)
      }
      
      # Save to file
      readr::write_tsv(updated_data, write_regions_file)
      
      # Update reactive value - this triggers reactive updates
      defined_regions_data(updated_data)
      
      # Mark that file is no longer empty
      originally_empty(FALSE)
      
      # Clear region name input and any errors
      updateTextInput(session, "region_name", value = "")
      duplicate_error(FALSE)
      multiple_regions_error(FALSE)
      
      # Clear all checkboxes (both filtered and previously selected)
      for (i in 1:nrow(full_morph_df)) {
        checkbox_id <- paste0("region_", i)
        updateCheckboxInput(session, checkbox_id, value = FALSE)
      }
      
      showNotification(paste("Added", length(selected_regions), "constituent regions for:", region_name_to_use), type = "message")
    })
    
    # Add all regions
    observeEvent(input$add_all_regions, {
      if (is.null(input$selected_tacs) || input$selected_tacs == "") {
        showNotification("Please select a TACs file first", type = "warning")
        return()
      }
      
      morph_df <- morph_data()  # Use full data, not filtered
      if (is.null(morph_df) || nrow(morph_df) == 0) {
        showNotification("No regions available to add", type = "warning")
        return()
      }
      
      # Parse the selected TACs to extract folder and description
      tacs_parts <- stringr::str_split(input$selected_tacs, ": ", n = 2)[[1]]
      folder_name <- tacs_parts[1]
      description_part <- if(length(tacs_parts) > 1) tacs_parts[2] else ""
      
      # Create rows for all regions using their original names
      new_rows <- tibble::tibble(
        RegionName = morph_df$name,
        folder = rep(folder_name, nrow(morph_df)),
        description = rep(description_part, nrow(morph_df)),
        ConstituentRegion = morph_df$name
      )
      
      # Add to existing data
      current_data <- defined_regions_data()
      if (is.null(current_data) || nrow(current_data) == 0) {
        updated_data <- new_rows
      } else {
        updated_data <- dplyr::bind_rows(current_data, new_rows)
      }
      
      # Save to file
      readr::write_tsv(updated_data, write_regions_file)
      
      # Update reactive value - this triggers reactive updates
      defined_regions_data(updated_data)
      
      # Mark that file is no longer empty
      originally_empty(FALSE)
      
      showNotification(paste("Added all", nrow(morph_df), "regions with original names"), type = "message")
    })
    
    # Remove region
    observeEvent(input$remove_region, {
      if (input$region_name == "") {
        showNotification("Please enter a region name to remove", type = "warning")
        return()
      }
      
      current_data <- defined_regions_data()
      if (is.null(current_data) || nrow(current_data) == 0) {
        showNotification("No regions defined to remove", type = "warning")
        return()
      }
      
      # Check if region exists
      if (!input$region_name %in% current_data$RegionName) {
        showNotification("Region name not found", type = "warning")
        return()
      }
      
      # Remove all rows with the specified region name
      updated_data <- current_data %>%
        dplyr::filter(RegionName != input$region_name)
      
      # Count removed rows
      removed_count <- nrow(current_data) - nrow(updated_data)
      
      # Save to file
      readr::write_tsv(updated_data, write_regions_file)
      
      # Update reactive value
      defined_regions_data(updated_data)
      
      # Clear region name input
      updateTextInput(session, "region_name", value = "")
      
      showNotification(paste("Removed", removed_count, "rows for region:", input$region_name), type = "message")
    })
    
    # Remove all regions
    observeEvent(input$remove_all_regions, {
      current_data <- defined_regions_data()
      if (is.null(current_data) || nrow(current_data) == 0) {
        showNotification("No regions defined to remove", type = "warning")
        return()
      }
      
      # Count total rows to be removed
      total_rows <- nrow(current_data)
      
      # Create empty data frame with proper structure
      empty_data <- tibble::tibble(
        RegionName = character(0),
        folder = character(0),
        description = character(0),
        ConstituentRegion = character(0)
      )
      
      # Save empty file
      readr::write_tsv(empty_data, write_regions_file)
      
      # Update reactive value
      defined_regions_data(empty_data)
      
      # Clear region name input
      updateTextInput(session, "region_name", value = "")
      
      showNotification(paste("Removed all", total_rows, "region definitions"), type = "message")
    })
    
    # Handle select all visible checkbox
    observeEvent(input$select_all_visible, {
      filtered_morph_df <- filtered_morph_data()
      full_morph_df <- morph_data()

      if (is.null(filtered_morph_df) || nrow(filtered_morph_df) == 0 ||
          is.null(full_morph_df) || nrow(full_morph_df) == 0) {
        return()
      }

      # Get currently selected regions
      selected_region_names <- c()
      for (i in 1:nrow(full_morph_df)) {
        checkbox_id <- paste0("region_", i)
        if (!is.null(input[[checkbox_id]]) && input[[checkbox_id]]) {
          selected_region_names <- c(selected_region_names, full_morph_df$name[i])
        }
      }

      # Get unselected filtered regions
      filtered_names <- filtered_morph_df$name
      unselected_filtered_names <- setdiff(filtered_names, selected_region_names)

      # Update only the UNSELECTED filtered region checkboxes
      for (region_name in unselected_filtered_names) {
        orig_idx <- which(full_morph_df$name == region_name)
        checkbox_id <- paste0("region_", orig_idx)
        updateCheckboxInput(session, checkbox_id, value = input$select_all_visible)
      }
    })

    # Handle reset selected regions button
    observeEvent(input$reset_selected, {
      full_morph_df <- morph_data()

      if (is.null(full_morph_df) || nrow(full_morph_df) == 0) {
        return()
      }

      # Deselect all checkboxes
      for (i in 1:nrow(full_morph_df)) {
        checkbox_id <- paste0("region_", i)
        updateCheckboxInput(session, checkbox_id, value = FALSE)
      }

      showNotification("All regions deselected", type = "message", duration = 2)
    })

    # Update select all checkbox based on individual selections
    observe({
      filtered_morph_df <- filtered_morph_data()
      full_morph_df <- morph_data()
      
      if (is.null(filtered_morph_df) || nrow(filtered_morph_df) == 0 || 
          is.null(full_morph_df) || nrow(full_morph_df) == 0) {
        return()
      }
      
      # Get currently selected regions
      selected_region_names <- c()
      for (i in 1:nrow(full_morph_df)) {
        checkbox_id <- paste0("region_", i)
        if (!is.null(input[[checkbox_id]]) && input[[checkbox_id]]) {
          selected_region_names <- c(selected_region_names, full_morph_df$name[i])
        }
      }
      
      # Get unselected filtered regions
      filtered_names <- filtered_morph_df$name
      unselected_filtered_names <- setdiff(filtered_names, selected_region_names)
      
      # Update select all checkbox state (should be checked only if no unselected filtered regions remain)
      all_unselected_filtered_selected <- length(unselected_filtered_names) == 0
      if (!is.null(input$select_all_visible) && input$select_all_visible != all_unselected_filtered_selected) {
        updateCheckboxInput(session, "select_all_visible", value = all_unselected_filtered_selected)
      }
    })
    
    # Generate Combined TACs
    observeEvent(input$generate_tacs, {
      # Check if there are defined regions
      current_data <- defined_regions_data()
      if (is.null(current_data) || nrow(current_data) == 0) {
        showNotification("No regions defined. Please add regions first.", 
                        type = "warning", duration = 5)
        return()
      }
      
      tryCatch({
        # Show processing notification that stays visible during processing
        processing_id <- showNotification(HTML("Generating combined TACs.<br>Please wait..."), 
                        type = "message", duration = NULL, id = "processing_tacs")
        
        # Step 1: Create file mapping
        petfit_regions_file <- write_regions_file
        derivatives_folder <- normalizePath(derivatives_dir, mustWork = FALSE)
        
        cat("Creating file mapping...\n")
        regions_files_data <- create_petfit_regions_files(petfit_regions_file, derivatives_folder)
        
        # Step 2: Process all regions
        petfit_regions_files_path <- file.path(write_config_dir, "petfit_regions_files.tsv")
        combined_output_folder <- file.path(derivatives_dir, petfit_output_foldername)
        
        cat("Processing all regions...\n")
        
        # Use consolidated TACs creation instead of separate files
        combined_data <- create_petfit_combined_tacs(petfit_regions_files_path, derivatives_folder, combined_output_folder, bids_dir, participant_data)
        
        # Show success notification with summary  
        total_rows <- nrow(combined_data)
        total_regions <- length(unique(combined_data$region))
        total_subjects <- length(unique(combined_data$sub))
        
        success_msg <- paste0(
          "Successfully created consolidated TACs file. ",
          "Total rows: ", total_rows, ", ",
          "Regions: ", total_regions, ", ",
          "Subjects: ", total_subjects, ". ",
          "Output: desc-combinedregions_tacs.tsv in ", combined_output_folder
        )
        
        showNotification(success_msg, type = "message", duration = 5)
        
        cat("=== Combined TACs Generation Complete ===\n")
        cat("Total rows:", total_rows, "\n")
        cat("Total regions:", total_regions, "\n")
        cat("Subjects processed:", total_subjects, "\n")
        cat("Output folder:", combined_output_folder, "\n")
        
        # Remove processing notification and show success
        removeNotification("processing_tacs")
        
        # Close app after 5 seconds to allow user to see success message
        later::later(function() {
          shiny::stopApp()
        }, delay = 5)
        
      }, error = function(e) {
        # Remove processing notification on error
        removeNotification("processing_tacs")
        
        error_msg <- paste("Error generating combined TACs:", e$message)
        showNotification(error_msg, type = "error", duration = 10)
        cat("Error:", e$message, "\n")
      })
    })
  }
  
  # Create the application
  app <- shiny::shinyApp(ui = ui, server = server)
  
  # Run with Docker-compatible settings
  cat("Please open the address on the following line in your web browser.\n")
  cat("If that doesn't work, use the address from the next line:\n")
  cat("http://localhost:3838\n")
  shiny::runApp(app, host = "0.0.0.0", port = 3838)
}
