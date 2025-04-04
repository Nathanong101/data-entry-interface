# deploy_app_1st_time.R

# Clear Workspace
rm(list = ls(all.names = TRUE))
gc()

#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
  settings_account <- "REDACTED"
settings_app_name <- "generic_data_entry"
settings_token <- 'REDACTED'
settings_secret <- 'REDACTED'
settings_name <- settings_account
app_files <- c("Generic_Data_Entry_Apr3.R", "Word_Bank.xlsx")
app_primary_doc <- "Generic_Data_Entry_Apr3.R"

#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

# Detect Environment: Local or ShinyApps.io
is_shinyapps <- !is.na(Sys.getenv("SHINY_PORT", unset = NA)) || grepl("/srv/connect", getwd())

# Set `base_dir` for Local & ShinyApps.io
if (is_shinyapps) {
  base_dir <- getwd()  # ShinyApps.io root directory
  message("✅ Running on ShinyApps.io")
} else {
  args <- commandArgs(trailingOnly = FALSE)
  script_path <- sub("--file=", "", args[grep("--file=", args)])
  
  if (length(script_path) > 0) {
    base_dir <- dirname(script_path)
    setwd(base_dir)
    message("✅ Local mode: Working directory set to script location: ", base_dir)
  } else {
    base_dir <- getwd()
    message("⚠️ Warning: Script path not found. Using current working directory.")
  }
}

message("Running ", ifelse(is_shinyapps, "on ShinyApps.io", "locally"))
message("✅ Base directory set to: ", base_dir)

#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

# Set your shinyapps.io account credentials (only needed the first time)
rsconnect::setAccountInfo(name = settings_name,
                          token = settings_token,
                          secret = settings_secret)

# Deploy the application with only the required files
rsconnect::deployApp(appDir = base_dir, 
                     appName = settings_app_name,
                     account = settings_account,
                     appFiles = app_files,
                     appPrimaryDoc = app_primary_doc)

