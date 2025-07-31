# ==============================================================================
# 1. Load Libraries and Utility Functions
# ==============================================================================
source('src/utils/som_subsampling_utils.R')

# ==============================================================================
# 2. Set and Create Output Directory
# ==============================================================================
output_dir <- "output/som_subsampling"
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# ==============================================================================
# 3. Read Input Data (Features for Sampling)
# ==============================================================================
cols_to_keep <- c('Median', 'demand', 'InitCombinedStorage', 'Neuron')

full_sow_info <- read_parquet(
  'output/full_factorial_sow_dev/full_factorial_sow_info.parquet'
)[cols_to_keep]

full_sow_timeseries <- read_parquet(
  'output/full_factorial_sow_dev/full_factorial_cfd.parquet'
)

features <- cbind(full_sow_info, full_sow_timeseries)

# ==============================================================================
# 4. Define Experiment Parameters
# ==============================================================================
# Set parameters for the subsampling experiment:
# - `neurons`: Randomly select a subset of neurons to perform experiment on.
# - `iterations`: Number of cLHS iterations for each sample size.
# - `sample_sizes`: Range of sample sizes to explore during the experiment.

set.seed(123)
neurons <- sort(sample(1:85, 5, replace = FALSE)) # 5 random neurons
iterations <- 100
sample_sizes <- seq(5, 150, 5)

# ==============================================================================
# 5. Initialize Results Storage
# ==============================================================================
# Prepare an empty data frame to store results of the experiment. Each row 
# corresponds to a combination of neuron, sample size, iteration, and the 
# associated metric values (MSTmean, AvgMedianFlow, AvgDemand, AvgInitStorage).

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
for (neuron in neurons) {
  
  cat("Processing Neuron", neuron, "\n")
  
  # Extract and preprocess data for this neuron
  neuron_sows <- full_sow_info %>%
    filter(Neuron == neuron) %>%
    select(-Neuron)
  
  neuron_timeseries <- full_sow_timeseries[full_sow_info$Neuron == neuron, ]
  
  data_to_sample <- cbind(neuron_timeseries, neuron_sows)
  
  data_to_sample_scaled <- data_to_sample %>% 
    mutate(across(everything(), min_max_scale))
  
  # Loop over sample sizes
  for (sample_size in sample_sizes) {
    
    cat("  Sample size =", sample_size, "\n")
    
    for (i in 1:iterations) {
      
      # Generate a cLHS sample
      clhs_temp <- clhs(
        x = data_to_sample,
        size = sample_size,
        simple = FALSE,
        iter = nrow(data_to_sample),
        progress = FALSE,
        weights = list(numeric = 1, factor = 0, correlation = 1),
        use.cpp = TRUE
      )
      
      # Extract sampled SOWs
      sampled_sows <- clhs_temp$sampled_data
      
      # Calculate the characteristic averages of the sampled SOWs
      avg_median_flow <- mean(sampled_sows$Median)
      avg_demand <- mean(sampled_sows$demand)
      avg_ic <- mean(sampled_sows$InitCombinedStorage)
      
      # Use scaled data for the minimum spanning tree calculations
      mst_data <- data_to_sample_scaled[
        as.integer(rownames(sampled_sows)), 
        c('Median', 'demand', 'InitCombinedStorage')
      ]
      mst_scores <- calc_mst_metrics(mst_data)
      
      # Append results
      results <- rbind(
        results,
        data.frame(
          Neuron = neuron,
          SampleSize = sample_size,
          Iteration = i,
          MSTmean = mst_scores$MSTmean,
          AvgMedianFlow = avg_median_flow,
          AvgDemand = avg_demand,
          AvgInitCombinedStorage = avg_ic
        )
      )
    }
  }
}

# ==============================================================================
# 7. Save Results
# ==============================================================================
# Save the results of the experiment to a Parquet file for future analysis.

results <- bind_rows(results)
write_parquet(
  x=results,
  sink=file.path(output_dir, "som_subsample_size_experiment.parquet")
)

# ==============================================================================
# 8. Generate Plots for Each Neuron
# ==============================================================================
# For each neuron, generate and save visualizations of the experiment results.
# These include, for each neuron, boxplots of MSTMean and AvgMedianFlow and 
# barplots of IQR and variance of these metrics.

# results <- read_parquet(
#   file=file.path(output_dir, "som_subsample_size_experiment.parquet")
# )

for (neuron in neurons){
  
  # Create subdirectory for plots
  neuron_dir <- file.path(output_dir, paste0("figures/Neuron_", neuron))
  if (!dir.exists(neuron_dir)) dir.create(neuron_dir, recursive = TRUE)
  
  # Filter data for the neuron
  filtered_data <- results %>% filter(Neuron == neuron)
  
  # Compute the true characteristic averages for the neuron
  true_avg_median <- mean(
    (full_sow_info %>% filter(Neuron == neuron))$Median
  )
  true_avg_demand <- mean(
    (full_sow_info %>% filter(Neuron == neuron))$demand
  )
  true_avg_ic <- mean(
    (full_sow_info %>% filter(Neuron == neuron))$InitCombinedStorage
  )
  
  # Generate and save boxplots for MSTMean and AvgMedianFlow
  plot_boxplot_by_factor(
    
      data = filtered_data,
      
      neuron = neuron,
      
      factor_col = "SampleSize",
      
      metric_to_plot = "MSTmean",
      
      output_dir = neuron_dir,
      
      y_label = "MSTMean",
      
      title = paste0(
        "Neuron", neuron, 
        ": MSTMean vs. Sample Size (",
        iterations, " cLHS iterations per boxplot)"
      ),
      
      ylims = c(0, 0.6)
  )
  
  plot_boxplot_by_factor(
    
      data = filtered_data,
      
      neuron = neuron,
      
      factor_col = "SampleSize",
      
      metric_to_plot = "AvgMedianFlow",
      
      output_dir = neuron_dir,
      
      y_label = "Avg Median Flow",
      
      title = paste0(
        "Neuron", neuron, 
        ": AvgMedianFlow vs. Sample Size (",
        iterations, " cLHS iterations per boxplot)"
      ),
      
      true_value = true_avg_median
  )
  
  plot_boxplot_by_factor(
    
    data = filtered_data,
    
    neuron = neuron,
    
    factor_col = "SampleSize",
    
    metric_to_plot = "AvgDemand",
    
    output_dir = neuron_dir,
    
    y_label = "Avg Demand",
    
    title = paste0(
      "Neuron", neuron, 
      ": AvgDemand vs. Sample Size (",
      iterations, " cLHS iterations per boxplot)"
    ),
    
    true_value = true_avg_demand
  )
  
  plot_boxplot_by_factor(
    
    data = filtered_data,
    
    neuron = neuron,
    
    factor_col = "SampleSize",
    
    metric_to_plot = "AvgInitCombinedStorage",
    
    output_dir = neuron_dir,
    
    y_label = "Avg Init Storage",
    
    title = paste0(
      "Neuron", neuron, 
      ": AvgInitStorage vs. Sample Size (",
      iterations, " cLHS iterations per boxplot)"
    ),
    
    true_value = true_avg_ic
  )
  
  # Generate and save plots of IQR vs. Sample Size for MSTMean and AvgMedianFlow
  plot_summary_barplot(
    
      data = filtered_data,
      
      neuron = neuron,
      
      factor_col = "SampleSize",
      
      metric_to_plot = "MSTmean",
      
      output_dir = neuron_dir,
      
      y_label = "MSTMean IQR",
      
      title = paste0(
        "Neuron", neuron,
        ": IQR of MSTMean vs. Sample Size (Based on ",
        iterations, " cLHS iterations per sample size)"
      ),
      
      summary_stat = "IQR"
  )
  
  plot_summary_barplot(
    
      data = filtered_data,
      
      neuron = neuron,
      
      factor_col = "SampleSize",
      
      metric_to_plot = "AvgMedianFlow",
      
      output_dir = neuron_dir,
      
      y_label = "AvgMedianFlow IQR",
      
      title = paste0(
        "Neuron", neuron,
        ": IQR of AvgMedianFlow vs. Sample Size (Based on ",
        iterations, " cLHS iterations per sample size)"
      ),
      
      summary_stat = "IQR"
  )
  
  # Generate and save plots of Var vs. Sample Size for MSTMean and AvgMedianFlow
  plot_summary_barplot(
    
      data = filtered_data,
      
      neuron = neuron,
      
      factor_col = "SampleSize",
      
      metric_to_plot = "MSTmean",
      
      output_dir = neuron_dir,
      
      y_label = "MSTMean Variance",
      
      title = paste0(
        "Neuron", neuron,
        ": Variance of MSTMean vs. Sample Size (Based on ",
        iterations, " cLHS iterations per sample size)"
      ),
      
      summary_stat = "variance",
      
      ylims = c(0, 0.006)
  )
  
  plot_summary_barplot(
    
      data = filtered_data,
      
      neuron = neuron,
      
      factor_col = "SampleSize",
      
      metric_to_plot = "AvgMedianFlow",
      
      output_dir = neuron_dir,
      
      y_label = "AvgMedianFlow Variance",
      
      title = paste0(
        "Neuron", neuron,
        ": Variance of AvgMedianFlow vs. Sample Size (Based on ",
        iterations, " cLHS iterations per sample size)"
      ),
      
      summary_stat = "variance",
      
      ylims =c(0, 0.14)
  )
}

# ==============================================================================
# 9. Perform Knee/Elbow Test
# ==============================================================================
# Analyze each metric for each neuron using knee/elbow tests to determine the
# point of diminishing returns for increasing sample sizes.

# results <- read_parquet(
#   file=file.path(output_dir, "som_subsample_size_experiment.parquet")
# )

metrics <- list(
  
  list(
    name = "MSTmean", 
    label = "MSTMean (Median)", 
    func = median
  ),
  list(
    name = "MSTmean",
    label = "MSTMean (Variance)", 
    func = var
  ),
  list(
    name = "AvgMedianFlow", 
    label = "AvgMedianFlow (Variance)", 
    func = var
  )
  
)

for (neuron in neurons){
  
  cat("Processing Neuron", neuron, "\n")

  for (metric_info in metrics) {
    
    calculate_knee(
      data = results,
      neuron = neuron,
      metric = metric_info$name,
      aggregation_func = metric_info$func,
      metric_label = metric_info$label
    )
    
  }
  
}
