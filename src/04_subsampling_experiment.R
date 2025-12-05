#' SOM Subsampling Experiment
#'
#' @description
#' The full-factorial ensemble of States of the World (SOWs) is often too large
#' to simulate directly in follow-on modeling. This script implements a
#' subsampling experiment to identify how many SOWs are need to be sampled
#' from each neuron to adequately represent the diversity and characteristics of 
#' of the SOWs contained in each neuron.
#' 
#' This script:
#'   1. Loads full SOW metadata (`ff_sow_info`) and CFD time series (`ff_cfd`).
#'   2. Selects random neurons from the trained SOM.
#'   3. For each neuron:
#'       a. Runs Conditioned Latin Hypercube Sampling (cLHS) with varying sample sizes.
#'       b. Calculates diversity (MST metrics) and feature averages for each subsample.
#'       c. Saves results, generates diagnostic plots, and performs knee/elbow tests.
#'
#' @details
#' Outputs are saved in:
#'   - `output/04_som_subsampling_experiment/`:
#'       * `som_subsample_size_experiment.parquet`: experiment results
#'       * `figures/Neuron_X/...`: plots for each sampled neuron
#'
#' @seealso
#'   - [som_library.R] for scaling, MST metrics, plotting, and knee detection
#'   - [03_final_som.R] for neuron assignments used in this script

# ==============================================================================
# 1. Load Libraries and Utility Functions
# ==============================================================================

source(here::here("src", "utils", "install_packages.R"))

library(here)
library(arrow)
source(here::here("src", "utils", "som_library.R"))

# ==============================================================================
# 2. Set Input Directory and Create Output Directory
# ==============================================================================

input_dir <- here::here("data", "processed")
output_dir <- here::here("output", "04_som_subsampling_experiment")
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# ==============================================================================
# 3. Read Input Data (Features for Sampling)
# ==============================================================================

cols_to_keep <- c("Median", "demand", "InitCombinedStorage", "Neuron")

ff_sow_info <- read_parquet(file.path(input_dir, "ff_sow_info.parquet"))[cols_to_keep]
ff_cfd <- read_parquet(file.path(input_dir, "ff_cfd.parquet"))

features <- cbind(ff_sow_info, ff_cfd)

# ==============================================================================
# 4. Define Experiment Parameters
# ==============================================================================

set.seed(123)
neurons <- sort(sample(1:85, 5, replace = FALSE)) # random selection of neurons
iterations <- 100  # number of iterations per sample size
sample_sizes <- seq(5, 150, 5)

# ==============================================================================
# 5. Initialize Results Storage
# ==============================================================================

results <- data.frame(
  Neuron = integer(),
  SampleSize = integer(),
  Iteration = integer(),
  MSTmean = numeric(),
  AvgMedianFlow = numeric(),
  AvgDemand = numeric(),
  AvgInitCombinedStorage = numeric()
)

# ==============================================================================
# 6. Main Experiment Loop
# ==============================================================================

results_list <- list()
counter <- 1

for (neuron in neurons) {
  
  cat("Processing Neuron", neuron, "\n")
  
  # Extract data for this neuron
  neuron_sows <- ff_sow_info %>%
    filter(Neuron == neuron) %>%
    select(-Neuron)
  
  neuron_timeseries <- ff_cfd[ff_sow_info$Neuron == neuron, ]
  data_to_sample <- cbind(neuron_timeseries, neuron_sows)
  
  # Scaled version for MST
  data_to_sample_scaled <- data_to_sample %>%
    dplyr::mutate(dplyr::across(dplyr::everything(), .fns = get("min_max_scale")))
  
  # Iterate over sample sizes
  for (sample_size in sample_sizes) {
    
    cat("  Sample size =", sample_size, "\n")
    
    for (i in 1:iterations) {
      
      # Run cLHS sampling
      clhs_temp <- clhs(
        x = data_to_sample,
        size = sample_size,
        simple = FALSE,
        iter = nrow(data_to_sample),
        progress = FALSE,
        weights = list(numeric = 1, factor = 0, correlation = 1),
        use.cpp = TRUE
      )
      
      sampled_sows <- clhs_temp$sampled_data
      
      # Calculate averages
      avg_median_flow <- mean(sampled_sows$Median)
      avg_demand <- mean(sampled_sows$demand)
      avg_ic <- mean(sampled_sows$InitCombinedStorage)
      
      # Calculate MST metrics (scaled data)
      mst_data <- data_to_sample_scaled[
        as.integer(rownames(sampled_sows)),
        c("Median", "demand", "InitCombinedStorage")
      ]
      mst_scores <- calc_mst_metrics(mst_data)
      
      # Append results into list
      results_list[[counter]] <- data.frame(
        Neuron = neuron,
        SampleSize = sample_size,
        Iteration = i,
        MSTmean = mst_scores$MSTmean,
        AvgMedianFlow = avg_median_flow,
        AvgDemand = avg_demand,
        AvgInitCombinedStorage = avg_ic
      )
      counter <- counter + 1
    }
  }
}

# Combine all results at once
results <- bind_rows(results_list)

# ==============================================================================
# 7. Save Results
# ==============================================================================

write_parquet(results, sink = file.path(output_dir, "som_subsample_size_experiment.parquet"))

# ==============================================================================
# 8. Generate Plots for Each Neuron
# ==============================================================================

for (neuron in neurons) {
  
  neuron_dir <- file.path(output_dir, paste0("figures/Neuron_", neuron))
  if (!dir.exists(neuron_dir)) dir.create(neuron_dir, recursive = TRUE)
  
  filtered_data <- results %>% filter(Neuron == neuron)
  
  # True averages (full population)
  true_avg_median <- mean((ff_sow_info %>% filter(Neuron == neuron))$Median)
  true_avg_demand <- mean((ff_sow_info %>% filter(Neuron == neuron))$demand)
  true_avg_ic <- mean((ff_sow_info %>% filter(Neuron == neuron))$InitCombinedStorage)
  
  # Boxplots
  plot_boxplot_by_factor(
    data = filtered_data, neuron = neuron,
    factor_col = "SampleSize", metric_to_plot = "MSTmean",
    output_dir = neuron_dir, y_label = "MSTMean",
    title = paste0("Neuron ", neuron, ": MSTMean vs. Sample Size (", iterations, " cLHS iterations per boxplot)"),
    ylims = c(0, 0.6)
  )
  
  plot_boxplot_by_factor(
    data = filtered_data, neuron = neuron,
    factor_col = "SampleSize", metric_to_plot = "AvgMedianFlow",
    output_dir = neuron_dir, y_label = "Avg Median Flow",
    title = paste0("Neuron ", neuron, ": AvgMedianFlow vs. Sample Size (", iterations, " cLHS iterations per boxplot)"),
    true_value = true_avg_median
  )
  
  plot_boxplot_by_factor(
    data = filtered_data, neuron = neuron,
    factor_col = "SampleSize", metric_to_plot = "AvgDemand",
    output_dir = neuron_dir, y_label = "Avg Demand",
    title = paste0("Neuron ", neuron, ": AvgDemand vs. Sample Size (", iterations, " cLHS iterations per boxplot)"),
    true_value = true_avg_demand
  )
  
  plot_boxplot_by_factor(
    data = filtered_data, neuron = neuron,
    factor_col = "SampleSize", metric_to_plot = "AvgInitCombinedStorage",
    output_dir = neuron_dir, y_label = "Avg Init Storage",
    title = paste0("Neuron ", neuron, ": AvgInitStorage vs. Sample Size (", iterations, " cLHS iterations per boxplot)"),
    true_value = true_avg_ic
  )
  
  # IQR + Variance barplots
  plot_summary_barplot(
    data = filtered_data, neuron = neuron,
    factor_col = "SampleSize", metric_to_plot = "MSTmean",
    output_dir = neuron_dir, y_label = "MSTMean IQR",
    title = paste0("Neuron ", neuron, ": IQR of MSTMean vs. Sample Size (Based on ", iterations, " iterations)"),
    summary_stat = "IQR"
  )
  
  plot_summary_barplot(
    data = filtered_data, neuron = neuron,
    factor_col = "SampleSize", metric_to_plot = "AvgMedianFlow",
    output_dir = neuron_dir, y_label = "AvgMedianFlow IQR",
    title = paste0("Neuron ", neuron, ": IQR of AvgMedianFlow vs. Sample Size (Based on ", iterations, " iterations)"),
    summary_stat = "IQR"
  )
  
  plot_summary_barplot(
    data = filtered_data, neuron = neuron,
    factor_col = "SampleSize", metric_to_plot = "MSTmean",
    output_dir = neuron_dir, y_label = "MSTMean Variance",
    title = paste0("Neuron ", neuron, ": Variance of MSTMean vs. Sample Size (Based on ", iterations, " iterations)"),
    summary_stat = "variance", ylims = c(0, 0.006)
  )
  
  plot_summary_barplot(
    data = filtered_data, neuron = neuron,
    factor_col = "SampleSize", metric_to_plot = "AvgMedianFlow",
    output_dir = neuron_dir, y_label = "AvgMedianFlow Variance",
    title = paste0("Neuron ", neuron, ": Variance of AvgMedianFlow vs. Sample Size (Based on ", iterations, " iterations)"),
    summary_stat = "variance", ylims = c(0, 0.14)
  )
}

# ==============================================================================
# 9. Perform Knee/Elbow Test
# ==============================================================================

# results <- read_parquet(file.path(output_dir, "som_subsample_size_experiment.parquet"))

metrics <- list(
  list(name = "MSTmean", label = "MSTMean (Median)", func = median),
  list(name = "MSTmean", label = "MSTMean (Variance)", func = var),
  list(name = "AvgMedianFlow", label = "AvgMedianFlow (Variance)", func = var)
)

for (neuron in neurons) {
  cat("Processing Neuron", neuron, "\n")
  for (metric_info in metrics) {
    calculate_knee(
      data = results, neuron = neuron,
      metric = metric_info$name,
      aggregation_func = metric_info$func,
      metric_label = metric_info$label
    )
  }
}
