library(arrow)
library(clhs)
library(DiceDesign) # space filling metrics
library(dplyr)
library(ggplot2)
library(kneedle)
################################################################################
################################################################################
min_max_scale <- function(x) {
  (x - min(x)) / (max(x) - min(x))
}
################################################################################
################################################################################
calc_mst_metrics=function(design){
  
  mst=mstCriteria(design)
  
  df=data.frame(
    mindist=mindist(design),
    MSTmean=mst$stats[1],
    MSTsd=mst$stats[2]
  )
  
  return(df)
  
}
################################################################################
################################################################################
# Function to save and plot
save_plot <- function(plot, filename) {
  ggsave(
    filename = file.path(filename), 
    plot = plot, 
    width = 9.5, 
    height = 6
  )
}
################################################################################
################################################################################
plot_boxplot_by_factor <- function(
    data, 
    neuron,
    factor_col,
    metric_to_plot,
    output_dir, 
    y_label,
    title,
    true_value = NULL,
    ylims = NULL
    ) 
  {
  # Check if the metric and factor columns exist in the data
  if (!factor_col %in% colnames(data)) {
    stop(paste("Factor column", factor_col, "not found in data"))
  }
  if (!metric_to_plot %in% colnames(data)) {
    stop(paste("Metric", metric_to_plot, "not found in data"))
  }
  
  # Create the plot
  plot <- 
    
    ggplot(
      data=data, 
      mapping=aes(
        x = as.factor(.data[[factor_col]]), 
        y = .data[[metric_to_plot]]
      )
    ) +
    
    geom_boxplot() +
    
    scale_x_discrete(
      labels = function(x) ifelse(seq_along(x) %% 2 == 1, x, "")
    ) +
    
    labs(
      title = title,
      x = factor_col,
      y = y_label
    ) +
    
    theme_minimal() +
    
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1)
    )
  
  # Add y-axis limits if provided
  if (!is.null(ylims)) {
    plot <- plot + scale_y_continuous(limits = ylims)
  }
  
  # Add a horizontal line if a true value is provided
  if (!is.null(true_value)) {
    plot <- plot + 
      geom_hline(
        yintercept = true_value, 
        linetype = "dashed", 
        color = "red"
      )
  }
  
  # Save the plot
  filename <- paste0(
    "Neuron_", neuron, "_", metric_to_plot, "_By_", factor_col, "_Boxplot.png"
  )
  save_plot(
    plot=plot, 
    filename=file.path(output_dir, filename)
  )
    
}
################################################################################
################################################################################
plot_summary_barplot <- function(
    data, 
    neuron,
    factor_col,
    metric_to_plot,
    output_dir, 
    y_label,
    title,
    summary_stat,
    ylims = NULL
    )
  {
  # Check if the metric and factor columns exist in the data
  if (!factor_col %in% colnames(data)) {
    stop(paste("Factor column", factor_col, "not found in data"))
  }
  if (!metric_to_plot %in% colnames(data)) {
    stop(paste("Metric", metric_to_plot, "not found in data"))
  }
  
  # Select the appropriate summary statistic function
  summary_func <- switch(
    summary_stat,
    "IQR" = IQR,
    "variance" = var,
    stop(paste("Unsupported summary statistic:", summary_stat))
  )
  
  # Calculate summary statistic
  summary_data <- data %>%
    group_by(.data[[factor_col]]) %>%
    summarise(
      SummaryValue = summary_func(.data[[metric_to_plot]], na.rm = TRUE)
    )
  
  # Create the barplot
  plot <- 
    
    ggplot(
      data=summary_data,
      mapping=aes(x = as.factor(.data[[factor_col]]), y = SummaryValue)
    ) +
    
    geom_bar(
      stat = "identity", 
      fill = "steelblue"
    ) +
    
    scale_x_discrete(
      labels = function(x) ifelse(seq_along(x) %% 2 == 1, x, "")
    ) +
    
    labs(
      title = title,
      x = factor_col,
      y = y_label
    ) +
    
    theme_minimal() +
    
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1)
    )
  
  # Add y-axis limits if provided
  if (!is.null(ylims)) {
    plot <- plot + scale_y_continuous(limits = ylims)
  }
  
  # Save the plot
  filename <- paste0(
    "Neuron_", neuron, "_", metric_to_plot, "_", summary_stat,
    "_By_", factor_col, "_Barplot.png"
  )
  save_plot(
    plot=plot, 
    filename=file.path(output_dir, filename)
  )
}
################################################################################
################################################################################
calculate_knee <- function(
    data, 
    neuron, 
    metric, 
    aggregation_func, 
    metric_label
    )
  {
  aggregated_metric <- data %>%
    filter(Neuron == neuron) %>%
    group_by(SampleSize) %>%
    summarise(AggregatedValue = aggregation_func(.data[[metric]], na.rm = TRUE))
  
  knee <- kneedle(
    x = aggregated_metric$SampleSize,
    y = aggregated_metric$AggregatedValue
  )
  
  cat("    For", metric_label, "elbow occurs at Sample Size:", knee[1], ", with Value:", knee[2], "\n")
}
