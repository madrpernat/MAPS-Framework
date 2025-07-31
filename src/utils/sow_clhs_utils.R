library(arrow)
library(clhs)
library(magrittr)
library(readxl)
################################################################################
################################################################################
# Function to generate cLHS samples for neurons

generate_clhs_samples <- function(
    sow_df, 
    neurons, 
    sample_size,
    cols_to_sample
) {
  
  sow_df <- sow_df %>% mutate(OriginalIndex = row_number())
  
  # Initialize a list to store sampling results for each neuron
  results_list <- vector("list", length(neurons))
  
  # Loop through each neuron
  for (i in seq_along(neurons)){
    
    neuron <- neurons[i]
    
    # Filter data for current neuron
    neuron_sows <- sow_df %>% filter(Neuron == neuron)
    neuron_sow_idx <- neuron_sows$OriginalIndex
    
    # Generate cLHS samples
    clhs_temp <- clhs(
      x = neuron_sows[cols_to_sample],
      size = sample_size,
      simple = FALSE,
      iter = nrow(neuron_sows),
      progress = FALSE,
      weights = list(numeric = 1, factor = 0, correlation = 1),
      use.cpp = TRUE
    )
    
    # Map sampled indices back to the original/full data indices
    temp_sows <- clhs_temp$sampled_data
    sampled_sow_idx <- neuron_sow_idx[as.numeric(rownames(temp_sows))]
    
    # Store results for the current neuron
    results_list[[i]] <- data.frame(
      Neuron = rep(neuron, sample_size),
      OriginalIndex = sampled_sow_idx
    )
    
  }
  
  # Combine results into a single data frame
  return(do.call(rbind, results_list))
  
}
################################################################################
################################################################################
subset_and_save <- function(
    input_path,
    output_path,
    indices
){
  
  input_data <- read_parquet(input_path)
  
  # Subset the data based on indices
  sampled_data <- input_data[indices, ]
  
  # Reset row names
  rownames(sampled_data) <- NULL
  
  # Write the output data
  write_parquet(
    x = sampled_data,
    sink = output_path
  )
}
################################################################################
################################################################################
