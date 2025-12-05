#' Generate Input Files for CRSS
#'
#' This script generates the required input files for CRSS for each SOW in the
#' sampled SOW ensemble. The inputs include:
#'   * Flow files for 29 inflow points
#'   * An Upper Basin (UB) demand file
#'   * Initial condition (IC) files
#'
#' @details
#' Each SOW specifies:
#'   - **Powell and Mead elevations**: used to find the closest matching CRMMS
#'     run (minimizing Euclidean distance).
#'   - **Trace number**: used to locate and copy the corresponding CRSS flow
#'     files.
#'   - **Annual UB demand**: written directly to a UB demand input file.
#'
#' Once the best matching CRMMS run is identified for a SOW:
#'   1. The SOW's Powell and Mead elevations are retained.
#'   2. All other IC values (e.g., other reservoirs, bank storage, recent
#'      outflows) are taken from the matched CRMMS run.
#'   3. Using the values from (1) and (2), RiverWare IC input files are generated.
#'   4. A UB demand input file is generated.
#'   5. Flow input files assocated with the SOW's trace are copied from the 'raw 
#'      CRSS `data/raw/crss_flow_files` to the RiverSMART directory.
#'
#' @output
#'   - `RiverSMART/Model/Inputs/SystemConditionInput/traceX/`: IC + demand files
#'   - `RiverSMART/Model/Inputs/FlowInput/traceX/`: inflow files copied from
#'     CRSS source directories
#'
#' @seealso
#'   - [05_create_subsampled_ensemble.R] for the sampled SOW ensemble
#'   - CRMMS workbooks in `data/raw/eocy2026_crmms_data/` (ESP80/90/100)
#'   - CRSS flow files in `data/raw/crss_flow_files/`
#'
#' @note
#' Requires Excel CRMMS workbooks and raw CRSS flow files to be present in
#' `data/raw/`.

source(here::here("src", "utils", "install_packages.R"))

library(arrow)
library(dplyr)
library(magrittr)
library(readxl)

# ==============================================================================
# 1. Read in  Sampled SOW Data
# ==============================================================================
sampled_sow_info <- read_parquet(
  here::here("output", "05_create_subsampled_ensemble", "sampled_sow_info.parquet")
)

# ==============================================================================
# 2. Set Up Paths to CRMMS Data
# ==============================================================================
# Define the directory and file paths for the CRMMS data. These files contain
# data needed to initialize post-2026 CRSS runs.

data_dir <- here::here("data", "raw", "eocy2026_crmms_data")
crmms_workbooks <- c(
  file.path(data_dir, "CrmmsToCrss_Monthly_ESP80.xlsx"),
  file.path(data_dir, "CrmmsToCrss_Monthly_ESP90.xlsx"),
  file.path(data_dir, "CrmmsToCrss_Monthly_ESP100.xlsx")
)

# ==============================================================================
# 3. Initialize DataFrames for CRMMS Run Information
# ==============================================================================
# Prepare dataframes to store CRMMS slot names and initial conditions (ICs).
# These will hold the EOCY2026 data needed for the analysis.

# Extract slot names from the first workbook
slots <- names(data.frame(read_excel(crmms_workbooks[1])))[-1]

# Initialize the IC DataFrame
ic_df <- data.frame(Slot = slots)
rownames(ic_df) <- slots

# Create a DataFrame to track workbook-sheet combinations
workbook_sheet_index <- data.frame(matrix(nrow = 90, ncol = 2))
names(workbook_sheet_index) <- c("Workbook", "Sheet")

# ==============================================================================
# 4. Populate IC and Workbook-Sheet DataFrames
# ==============================================================================
# Loop through the CRMMS workbooks and sheets, extracting EOCY2026 data and 
# populating the initialized DataFrames.

counter <- 1
for (workbook in crmms_workbooks) {
  
  sheet_list <- excel_sheets(workbook)
  
  for (sheet in sheet_list) {
    # Read the data and process the sheet
    temp_df <- data.frame(read_excel(workbook, sheet))
    temp_df <- temp_df %>% set_rownames(temp_df[,1]) %>% select(-1)
    
    # Extract EOCY2026 values (December 2026)
    eocy2026 <- t(temp_df["2026-12-01", ])
    
    # Add EOCY2026 data to the IC DataFrame
    ic_df <- cbind(ic_df, eocy2026)
    
    # Record the workbook and sheet in the index
    workbook_sheet_index[counter, ] <- c(workbook, sheet)
    counter <- counter + 1
  }
}

# Finalize IC DataFrame with proper column names and remove the "Slot" column
ic_df <- ic_df %>% 
  set_colnames(0:(ncol(ic_df) - 1)) %>% 
  select(-1)

# ==============================================================================
# 5. Identify Best Matching ICs for Each SOW
# ==============================================================================
# For each SOW, identify the CRMMS run with EOCY2026 conditions closest to the
# SOW's initial conditions based on Euclidean distance.

## Extract Mead and Powell initial pool elevations for the sampled SOW ensemble
sampled_sow_ic <- sampled_sow_info %>% select(c(mead, powell))

# Extract Mead and Powell EOCY2026 conditions from the CRMMS IC DataFrame
crmms_ic <- data.frame(t(ic_df)) %>% 
  select(c(Mead.Pool.Elevation, Powell.Pool.Elevation)) %>% 
  set_colnames(names(sampled_sow_ic))

# Identify the closest CRMMS run for each SOW
closest_id <- sapply(1:nrow(sampled_sow_ic), function(i) {
  # Get the Mead and Powell ICs for the current SOW
  ic <- sampled_sow_ic[i, ]
  
  # Compute Euclidean distances between the SOW and all CRMMS runs
  distances <- apply(crmms_ic, MARGIN = 1, function(row) dist(rbind(ic, row)))
  
  # Return the index of the closest CRMMS run
  unname(which.min(distances))
})

# ==============================================================================
# 6. Generate Initial Condition and Demand Input Files for Each SOW
# ==============================================================================
# Create RiverWare initial condition input files based on the best matching
# CRMMS runs for each SOW.

output_dir <- here::here("RiverSMART", "Model", "Inputs", "SystemConditionInput")

for (i in 1:nrow(sampled_sow_ic)) {
  # Create folder for the current trace
  folder <- file.path(output_dir, paste0("trace", i))
  dir.create(folder, recursive = TRUE)
  
  # Retrieve workbook and sheet information for the best matching CRMMS run
  idx <- closest_id[i]
  workbook_path <- workbook_sheet_index[idx, "Workbook"]
  sheet <- workbook_sheet_index[idx, "Sheet"]
  
  # ----------------------------------------------------------------------------
  # Pool Elevation Slots
  # ----------------------------------------------------------------------------
  pool_slots <- c(
    "BlueMesa.Pool.Elevation", "Crystal.Pool.Elevation",
    "Fontenelle.Pool.Elevation", "Havasu.Pool.Elevation",
    "Mead.Pool.Elevation", "Mohave.Pool.Elevation",
    "MorrowPoint.Pool.Elevation", "Navajo.Pool.Elevation",
    "Powell.Pool.Elevation", "TaylorPark.Pool.Elevation"
  )
  
  for (slot in pool_slots) {
    elevation <- if (slot == "Mead.Pool.Elevation") {
      sampled_sow_info[[i, "mead"]]
    } else if (slot == "Powell.Pool.Elevation") {
      sampled_sow_info[[i, "powell"]]
    } else {
      ic_df[slot, idx]
    }
    
    writeLines(
      c("data_date: 2026-12-31 24:00", "units: ft", elevation), 
      file.path(folder, paste0(sub("\\..*", "", slot), ".poolelevation"))
    )
  }
  
  # ----------------------------------------------------------------------------
  # Bank Storage Slots
  # ----------------------------------------------------------------------------
  bank_slots <- c(
    "FlamingGorge.Bank.Storage", "Mead.Bank.Storage", "Powell.Bank.Storage"
  )
  
  for (slot in bank_slots) {
    writeLines(
      c("data_date: 2026-12-31 24:00", "units: acre-ft", ic_df[slot, idx]), 
      file.path(folder, paste0(sub("\\..*", "", slot), ".bankstorage"))
    )
  }
  
  # ----------------------------------------------------------------------------
  # Additional Slots with Multiple Timesteps
  # ----------------------------------------------------------------------------
  temp_df <- data.frame(read_excel(workbook_path, sheet))
  temp_df <- temp_df %>% set_rownames(temp_df[, 1]) %>% select(-1)
  
  # Powell Outflows (3 previous timesteps)
  powell_outflows <- temp_df[
    c("2026-10-01", "2026-11-01", "2026-12-01"), 
    "Powell.Outflow"
  ]
  writeLines(
    c("data_date: 2026-10-31 24:00", "units: acre-ft/month", powell_outflows), 
    file.path(folder, "Powell.outflow")
  )
  
  # Green River Above Flaming Gorge Outflows (6 previous timesteps)
  green_outflows <- temp_df[
    c("2026-07-01", "2026-08-01", "2026-09-01",
      "2026-10-01", "2026-11-01", "2026-12-01"), 
    "GreenRAboveFlamingGorge.Outflow"
  ]
  writeLines(
    c("data_date: 2026-07-31 24:00", "units: acre-ft/month", green_outflows), 
    file.path(folder, "GreenRAboveFlamingGorge.outflow")
  )
  
  # Flaming Gorge Pool Elevations (6 previous timesteps)
  flaminggorge_elevations <- temp_df[
    c("2026-07-01", "2026-08-01", "2026-09-01", 
      "2026-10-01", "2026-11-01", "2026-12-01"), 
    "FlamingGorge.Pool.Elevation"
  ]
  writeLines(
    c("data_date: 2026-07-31 24:00", "units: ft", flaminggorge_elevations), 
    file.path(folder, "FlamingGorge.poolelevation")
  )
  
  # ----------------------------------------------------------------------------
  # UB Demand Input File
  # ----------------------------------------------------------------------------
  writeLines(
    c("units: NONE", sampled_sow_info[[i, "demand"]]), 
    file.path(folder, "UB.demand")
  )
}

# ==============================================================================
# 7. Locate and Copy Flow Files to RiverSMART Directory for Each SOW
# ==============================================================================

src_dir <- here::here("data", "raw", "crss_flow_files")

output_dir <- here::here("RiverSMART", "Model", "Inputs", "FlowInput")

for (i in 1:nrow(sampled_sow_info)){
  
  # Identify the SOW's ensemble name and trace number
  ensemble <- sampled_sow_info$Scenario[i]
  trace_number <- sampled_sow_info$TraceNumber[i]
  
  # Determine source folder name based on ensemble name
  folder_name <- switch(
    ensemble,
    "stress_test" = "Stress Test",
    "cmip5" = "CMIP5",
    "npc_adjusted" = "NPC Adjusted",
    "paleo_drought" = "Paleo Drought Resampled",
    "npc_cmip3" = "NPC_MEKO_CMIP3_FULL"
  )
  
  from_folder <- file.path(src_dir, folder_name, paste0('trace', trace_number))
  to_folder <- file.path(output_dir, paste0('trace', i))
  
  # Create destination folder and copy files
  dir.create(to_folder, recursive=TRUE)
  
  files <- list.files(from_folder, full.name=TRUE)
  file.copy(from = files, to = to_folder)
  
}
