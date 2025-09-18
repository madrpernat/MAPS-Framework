#' Consolidate RiverSMART Re-Evaluation Objective Data
#'
#' @description
#' This script consolidates RiverSMART policy evaluation results across all
#' sampled States of the World (SOWs) into a single Parquet file. Each policy’s
#' annual objective values are extracted from RiverSMART output workbooks and
#' reshaped into a tidy format.
#'
#' @details
#' Workflow:
#'   1. Identify all policy scenario directories under `RiverSMART/Scenario/`.
#'   2. For each policy, read annual objective workbooks for a fixed set of
#'      objectives.
#'   3. Extract the final-year (row 360) values for all SOWs.
#'   4. Combine results into a tidy format dataframe with columns:
#'      * `Policy`: policy ID
#'      * `SOW`: state of the world index
#'      * `Objective`: objective name
#'      * `Value`: numeric value of the objective
#'   5. Save the consolidated dataset to a Parquet file for downstream analysis.
#'
#' @output
#' - `output/07_consolidate_rw_output/reevaluation_objectives.parquet`:
#'   tidy dataframe of all objective results across policies and SOWs
#'
#' @seealso
#'   - RiverSMART scenario results under `RiverSMART/Scenario/`

# ==============================================================================
# 1. Load Libraries
# ==============================================================================

library(readxl)
library(magrittr)
library(arrow)
library(dplyr)

# ==============================================================================
# 2. Define Directories and Scenario Settings
# ------------------------------------------------------------------------------
# The script expects RiverSMART results organized as:
#   RiverSMART/Scenario/policyX/Objectives.<Objective>_Annual.xlsx
# ==============================================================================

results_dir <- "RiverSMART/Scenario"
scenario_prefix <- "policy"

output_dir <- "output/07_consolidate_rw_output"
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# ==============================================================================
# 3. Define Objectives, SOWs, and Policies
# ==============================================================================

objectives <- c(
  "Avg_Annual_LB_Policy_Shortage",
  "Avg_Mead_PE",
  "Avg_Powell_PE",
  "LB_Shortage_Volume",
  "Lee_Ferry_Deficit",
  "Max_Delta_Annual_Shortage",
  "Mead_1000",
  "Mead_1020",
  "Powell_3490",
  "Powell_3525",
  "Powell_Release_LTEMP",
  "Powell_WY_Release",
  "Start_in_EQ"
)

sows <- 1:4250
n_sows <- length(sows)

# Policy IDs extracted from folder names (e.g., policy1, policy2, …)
policy_ids <- sub(
  pattern = scenario_prefix,
  replacement = "",
  x = list.dirs(results_dir, recursive = FALSE, full.names = FALSE)
)

# ==============================================================================
# 4. Extract Objectives for Each Policy for Each SOW
# ==============================================================================

dfs <- list()

for (i in policy_ids) {
  
  message("Processing Policy ", i)
  
  policy_dir <- file.path(results_dir, paste0(scenario_prefix, i))
  
  # Initialize dataframe for this policy
  policy_df <- data.frame(
    Policy    = character(n_sows * length(objectives)),
    SOW       = integer(n_sows * length(objectives)),
    Objective = character(n_sows * length(objectives)),
    Value     = numeric(n_sows * length(objectives)),
    stringsAsFactors = FALSE
  )
  
  # --------------------------------------------------------------------------
  # Loop through objectives
  # --------------------------------------------------------------------------
  for (objective in objectives) {
    
    # Read objective workbook (annual time series per SOW)
    values <- read_xlsx(
      path  = file.path(policy_dir, paste0("Objectives.", objective, "_Annual.xlsx")),
      sheet = 2
    )
    
    # Extract final simulation-year values (row 360, excluding first column)
    values <- as.double(values[360, ])[-1]
    
    # Insert into correct rows of dataframe
    start_idx <- (which(objectives == objective) - 1) * n_sows + 1
    end_idx   <- start_idx + n_sows - 1
    
    policy_df[start_idx:end_idx, ] <- data.frame(
      Policy    = rep(i, n_sows),
      SOW       = sows,
      Objective = rep(objective, n_sows),
      Value     = values
    )
  }
  
  dfs[[i]] <- policy_df
}

# ==============================================================================
# 5. Combine and Save Results
# ==============================================================================

combined_df <- bind_rows(dfs)

write_parquet(
  x = combined_df,
  sink = file.path(output_dir, "reevaluation_objectives.parquet")
)
