#' Create Subsampled Ensemble of States of the World (SOWs)
#'
#' @description
#' This script:
#'   1. Loads full SOW metadata (`ff_sow_info`) and CFD time series (`ff_cfd`).
#'   2. Runs cLHS across all SOM neurons to select a representative subset.
#'   3. Saves metadata for sampled SOWs.
#'   4. Extracts and saves corresponding CFD (raw + scaled) and trace time
#'      series for only the sampled SOWs.
#'
#' @details
#' Outputs are saved in:
#'   - `output/05_create_subsampled_ensemble/`:
#'       * `sampled_sow_info.parquet` : metadata for sampled SOWs
#'       * `sampled_sow_cfd.parquet` : CFD time series (raw, subsetted)
#'       * `sampled_sow_cfd_min_max_scaled.parquet` : CFD time series (scaled, subsetted)
#'       * `sampled_sow_traces_timeseries.parquet` : trace time series (subsetted)
#'
#' @seealso
#'   - [04_som_subsampling_experiment.R] for prior analysis and selection of sample size
#'   - [som_library.R] for helper functions used in subsampling

# ==============================================================================
# 1. Load Libraries and Utility Functions
# ==============================================================================

source(here::here("src", "utils", "install_packages.R"))

source(here::here("src", "utils", "som_library.R"))

# ==============================================================================
# 2. Set Input Directory and Create Output Directory
# ==============================================================================

input_dir <- here::here("data", "processed")
output_dir <- here::here("output", "05_create_subsampled_ensemble")
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# ==============================================================================
# 3. Read Full SOW Information
# ==============================================================================

ff_sow_info <- read_parquet(file.path(input_dir, "ff_sow_info.parquet"))
ff_cfd      <- read_parquet(file.path(input_dir, "ff_cfd.parquet"))

sow_df <- cbind(ff_sow_info, ff_cfd)

# ==============================================================================
# 4. Perform cLHS Sampling
# ==============================================================================

sample_size <- 5

cols_to_sample <- c(
  "Median", 
  "demand", 
  "InitCombinedStorage", 
  colnames(ff_cfd)
)

clhs_sows <- generate_clhs_samples(
  sow_df        = sow_df,
  neurons       = sort(unique(sow_df$Neuron)),
  sample_size   = sample_size,
  cols_to_sample = cols_to_sample
)

# Extract the sampled SOW metadata
sampled_sow_info <- ff_sow_info[clhs_sows$OriginalIndex, ]

# Save sampled SOW metadata
write_parquet(
  x    = sampled_sow_info,
  sink = file.path(output_dir, "sampled_sow_info.parquet")
)

# ==============================================================================
# 5. Define Paths to Input and Output Datasets
# ==============================================================================

# Input datasets: full ensemble data
ff_cfd_path         <- file.path(input_dir, "ff_cfd.parquet")
ff_cfd_scaled_path  <- file.path(input_dir, "full_factorial_cfd_min_max_scaled.parquet")
ff_traces_path      <- file.path(input_dir, "full_factorial_trace_timeseries.parquet")

# Output datasets: subsetted data for sampled SOWs
sampled_sows_cfd_path        <- file.path(output_dir, "sampled_sow_cfd.parquet")
sampled_sows_cfd_scaled_path <- file.path(output_dir, "sampled_sow_cfd_min_max_scaled.parquet")
sampled_sows_traces_path     <- file.path(output_dir, "sampled_sow_traces_timeseries.parquet")

# ==============================================================================
# 6. Save Subsetted Data for Sampled SOWs
# ==============================================================================

# Extract and save cumulative flow less demand (CFD) data
subset_and_save(
  input_path  = ff_cfd_path,
  output_path = sampled_sows_cfd_path,
  indices     = clhs_sows$OriginalIndex
)

# Extract and save scaled CFD data
subset_and_save(
  input_path  = ff_cfd_scaled_path,
  output_path = sampled_sows_cfd_scaled_path,
  indices     = clhs_sows$OriginalIndex
)

# Extract and save trace time series data
subset_and_save(
  input_path  = ff_traces_path,
  output_path = sampled_sows_traces_path,
  indices     = sampled_sow_info$Trace
)
