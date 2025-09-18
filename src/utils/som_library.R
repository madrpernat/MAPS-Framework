#' SOM Helper Functions
#'
#' Centralized utilities for Self-Organizing Map (SOM) workflows used in this
#' project, including data preparation, PCA, prototype initialization,
#' subsampling, diversity metrics, visualization, and neuron/grid utilities.
#'
#' @description Contents:
#' - **Data Loading + PCA**
#'   * `load_som_data()` – load CFD + IC data
#'   * `run_pca()` – run PCA, return rotation and ranges
#'   * `init_prototypes()` – initialize neuron prototypes in PCA space
#'
#' - **Legacy Grid Functions** (adapted from Kohonen / Bonham et al., 2022)
#'   * `continuous_to_discrete()`
#'   * `quantile2radius()`
#'   * `check.somgrid()`
#'   * `unit.distances()`
#'
#' - **Subsampling + Diversity Metrics**
#'   * `min_max_scale()` – normalize data [0,1]
#'   * `calc_mst_metrics()` – compute MST-based diversity scores
#'   * `generate_clhs_samples()` – run cLHS subsampling within neurons
#'   * `subset_and_save()` – subset datasets and save to Parquet
#'
#' - **Visualization Utilities**
#'   * `save_plot()` – generic ggsave wrapper
#'   * `plot_boxplot_by_factor()`
#'   * `plot_summary_barplot()`
#'   * `calculate_knee()` – knee/elbow test for sample size
#'
#' @references
#' Legacy grid utilities adapted from:
#' Nathan Bonham et al. (2022),
#' *Environmental Modelling & Software*,
#' \doi{10.1016/j.envsoft.2022.105491}

# ------------------------------------------------------------------------------

library(here)
library(stats)
library(data.table)
library(lhs)
library(kohonen)
library(dplyr)
library(plyr)
library(plotly)
library(htmlwidgets)
library(aweSOM)
library(arrow)
library(clhs)
library(DiceDesign)
library(ggplot2)
library(kneedle)


# ==============================================================================
# Data Loading and PCA
# ==============================================================================

# ------------------------------------------------------------------------------
# Load CFD + IC data and combine into one matrix for PCA
# ------------------------------------------------------------------------------

load_som_data <- function(cfd_path, ic_path) {
  cfd_data <- as.matrix(read_parquet(cfd_path))
  ic_data  <- as.matrix(read_parquet(ic_path))
  combined <- cbind(cfd_data, ic_data)
  list(cfd = cfd_data, ic = ic_data, combined = combined)
}

# ------------------------------------------------------------------------------
# Run PCA on combined data and return rotation + ranges
# ------------------------------------------------------------------------------

run_pca <- function(data_matrix) {
  cov_matrix <- cov(data_matrix)
  eigen_decomp <- eigen(cov_matrix)
  rotation_matrix <- eigen_decomp$vectors[, 1:2]
  eigen_values <- eigen_decomp$values[1:2]
  pcs <- data_matrix %*% rotation_matrix
  list(
    rotation   = rotation_matrix,
    pc1_range  = range(pcs[, 1]),
    pc2_range  = range(pcs[, 2]),
    eigen_vals = eigen_values
  )
}

# ------------------------------------------------------------------------------
# Initialize neuron prototypes in PCA space
# ------------------------------------------------------------------------------

init_prototypes <- function(rotation_matrix, pc1_range, pc2_range, x_dim, y_dim) {
  d1 <- seq(from = pc1_range[1], to = pc1_range[2], length.out = x_dim)
  d2 <- seq(from = pc2_range[1], to = pc2_range[2], length.out = y_dim)
  pc_grid <- expand.grid(d1, d2)
  init_matrix <- as.matrix(pc_grid) %*% t(rotation_matrix)
  list(
    init1 = as.matrix(init_matrix[, 1:30], ncol = 30),  # flow/demand layer
    init2 = as.matrix(init_matrix[, 31], ncol = 1)      # initial storage layer
  )
}


# ==============================================================================
# Legacy Grid Functions (from Nathan Bonham et al., 2022)
# ==============================================================================

# ------------------------------------------------------------------------------
# Transform continuous values to discrete categories
# ------------------------------------------------------------------------------

continuous_to_discrete <- function(unit_cube, probs, categories) {
  for (i in 1:(length(probs) - 1)) {
    indices <- which(unit_cube > probs[i] & unit_cube <= probs[i + 1])
    unit_cube[indices] <- categories[i]
  }
  return(unit_cube)
}

# ------------------------------------------------------------------------------
# Calculate neighborhood radius from quantile of max node distance
# ------------------------------------------------------------------------------

quantile2radius <- function(fraction, x, y, shape) {
  grid <- somgrid(x, y, shape)
  grid <- check.somgrid(grid)
  nhbrdist <- unit.distances(grid)
  radius <- quantile(nhbrdist, fraction)
  return(radius)
}

# ------------------------------------------------------------------------------
# Validate and augment somgrid object (from Kohonen source)
# ------------------------------------------------------------------------------

check.somgrid <- function(grd) {
  mywarn <- FALSE
  if (is.null(grd$toroidal)) {
    mywarn <- TRUE
    grd$toroidal <- FALSE
  }
  if (is.null(grd$neighbourhood.fct)) {
    mywarn <- TRUE
    grd$neighbourhood.fct <- factor("bubble", levels = c("bubble", "gaussian"))
  }
  if (mywarn) {
    warning("Added defaults for somgrid object - ",
            "you are probably using the somgrid function ",
            "from the class library...")
  }
  grd
}

# ------------------------------------------------------------------------------
# Compute pairwise unit distances on a SOM grid (from Kohonen source)
# ------------------------------------------------------------------------------

unit.distances <- function(grid, toroidal) {
  if (missing(toroidal)) toroidal <- grid$toroidal
  if (!toroidal) {
    if (grid$topo == "hexagonal") {
      return(as.matrix(stats::dist(grid$pts)))
    } else {
      return(as.matrix(stats::dist(grid$pts, method = "maximum")))
    }
  }
  np <- nrow(grid$pts)
  maxdiffx <- grid$xdim / 2
  maxdiffy <- max(grid$pts[, 2]) / 2
  result <- matrix(0, np, np)
  for (i in 1:(np - 1)) {
    for (j in (i + 1):np) {
      diffs <- abs(grid$pts[j, ] - grid$pts[i, ])
      if (diffs[1] > maxdiffx) diffs[1] <- 2 * maxdiffx - diffs[1]
      if (diffs[2] > maxdiffy) diffs[2] <- 2 * maxdiffy - diffs[2]
      if (grid$topo == "hexagonal") {
        result[i, j] <- sum(diffs^2)
      } else {
        result[i, j] <- max(diffs)
      }
    }
  }
  if (grid$topo == "hexagonal") {
    sqrt(result + t(result))
  } else {
    result + t(result)
  }
}


# ==============================================================================
# Subsampling and Diversity Metrics
# ==============================================================================

# ------------------------------------------------------------------------------
# Min-max scaling
# ------------------------------------------------------------------------------

min_max_scale <- function(x) {
  (x - min(x)) / (max(x) - min(x))
}

# ------------------------------------------------------------------------------
# Calculate MST diversity metrics
# ------------------------------------------------------------------------------

calc_mst_metrics <- function(design) {
  mst <- mstCriteria(design)
  data.frame(
    mindist = mindist(design),
    MSTmean = mst$stats[1],
    MSTsd   = mst$stats[2]
  )
}

# ------------------------------------------------------------------------------
# Generate cLHS samples for each neuron
# ------------------------------------------------------------------------------

generate_clhs_samples <- function(
    sow_df, 
    neurons, 
    sample_size,
    cols_to_sample
) {
  sow_df <- dplyr::mutate(sow_df, OriginalIndex = dplyr::row_number())
  
  results_list <- vector("list", length(neurons))
  
  for (i in seq_along(neurons)) {

    neuron <- neurons[i]
    
    neuron_sows <- dplyr::filter(sow_df, Neuron == neuron)
    neuron_sow_idx <- neuron_sows$OriginalIndex
    
    clhs_temp <- clhs(
      x        = neuron_sows[cols_to_sample],
      size     = sample_size,
      simple   = FALSE,
      iter     = nrow(neuron_sows),
      progress = FALSE,
      weights  = list(numeric = 1, factor = 0, correlation = 1),
      use.cpp  = TRUE
    )
    
    temp_sows <- clhs_temp$sampled_data
    sampled_sow_idx <- neuron_sow_idx[as.numeric(rownames(temp_sows))]
    
    results_list[[i]] <- data.frame(
      Neuron        = rep(neuron, sample_size),
      OriginalIndex = sampled_sow_idx
    )
  }
  
  return(do.call(rbind, results_list))
}

# ------------------------------------------------------------------------------
# Subset a dataset by indices and save to Parquet
# ------------------------------------------------------------------------------

subset_and_save <- function(
    input_path,
    output_path,
    indices
) {
  input_data <- read_parquet(input_path)
  sampled_data <- input_data[indices, ]
  rownames(sampled_data) <- NULL
  
  write_parquet(
    x    = sampled_data,
    sink = output_path
  )
}


# ==============================================================================
# Visualization Utilities
# ==============================================================================

# ------------------------------------------------------------------------------
# Save a ggplot object
# ------------------------------------------------------------------------------

save_plot <- function(plot, filename) {
  ggsave(
    filename = file.path(filename),
    plot     = plot,
    width    = 9.5,
    height   = 6
  )
}

# ------------------------------------------------------------------------------
# Boxplot by factor (e.g., SampleSize)
# ------------------------------------------------------------------------------

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
) {
  if (!factor_col %in% colnames(data)) {
    stop(paste("Factor column", factor_col, "not found in data"))
  }
  if (!metric_to_plot %in% colnames(data)) {
    stop(paste("Metric", metric_to_plot, "not found in data"))
  }
  
  plot <- ggplot(data, aes(
    x = as.factor(.data[[factor_col]]),
    y = .data[[metric_to_plot]]
  )) +
    geom_boxplot() +
    scale_x_discrete(labels = function(x) ifelse(seq_along(x) %% 2 == 1, x, "")) +
    labs(title = title, x = factor_col, y = y_label) +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  
  if (!is.null(ylims)) {
    plot <- plot + scale_y_continuous(limits = ylims)
  }
  if (!is.null(true_value)) {
    plot <- plot + geom_hline(yintercept = true_value, linetype = "dashed", color = "red")
  }
  
  filename <- paste0("Neuron_", neuron, "_", metric_to_plot, "_By_", factor_col, "_Boxplot.png")
  save_plot(plot, file.path(output_dir, filename))
}

# ------------------------------------------------------------------------------
# Barplot of summary statistics (IQR or variance)
# ------------------------------------------------------------------------------

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
) {
  if (!factor_col %in% colnames(data)) {
    stop(paste("Factor column", factor_col, "not found in data"))
  }
  if (!metric_to_plot %in% colnames(data)) {
    stop(paste("Metric", metric_to_plot, "not found in data"))
  }
  
  summary_func <- switch(
    summary_stat,
    "IQR"      = IQR,
    "variance" = var,
    stop(paste("Unsupported summary statistic:", summary_stat))
  )
  
  summary_data <- data %>%
    group_by(.data[[factor_col]]) %>%
    summarise(SummaryValue = summary_func(.data[[metric_to_plot]], na.rm = TRUE))
  
  plot <- ggplot(summary_data, aes(
    x = as.factor(.data[[factor_col]]),
    y = SummaryValue
  )) +
    geom_bar(stat = "identity", fill = "steelblue") +
    scale_x_discrete(labels = function(x) ifelse(seq_along(x) %% 2 == 1, x, "")) +
    labs(title = title, x = factor_col, y = y_label) +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  
  if (!is.null(ylims)) {
    plot <- plot + scale_y_continuous(limits = ylims)
  }
  
  filename <- paste0("Neuron_", neuron, "_", metric_to_plot, "_", summary_stat,
                     "_By_", factor_col, "_Barplot.png")
  save_plot(plot, file.path(output_dir, filename))
}

# ------------------------------------------------------------------------------
# Knee/elbow test for sample size
# ------------------------------------------------------------------------------

calculate_knee <- function(
    data,
    neuron,
    metric,
    aggregation_func,
    metric_label
) {
  aggregated_metric <- data %>%
    filter(Neuron == neuron) %>%
    group_by(SampleSize) %>%
    summarise(AggregatedValue = aggregation_func(.data[[metric]], na.rm = TRUE))
  
  knee <- kneedle(
    x = aggregated_metric$SampleSize,
    y = aggregated_metric$AggregatedValue
  )
  
  cat("    For", metric_label,
      "elbow occurs at Sample Size:", knee[1],
      ", with Value:", knee[2], "\n")
}


