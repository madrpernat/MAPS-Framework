# ==============================================================================
# 1. Load Libraries and Utility Functions
# ==============================================================================
source(here::here("src", "utils", "sow_clhs_utils.R"))

# ==============================================================================
# 2. Create Output Directory
# ==============================================================================
output_dir <- here::here("output", "05_create_subsampled_ensemble")
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# ==============================================================================
# 3. Read Full SOW Information
# ==============================================================================
input_dir = here::here("data", "processed")

ff_sow_info <- read_parquet(
  file.path(input_dir, "ff_sow_info.parquet")
)

ff_cfd <- read_parquet(
  file.path(input_dir, "ff_cfd.parquet")
)

sow_df <- cbind(ff_sow_info, ff_cfd)

# ==============================================================================
# 4. Perform cLHS Sampling
# ==============================================================================
cols_to_sample <- c(
  "Median", 
  "demand", 
  "InitCombinedStorage", 
  colnames(ff_cfd)
)

clhs_sows <- generate_clhs_samples(
  sow_df = sow_df,
  neurons = sort(unique(sow_df$Neuron)),
  sample_size = 50,
  cols_to_sample = cols_to_sample
)

# Extract the sampled SOW information
sampled_sow_info <- ff_sow_info[clhs_sows$OriginalIndex, ]

# Write out the sampled SOW info
write_parquet(
  x = sampled_sow_info,
  sink = file.path(output_dir, "sampled_sow_info.parquet")
)

# ==============================================================================
# 5. Define Paths to Input and Output Datasets
# ==============================================================================
# - Input datasets: These files contain data for the complete set of States of
#   the World (SOWs). We need these files to extract information specific to the
#   the subset of sampled SOWs.
# 
# - Output datasets: These files will store data specific to the sampled SOWs,
#   allowing us to isolate and analyze the subset selected during the cLHS
#   sampling step. These files serve as inputs for downstream analysis.

# Input datasets of full factorial ensemble data

ff_cfd_path <- file.path(
  input_dir, 
  "ff_cfd.parquet"
)

ff_cfd_scaled_path <- file.path(
  input_dir, 
  "full_factorial_cfd_min_max_scaled.parquet"
)

ff_traces_path <- file.path(
  input_dir, 
  "full_factorial_trace_timeseries.parquet"
)

# Output datasets for sampled SOWs

sampled_sows_cfd_path <- file.path(
  output_dir, 
  "sampled_sows_cfd.parquet"
)

sampled_sows_cfd_scaled_path <- file.path(
  output_dir, 
  "sampled_sows_cfd_min_max_scaled.parquet"
)

sampled_sows_traces_path <- file.path(
  output_dir, 
  "sampled_sows_traces_timeseries.parquet"
)

# ==============================================================================
# 6. Save Subsetted Data for Sampled SOWs
# ==============================================================================
# Extract and save cumulative flow less demand (CFD) data
subset_and_save(
  input_path = ff_cfd_path,
  output_path = sampled_sows_cfd_path,
  indices = clhs_sows$OriginalIndex
)

# Extract and save scaled CFD data
subset_and_save(
  input_path = ff_cfd_scaled_path,
  output_path = sampled_sows_cfd_scaled_path,
  indices = clhs_sows$OriginalIndex
)

# Extract and save trace time series data
subset_and_save(
  input_path = ff_traces_path,
  output_path = sampled_sows_traces_path,
  indices = sampled_sow_info$Trace
)
