#If running for the first time, copy/paste everything after the first # below into the console (bottom left hand box)
#source("deploy_app_1st_time.R")


#First, start with a clean slate.
#Clear Workspace
#rm(list = ls())
#Clear Objects
#rm(list = ls(all.names = TRUE))
#free up memory and report the memory usage.
#gc()

# Global list of values that should persist across resets
persistent_values <- c("UMNH.VP.", "UMNH.IP.", "UMNH.PB.", "UMNH.MN.", 
                       "UMNH.VP.LOC.", "UMNH.IP.LOC.", "UMNH.PB.LOC.", 
                       "UMNH.MN.LOC.", "UMNH.A.", "UU.", "UUVP.", "UUIP.",
                       "UUPB.")

ui_title <- "Generic Data Entry Interface"

#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# Detect Environment: Local or ShinyApps.io
#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

is_shinyapps <- !is.na(Sys.getenv("SHINY_PORT", unset = NA)) || grepl("/srv/connect", getwd())

# Set base_dir based on environment
if (is_shinyapps) {
  base_dir <- getwd()  
  print("Running on ShinyApps.io")
} else {
  args <- commandArgs(trailingOnly = FALSE)
  script_path <- sub("--file=", "", args[grep("--file=", args)])
  
  if (length(script_path) > 0) {
    base_dir <- dirname(script_path)  
    setwd(base_dir)  
    print(paste("✅ Local mode: Working directory set to script location:", base_dir))
  } else {
    base_dir <- getwd()  
    print("⚠️ Warning: Script path not found. Using current working directory.")
  }
  
  print("Running locally")
}

print(paste("✅ Base directory set to:", base_dir))

#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# Load Required Packages
#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

library(shiny)
library(DT)
library(readxl)
library(fs)
library(dplyr)
library(openxlsx)
library(tidyxl)

#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# Load Word_Bank.xlsx and Generate Named Lists
#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

word_bank_file_path <- file.path(base_dir, "Word_Bank.xlsx")

# Define file path and sheet name
columns_sheet_name <- "Columns"  # Change if necessary

# Read entire sheet to determine row count
word_bank_columns <- read_excel(word_bank_file_path, sheet = columns_sheet_name, col_names = FALSE)
if (!file.exists(word_bank_file_path)) {
  stop(paste("Error: File 'Word_Bank' not found in", base_dir))
}

#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# Extract options for data validated dropdown lists of columns sheet
#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
#NOTE: In order for this code to work, col_names must be FALSE when importing this spreadsheet. 

# Extract Column A values dynamically
column_A_values <- word_bank_columns[[1]]  # First column in the sheet

# Read data validation rules
validations <- xlsx_validation(word_bank_file_path)

# Extract row numbers from cell references
dropdown_rows <- as.numeric(gsub(".*([0-9]+).*", "\\1", validations$ref))

# Extract corresponding values from Column A based on row numbers
dropdown_names <- column_A_values[dropdown_rows]

# Ensure valid names and add "Options_" prefix
dropdown_names <- paste0("Options_", dropdown_names)

# Extract dropdown lists from formula1
dropdown_list <- validations$formula1

# Clean and split dropdown values
dropdown_values <- lapply(dropdown_list, function(x) {
  gsub('^"|"$', '', x) |>  # Remove leading/trailing quotes
    strsplit(",") |>       # Split into individual values
    unlist() |>            # Convert list to vector
    trimws()               # Remove any extra spaces
})

# Assign proper names (fallback to 'Options_Unknown' if missing)
names(dropdown_values) <- ifelse(is.na(dropdown_names), "Options_Unknown", dropdown_names)

# Print structured dropdown data
print(dropdown_values)

#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# Extract data from columns spreadsheet
#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

# Extract metadata (Row labels & Column labels)
variable_names <- word_bank_columns[[1]]  
field_names <- as.character(word_bank_columns[1, -1])  

# Subset actual values (excluding first row and first column)
values_df <- word_bank_columns[-1, -1]
colnames(values_df) <- field_names  
values_df <- cbind(Variable_Name = variable_names[-1], values_df)  

# Initialize field_configuration
field_configuration <- list()

# Initialize lookup table storage
lookup_table_list <- list()

# Extract available sheets from the Excel file
available_sheets <- setdiff(excel_sheets(word_bank_file_path), columns_sheet_name)

# Populate field_configuration dynamically, ensuring Indexed_Output is included
for (i in seq_len(nrow(values_df))) {
  list_name <- values_df$Variable_Name[i]  
  if (!is.na(list_name) && list_name != "Options" && list_name != "") {
    field_configuration[[list_name]] <- as.list(setNames(values_df[i, -1], field_names))
    
    # Ensure Indexed_Output is captured if it exists
    if ("Indexed_Output" %in% field_names) {
      field_configuration$Indexed_Output <- as.list(setNames(values_df$Indexed_Output, values_df$Variable_Name))
    }
  }
}

# Handle "Options" as lists of valid choices
options_row_index <- which(variable_names == "Options")
if (!is.na(options_row_index) && length(options_row_index) > 0) {
  options_df <- values_df[(options_row_index - 1):nrow(values_df), -1, drop = FALSE]
  options_list <- list()
  
  for (field_name in names(options_df)) {
    options_field <- unique(na.omit(options_df[[field_name]]))
    
    # If options contain "Column=XYZ", extract values from XYZ column in Lookup_Table_Name
    column_match <- grep("^Column=", options_field, value = TRUE)
    if (length(column_match) > 0) {
      column_name <- sub("^Column=", "", column_match[1])  # Extract actual column name
      
      # Ensure the lookup table is properly referenced
      lookup_table <- field_configuration$Lookup_Table_Name[[field_name]]
      
      if (!is.null(lookup_table) && lookup_table != "" && lookup_table %in% available_sheets) {
        lookup_data <- read_excel(word_bank_file_path, sheet = lookup_table, col_names = TRUE)
        
        if (column_name %in% colnames(lookup_data)) {
          extracted_options <- unique(na.omit(lookup_data[[column_name]]))
          options_list[[field_name]] <- extracted_options
          print(paste("✅ Extracted dropdown options from column", column_name, "in", lookup_table, "for", field_name))
        } else {
          print(paste("⚠️ Column", column_name, "not found in lookup table", lookup_table, "for", field_name))
        }
      } else {
        print(paste("⚠️ Lookup Table for", column_name, "not found for field", field_name))
      }
    } else {
      options_list[[field_name]] <- options_field  # Store direct list of options
    }
  }
  field_configuration$Options <- options_list
}

# Locate the row index where "Options" appears in Column 1
options_row_index <- which(values_df[[1]] == "Options")

if (length(options_row_index) > 0) {
  # Extract the values in the "Options" row for each field (excluding the first column)
  options_values <- values_df[options_row_index, -1, drop = FALSE]  # Keep all field values except Column 1
  
  # Convert the row into a named list where:
  #   - Keys = field names (column headers)
  #   - Values = actual content from the "Options" row
  field_configuration$Options_Verbatim <- as.list(setNames(as.character(unlist(options_values)), colnames(values_df)[-1]))
  
  print("✅ field_configuration$Options_Verbatim successfully created!")
} else {
  print("⚠️ WARNING: 'Options' row not found in values_df. Initializing empty Options_Verbatim.")
  field_configuration$Options_Verbatim <- list()  # Prevent NULL errors
}

# Ensure critical lists exist
field_configuration$Data_Specificity <- field_configuration$Data_Specificity %||% list()
field_configuration$Front_End_Name <- as.list(setNames(as.character(unlist(field_configuration$Front_End_Name)), names(field_configuration$Front_End_Name)))
field_configuration$Field_Type <- as.list(setNames(as.character(unlist(field_configuration$Field_Type)), names(field_configuration$Field_Type)))

# Iterate over fields and map them to their corresponding lookup table
for (field_name in names(field_configuration$Front_End_Name)) {
  lookup_table <- field_configuration$Lookup_Table_Name[[field_name]]
  lookup_from <- field_configuration$Lookup_From[[field_name]]
  options_field <- field_configuration$Options[[field_name]]
  
  # Case 1: Handle direct Lookup_From field references
  if (!is.null(lookup_table) && lookup_table %in% available_sheets) {
    print(paste("✅ Using Lookup Table:", lookup_table, "for field:", field_name))
    
    # Read lookup table
    lookup_data <- read_excel(word_bank_file_path, sheet = lookup_table, col_names = TRUE)
    
    # If Lookup_From specifies a field (Field=Some_Field)
    if (!is.null(lookup_from) && grepl("^Field=", lookup_from)) {
      lookup_field <- sub("^Field=", "", lookup_from)  # Extract the field name
      
      if (lookup_field %in% colnames(lookup_data) && field_name %in% colnames(lookup_data)) {
        # Create a lookup map from one column to another
        lookup_map <- setNames(lookup_data[[field_name]], lookup_data[[lookup_field]])
        lookup_table_list[[field_name]] <- lookup_map
        print(paste("✅ Created lookup mapping from", lookup_field, "to", field_name))
      } else {
        print(paste("⚠️ Field", lookup_field, "or", field_name, "not found in lookup table", lookup_table))
      }
    } else {
      print(paste("⚠️ No valid 'Field=' entry in Lookup_From for", field_name))
    }
    
    # Case 2: Use Options as a direct list (Options should still start with Column=)
  } else if (!is.null(options_field)) {
    options_list <- as.character(unlist(options_field))
    direct_options <- options_list[!grepl("^Field=", options_list)]  # Ensure Field= is ignored for Options
    
    if (length(direct_options) > 0) {
      lookup_table_list[[field_name]] <- unique(na.omit(direct_options))
      print(paste("✅ Using direct options list for", field_name, ":", paste(direct_options, collapse = ", ")))
    }
  }
}


# Store lookup values in field_configuration
field_configuration$Lookup_Values <- lookup_table_list

# Store lookup values in field_configuration
field_configuration$Lookup_Values <- lookup_table_list

# Store lookup values in field_configuration
field_configuration$Lookup_Values <- lookup_table_list

# Replace empty strings and NULL values with NA
field_configuration$Front_End_Name[field_configuration$Front_End_Name == ""] <- NA
field_configuration$Field_Type[field_configuration$Field_Type == ""] <- NA

#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# Generate Input Fields
#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

generate_input_fields <- function(field_configuration, fields, ns) {
  num_fields <- length(fields)
  if (num_fields == 0) return(NULL)  # Exit if no fields are provided
  
  # Use as many columns as there are fields if less than 4; otherwise, use 4 columns
  num_columns <- min(4, num_fields)
  fields_per_col <- ceiling(num_fields / num_columns)
  
  input_columns <- lapply(seq_len(num_columns), function(i) {
    start <- (i - 1) * fields_per_col + 1
    end   <- min(i * fields_per_col, num_fields)
    
    column(12 / num_columns,  
           lapply(seq(start, end), function(j) {
             field_name <- fields[j]
             
             # Wrap the field name using ns() for proper namespacing
             inputId <- ns(field_name)
             
             # Extract field properties
             front_end_name <- field_configuration$Front_End_Name[[field_name]]
             field_type <- field_configuration$Field_Type[[field_name]]
             default_internal <- field_configuration$Default_Choice_Internal[[field_name]] %||% ""
             default_external <- field_configuration$Default_Choice_External[[field_name]] %||% ""
             example_text <- field_configuration$Example[[field_name]]
             
             # Determine dropdown options
             dropdown_options <- field_configuration$Lookup_Values[[field_name]] %||% field_configuration$Options[[field_name]]
             dropdown_options <- unique(na.omit(dropdown_options))
             if (length(dropdown_options) == 0 || is.null(dropdown_options)) {
               dropdown_options <- c()
             }
             
             # Skip if field is hidden
             if (is.null(field_type) || is.na(field_type) || field_type %in% c("NA", "Backend")) {
               return(NULL)
             }
             
             if (is.null(front_end_name) || is.na(front_end_name)) front_end_name <- field_name
             if (length(field_type) == 0 || is.na(field_type)) {
               field_type <- "Short_Answer"
             }
             
             # Build the UI element based on the field type
             input_field <- switch(field_type,
                                   "Selection" = selectInput(
                                     inputId = inputId,
                                     label = front_end_name,
                                     choices = c("", dropdown_options),
                                     selected = ""
                                   ),
                                   "Selection+" = selectizeInput(
                                     inputId = inputId,
                                     label = front_end_name,
                                     choices = c("", dropdown_options),
                                     selected = "",
                                     options = list(create = TRUE)
                                   ),
                                   "Checkbox" = checkboxInput(inputId, front_end_name, value = FALSE),
                                   "Date" = dateInput(
                                     inputId,
                                     front_end_name,
                                     value = NA,
                                     format = "dd-mm-yyyy"
                                   ),
                                   "Person" = textInput(inputId, front_end_name, value = ""),
                                   "Number" = numericInput(
                                     inputId, 
                                     front_end_name, 
                                     value = NA,
                                     min = 0
                                   ),
                                   "Short_Answer" = textInput(inputId, front_end_name, value = ""),
                                   textInput(inputId, front_end_name, value = "") # default fallback
             )
             
             if (!is.null(example_text) && !is.na(example_text) && example_text != "") {
               tagList(
                 input_field,
                 div(style = "margin-top: -15px;", helpText(paste("Example:", example_text)))
               )
             } else {
               input_field
             }
           })
    )
  })
  
  fluidRow(input_columns)
}

#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# Group UI
#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

generate_grouped_ui <- function(field_configuration, ns) {
  # Use the extracted dropdown list for Data_Specificity
  reset_levels <- dropdown_values[["Options_Data_Specificity"]]
  
  # Extract Data_Specificity values safely
  reset_freqs <- field_configuration$Data_Specificity %||% list()
  
  # Organize fields by Data_Specificity (Remove duplicates)
  grouped_fields <- setNames(
    lapply(reset_levels, function(level) {
      unique(names(reset_freqs)[reset_freqs == level])
    }),
    reset_levels
  )
  
  # Define hierarchy for resetting (excluding "Never")
  reset_hierarchy <- gsub("^Per ", "", reset_levels[reset_levels != "Never"])
  
  generate_section <- function(fields, section_name) {
    if (length(fields) == 0) return(NULL)
    button_label <- paste("Move on to next", section_name)
    
    # Determine which levels to reset when this button is pressed
    reset_levels_above <- character(0)
    if (section_name %in% reset_hierarchy) {
      reset_index <- which(reset_hierarchy == section_name)
      if (length(reset_index) > 0 && reset_index > 0) {
        reset_levels_above <- reset_hierarchy[seq_len(reset_index)]
      }
    }
    
    section_ui <- list(
      tags$hr(style = "border-top: 3px solid #333; margin: 30px 0;"),
      h3(section_name, style = "font-weight: bold; text-align: center;")
    )
    
    if (section_name != "Never") {
      section_ui <- c(section_ui, list(
        actionButton(ns(paste0("move_next_", gsub(" ", "_", tolower(section_name)))),
                     label = button_label,
                     style = "margin-bottom: 15px; width: 100%;")
      ))
    }
    
    # Generate the input fields with proper namespacing
    input_fields <- generate_input_fields(field_configuration, fields, ns)
    if (!is.null(input_fields)) {
      section_ui <- c(section_ui, list(input_fields))
    }
    
    section_ui
  }
  
  ui_sections <- Filter(Negate(is.null), Map(generate_section, grouped_fields, names(grouped_fields)))
  do.call(tagList, ui_sections)
}



safe_normalize_path <- function(path) {
  tryCatch(
    normalizePath(path.expand(path), winslash = "/", mustWork = FALSE),
    error = function(e) {
      warning(paste("Path normalization failed for:", path))
      return(path)  
    }
  )
}

#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# Define UI
#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

data_entry_ui <- function(id, field_configuration) {
  ns <- NS(id)
  
  fluidPage(
    titlePanel(ui_title),
    
    tabsetPanel(
      tabPanel("Data Entry",
               # Data Entry Form Section
               fluidRow(
                 column(4, checkboxInput(ns("institution_internal"), "Use Internal Presets", value = TRUE)),
                 column(4, checkboxInput(ns("maintain_prefixes"), "Maintain Prefixes", value = TRUE)),
                 column(4, checkboxInput(ns("use_hierarchical_entry"), "Use Hierarchical Data Entry", value = TRUE))
               ),
               
               # Generate grouped UI fields with namespaced IDs
               generate_grouped_ui(field_configuration, ns),
               
               # Entered Data Section
               tags$hr(style = "border-top: 3px solid #333; margin: 30px 0;"),
               h3("Entered Data", style = "font-weight: bold; text-align: center;"),
               fluidRow(
                 column(12,
                        actionButton(ns("delete_entry"), "Delete Selected Entry"),
                        downloadButton(ns("download"), "Download Data")
                 )
               ),
               # Note: The condition in conditionalPanel is JavaScript-based.
               # We need to reference the namespaced output properly.
               conditionalPanel(
                 condition = sprintf("output['%s'] === true", ns("data_empty")),
                 h4("No entries yet. Please fill in the Data Entry Form above.")
               ),
               DTOutput(ns("data_table"))
      )
    ),
    
    verbatimTextOutput(ns("notification")),
    
    # Bottom Spacer to Ensure Dropdowns Have Room
    tags$div(style = "height: 150px;")
  )
}



#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# Define Server Logic
#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

data_entry_server <- function(id, word_bank_file_path, field_configuration, dropdown_values, persistent_values, available_sheets) {
  moduleServer(id, function(input, output, session) {
    
    # Reactive storage for data entries and notifications
    data <- reactiveVal(data.frame(stringsAsFactors = FALSE))
    notification <- reactiveVal("")
    
    # Reactive storage for lookup tables (loaded once on startup)
    lookup_data_list <- reactiveVal(list())
    
    # -------------------------------
    # Observer: Update default choices
    # -------------------------------
    observe({
      if (is.null(input$institution_internal)) return()
      
      use_internal <- input$institution_internal
      if (is.null(field_configuration$Front_End_Name) || length(field_configuration$Front_End_Name) == 0) return()
      
      for (field_name in names(field_configuration$Front_End_Name)) {
        internal_default <- field_configuration$Default_Choice_Internal[[field_name]] %||% ""
        external_default <- field_configuration$Default_Choice_External[[field_name]] %||% ""
        default_value <- if (use_internal) internal_default else external_default
        
        if (!is.null(field_configuration$Field_Type[[field_name]])) {
          field_type <- field_configuration$Field_Type[[field_name]]
          
          if (field_type %in% c("Selection", "Selection+")) {
            updateSelectInput(session, field_name, selected = default_value)
          } else if (field_type %in% c("Short_Answer", "Person")) {
            updateTextInput(session, field_name, value = default_value)
          } else if (field_type == "Number") {
            updateNumericInput(session, field_name, value = suppressWarnings(as.numeric(default_value)))
          }
        }
      }
    })
    
    output$data_empty <- reactive({ nrow(data()) == 0 })
    outputOptions(output, "data_empty", suspendWhenHidden = FALSE)
    
    # -------------------------------
    # Reset and Save Functions
    # -------------------------------
    reset_full_list <- dropdown_values[["Options_Data_Specificity"]]
    reset_hierarchy <- setdiff(reset_full_list, c("NA", "Never"))
    lapply(reset_hierarchy, function(level) {
      observeEvent(input[[paste0("move_next_", tolower(level))]], {
        save_and_reset(level)
      })
    })
    
    save_data <- function() {
      valid_fields <- intersect(names(field_configuration$Front_End_Name), names(input))
      
      new_entry <- as.data.frame(lapply(valid_fields, function(col) {
        val <- input[[col]]
        if (is.null(val) || length(val) == 0) return(NA)
        
        # Extract lookup details
        lookup_table <- field_configuration$Lookup_Table_Name[[col]]  
        options_verbatim <- field_configuration$Options_Verbatim[[col]]  
        indexed_output_col <- field_configuration$Indexed_Output[[col]]  
        
        # If no Indexed Output is needed, store the user's selection directly
        if (is.null(indexed_output_col) || is.na(indexed_output_col) || indexed_output_col == "") {
          return(val)
        }
        
        # Extract the lookup column from Options_Verbatim
        if (!is.null(options_verbatim) && grepl("^Column=", options_verbatim)) {
          lookup_from_col <- sub("^Column=", "", options_verbatim)
        } else {
          return(val)  
        }
        
        # Ensure lookup table exists
        if (!is.null(lookup_table) && lookup_table %in% available_sheets) {
          lookup_data <- lookup_data_list()[[lookup_table]]
          
          # Ensure lookup data and columns exist
          if (!is.null(lookup_data) && lookup_from_col %in% colnames(lookup_data)) {
            
            # Match user selection with the lookup_from_col
            matched_rows <- lookup_data[lookup_data[[lookup_from_col]] == val, , drop = FALSE]
            
            # Extract the Indexed Output column name
            lookup_col <- sub("^Column=", "", indexed_output_col)
            
            # Ensure Indexed Output column exists in lookup table
            if (lookup_col %in% colnames(lookup_data) && nrow(matched_rows) > 0) {
              return(matched_rows[[lookup_col]][1])
            }
          }
        }
        
        return(val)  # Return original selection if no match found
      }), stringsAsFactors = FALSE)
      
      colnames(new_entry) <- valid_fields
      
      if (nrow(new_entry) > 0) {
        data(rbind(data(), new_entry))
        notification("✅ Data entered successfully.")
      } else {
        notification("⚠️ Error: No valid data entered.")
      }
    }
    
    
    save_and_reset <- function(trigger_level) {
      print(paste("🔄 Reset triggered for:", trigger_level))
      save_data()
      
      reset_full_list <- dropdown_values[["Options_Data_Specificity"]]
      reset_hierarchy <- setdiff(reset_full_list, c("NA", "Never"))
      use_hierarchy <- isTRUE(input$use_hierarchical_entry)
      reset_levels_above <- character(0)
      if (use_hierarchy && !is.null(trigger_level) && trigger_level %in% reset_hierarchy) {
        reset_index <- which(reset_hierarchy == trigger_level)
        if (length(reset_index) > 0 && reset_index > 0) {
          reset_levels_above <- reset_hierarchy[seq_len(reset_index)]
        }
      } else {
        reset_levels_above <- reset_hierarchy
      }
      print(paste("🔄 Resetting levels:", paste(reset_levels_above, collapse = ", ")))
      maintain_prefixes <- isTRUE(input$maintain_prefixes)
      for (level in reset_levels_above) {
        fields_to_reset <- names(field_configuration$Data_Specificity[field_configuration$Data_Specificity == level])
        for (field in fields_to_reset) {
          current_value <- input[[field]]
          if (is.null(current_value) || is.na(current_value) || !is.character(current_value))
            current_value <- ""
          persistent_part <- NA
          if (maintain_prefixes) {
            matching_persistent_values <- persistent_values[startsWith(current_value, persistent_values)]
            if (length(matching_persistent_values) > 0) {
              persistent_part <- matching_persistent_values[which.max(nchar(matching_persistent_values))]
            }
          }
          if (!is.na(persistent_part) && nzchar(persistent_part)) {
            updateTextInput(session, field, value = persistent_part)
          } else {
            updateTextInput(session, field, value = "")
            updateNumericInput(session, field, value = NULL)
            updateSelectInput(session, field, selected = NULL)
            updateDateInput(session, field, value = NULL)
          }
        }
      }
      notification(paste("✅ Moved on to next", gsub("^Per ", "", trigger_level), "& reset relevant fields."))
    }
    
    # -------------------------------
    # Load Lookup Tables
    # -------------------------------
    observe({
      lookup_tables <- list()
      for (table_name in unique(na.omit(field_configuration$Lookup_Table_Name))) {
        if (table_name %in% available_sheets) {
          lookup_tables[[table_name]] <- read_excel(word_bank_file_path, sheet = table_name, col_names = TRUE)
        }
      }
      lookup_data_list(lookup_tables)
      print("✅ Lookup tables loaded")
    })
    
    # -------------------------------
    # Auto-Fill / Lookup Observer
    # -------------------------------
    # Note: Because input IDs are automatically namespaced in modules,
    # you can refer to them by their base names as stored in field_configuration.
    lapply(names(field_configuration$Lookup_From), function(field_name) {
      lookup_table <- field_configuration$Lookup_Table_Name[[field_name]]
      lookup_from <- field_configuration$Lookup_From[[field_name]] %||% ""
      
      if (!is.null(lookup_from) && lookup_from != "" && grepl("^Field=", lookup_from)) {
        trigger_field <- sub("^Field=", "", lookup_from)
        cleaned_trigger_field <- sub("^(Fossil_|Matrix_Start_|Matrix_End_)", "", trigger_field)
        cleaned_field_name <- sub("^(Fossil_|Matrix_Start_|Matrix_End_)", "", field_name)
        
        observeEvent(input[[trigger_field]], {
          selected_value <- isolate(input[[trigger_field]])
          print(paste("🟢 Change detected:", trigger_field, "=", selected_value))
          if (!is.null(selected_value) && selected_value != "") {
            lookup_data <- lookup_data_list()[[lookup_table]]
            if (!is.null(lookup_data)) {
              print("Available columns in lookup table:")
              print(colnames(lookup_data))
              cleaned_colnames <- sub("^(Fossil_|Matrix_Start_|Matrix_End_)", "", colnames(lookup_data))
              names(lookup_data) <- cleaned_colnames
              possible_stage_columns <- c(cleaned_trigger_field, "Stage")
              matched_stage_column <- intersect(possible_stage_columns, colnames(lookup_data))
              possible_epoch_columns <- c(cleaned_field_name, "Epoch")
              matched_epoch_column <- intersect(possible_epoch_columns, colnames(lookup_data))
              
              if (length(matched_stage_column) > 0 && length(matched_epoch_column) > 0) {
                stage_col <- matched_stage_column[1]
                epoch_col <- matched_epoch_column[1]
                print(paste("🔍 Using columns:", stage_col, "->", epoch_col))
                lookup_data[[stage_col]] <- trimws(tolower(lookup_data[[stage_col]]))
                selected_value <- trimws(tolower(selected_value))
                matched_row <- lookup_data[!is.na(lookup_data[[stage_col]]) & lookup_data[[stage_col]] == selected_value, , drop = FALSE]
                print(paste("🔎 Matching row count:", nrow(matched_row)))
                if (nrow(matched_row) > 0) {
                  print("✅ Matched row data:")
                  print(matched_row)
                  new_value <- matched_row[[epoch_col]][1]
                  if (!is.null(new_value) && !is.na(new_value) && new_value != "") {
                    if (!is.null(input[[field_name]]) && input[[field_name]] == new_value) {
                      print(paste("🔁 Skipping redundant update for", field_name, "already set to", new_value))
                      return(NULL)
                    }
                    print(paste("🔄 Auto-filling", field_name, "with", new_value))
                    freezeReactiveValue(input, field_name)
                    updateTextInput(session, field_name, value = new_value)
                  } else {
                    print(paste("⚠️ No valid value found for", field_name))
                  }
                } else {
                  print(paste("⚠️ No match found in", lookup_table, "for", stage_col, "=", selected_value))
                }
              } else {
                print(paste("⚠️ Could not find Stage or Epoch columns in lookup table", lookup_table))
              }
            } else {
              print(paste("⚠️ Lookup table", lookup_table, "not found"))
            }
          }
        }, ignoreNULL = FALSE, ignoreInit = TRUE)
      }
    })
    
    # Observer: Automatically Look Up Indexed Output When Selection is Made
    observe({
      for (col in names(field_configuration$Indexed_Output)) {
        lookup_table <- field_configuration$Lookup_Table_Name[[col]]  # Expected "Individuals"
        options_col_entry <- field_configuration$Options[[col]]  # Expected "Column=People"
        indexed_output_col <- field_configuration$Indexed_Output[[col]]  # Expected "Column=IRN"
        
        # Ensure we have valid values
        if (is.null(indexed_output_col) || is.na(indexed_output_col) || indexed_output_col == "") {
          next  # Skip this field if Indexed_Output is missing
        }
        
        lookup_col <- sub("^Column=", "", indexed_output_col)  # Extract "IRN"
        lookup_from_col <- unique(sub("^Column=", "", options_col_entry))  # Ensure a single column name
        
        # If multiple column names exist, print a warning
        if (length(lookup_from_col) > 1) {
          print(paste("⚠️ WARNING: Multiple lookup columns found for", col, ":", paste(lookup_from_col, collapse=", ")))
          lookup_from_col <- lookup_from_col[1]  # Take only the first valid column
        }
        
        observeEvent(input[[col]], {
          selected_value <- input[[col]]  # The value the user selected
          print(paste("🟢 User Selected Value for", col, "=", selected_value))
          
          if (!is.null(selected_value) && selected_value != "") {
            lookup_data <- lookup_data_list()[[lookup_table]]
            
            if (!is.null(lookup_data) && lookup_from_col %in% colnames(lookup_data) && lookup_col %in% colnames(lookup_data)) {
              matched_rows <- lookup_data[lookup_data[[lookup_from_col]] == selected_value, , drop = FALSE]
              
              if (nrow(matched_rows) > 0 && !is.na(matched_rows[[lookup_col]][1])) {
                indexed_value <- matched_rows[[lookup_col]][1]
                print(paste("✅ Indexed Output for", col, ": Selected Value =", selected_value, "→ Indexed Value =", indexed_value))
              } else {
                print(paste("⚠️ No indexed match found for", selected_value, "in", lookup_table, "- Keeping original value."))
              }
            } else {
              print(paste("⚠️ Lookup table", lookup_table, "is missing required columns for", col))
            }
          }
        }, ignoreNULL = FALSE, ignoreInit = TRUE)
      }
    })
    
    
    # -------------------------------
    # Debug: Check Lookup Table Contents
    # -------------------------------
    observe({
      print("📂 Checking lookup table contents at startup...")
      for (table_name in unique(na.omit(field_configuration$Lookup_Table_Name))) {
        if (table_name %in% available_sheets) {
          lookup_data <- read_excel(word_bank_file_path, sheet = table_name, col_names = TRUE)
          print(paste("🔎 Lookup Table:", table_name))
          print(head(lookup_data))
        }
      }
    })
    
    # -------------------------------
    # Data Table and Edit/Delete
    # -------------------------------
    output$data_table <- DT::renderDT({
      df <- data()
      if (is.null(df) || nrow(df) == 0) {
        return(DT::datatable(data.frame(Message = "No data available"), options = list(dom = 't')))
      }
      
      # Remove empty columns (all NA or empty strings)
      df <- df[, colSums(!is.na(df) & df != "") > 0, drop = FALSE]
      
      DT::datatable(df, selection = "single", editable = "cell")
    })
    
    observeEvent(input$data_table_cell_edit, {
      info <- input$data_table_cell_edit
      df <- data()
      df[info$row, info$col] <- info$value
      data(df)
    })
    
    observeEvent(input$delete_entry, {
      selected <- input$data_table_rows_selected
      if (!is.null(selected) && length(selected) > 0) {
        df <- data()
        df <- df[-selected, , drop = FALSE]
        data(df)
        notification("✅ Entry deleted successfully.")
      } else {
        notification("⚠️ No entry selected for deletion.")
      }
    })
    
    output$download <- downloadHandler(
      filename = function() { "formatted_data.csv" },
      content = function(file) {
        df <- data()
        # Remove empty columns (all NA or empty strings)
        df <- df[, colSums(!is.na(df) & df != "") > 0, drop = FALSE]
        
        write.csv(df, file, row.names = FALSE)
      }
    )
    
    output$notification <- renderText({ notification() })
    
    # Return reactive values if needed by parent server
    return(list(
      data = data,
      notification = notification
    ))
  })
}

# Create the module UI using your custom UI function:
ui <- fluidPage(
  data_entry_ui("data_entry", field_configuration)
)

server <- function(input, output, session) {
  # Assume word_bank_file_path, field_configuration, dropdown_values, persistent_values, available_sheets
  # are defined or loaded here (perhaps in your query/word bank server module).
  data_entry_server("data_entry", word_bank_file_path, field_configuration, dropdown_values, persistent_values, available_sheets)
  
  # ... Additional server code for your query and word bank functionality
}


#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# Launch Shiny App
#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

shinyApp(ui, server)
