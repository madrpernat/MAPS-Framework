#' SOM Hyperparameter Tuning with Successive Non-Dominated Pruning
#'
#' @description
#' This script:
#'   1. Loads preprocessed full-factorial State of the World (SOW) ensemble data.
#'   2. Runs PCA to establish initialization space for SOM prototypes.
#'   3. Samples hyperparameter configurations using Latin Hypercube Sampling (LHS).
#'   4. Iteratively evaluates configurations using successive non-dominated pruning.
#'   5. Produces plots and exports results for analysis.
#'
#' @details
#' Outputs are saved in `output/02_som_hyperparameter_tuning/`, including:
#'   - `all_configs.csv`: full set of sampled hyperparameters
#'   - `snp_round*/...configs.csv`: pruning round performance data
#'   - `nondom_config_pc_plot.html`: interactive visualization of Pareto front configs
#'   - `epoch_test_results.csv`: epoch sensitivity test results
#'
#' @seealso
#'   - [som_library.R] for PCA, initialization, and utilities
#'   - [error_functions.R] for variance explained and topographic error metrics

# ==============================================================================
# 1. Load Libraries and Utility Functions
# ==============================================================================

source(here::here("src", "utils", "install_packages.R"))

library(here)
library(glue)
source(here::here("src", "utils", "som_library.R"))
source(here::here("src", "utils", "error_functions.R"))

# ==============================================================================
# 2. Define Output Directory and Load Data
# ==============================================================================

output_dir <- here::here("output", "02_som_hyperparameter_tuning")
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# Load SOM input data
som_data <- load_som_data(
  here::here("data", "processed", "ff_cfd_scaled.parquet"),
  here::here("data", "processed", "ff_init_storage_scaled.parquet")
)

# PCA results
pca_res <- run_pca(som_data$combined)
rotation_matrix <- pca_res$rotation
pc1_range <- pca_res$pc1_range
pc2_range <- pca_res$pc2_range
eigen_ratio <- pca_res$eigen_vals[1] / pca_res$eigen_vals[2]

# Feature subsets and weights (called data "layers" in the Kohonen package)
data_list <- list(som_data$cfd, som_data$ic)
user_weights <- c(0.25, 0.75)

rm(som_data, pca_res); gc()

# ==============================================================================
# 3. Sample Hyperparameter Configurations with LHS
# ==============================================================================

# Did NOT tune Distance Function here, as preliminary analysis showed that 
# Euclidean distance was far superior compared to Manhattan and Sum of Squares

n_samples <- 1000

# Continuous hyperparameter ranges
radius_range    <- c(0.5, 1)
y_dim_range     <- c(3, 5)
x_y_ratio_range <- c(floor(sqrt(eigen_ratio)), ceiling(eigen_ratio))

# Discrete hyperparameter options
neighborhood_fnc_opts <- c("gaussian", "bubble")

# Generate LHS samples
cube <- as.data.frame(improvedLHS(n = n_samples, k = 4))
colnames(cube) <- c("radius", "y_dim", "x_y_ratio", "neighborhood_fnc")

# Map samples to ranges
cube$radius <- qunif(cube$radius, min = radius_range[1], max = radius_range[2])
cube$y_dim  <- round(qunif(cube$y_dim, min = y_dim_range[1] - 0.5, max = y_dim_range[2] + 0.5))
cube$x_y_ratio <- qunif(cube$x_y_ratio, min = x_y_ratio_range[1], max = x_y_ratio_range[2])

# Map unit samples to categories
neighborhood_probs <- seq(0, 1, length.out = length(neighborhood_fnc_opts) + 1)
cube$neighborhood_fnc <- continuous_to_discrete(cube$neighborhood_fnc, neighborhood_probs, neighborhood_fnc_opts)

# Derive additional parameters
cube$x_dim     <- round(cube$y_dim * cube$x_y_ratio)
cube$n_neurons <- cube$y_dim * cube$x_dim
cube$ConfigID  <- seq_len(n_samples)

all_configs <- cube[, c("ConfigID", "radius", "y_dim", "x_y_ratio",
                        "neighborhood_fnc", "x_dim", "n_neurons")]

# Save configs
write.csv(all_configs, file = file.path(output_dir, "all_configs.csv"), row.names = FALSE)

# Visualize distributions
hist(all_configs$radius, main = "Distribution of Radius", xlab = "Radius")
hist(all_configs$y_dim, main = "Distribution of Y Dimension", xlab = "Y Dimension")
hist(all_configs$x_y_ratio, main = "Distribution of X/Y Ratio", xlab = "X/Y Ratio")
hist(all_configs$n_neurons, main = "Distribution of Number of Neurons", xlab = "Number of Neurons")
table(all_configs$neighborhood_fnc)

rm(cube, radius_range, y_dim_range, x_y_ratio_range, neighborhood_fnc_opts, neighborhood_probs, n_samples); gc()

# ==============================================================================
# 4. Successive Non-Dominated Pruning
# ==============================================================================

n_configs_each_round <- c(1000, 500, 250, 125, 63, 32)
subset_data_size     <- c(58970, 148126, 372076, 934612, 2347638, 5897000)
total_data_size      <- nrow(data_list[[1]])

for (i in 1:2) {
  current_configs <- 1:1000

  for (j in seq_along(n_configs_each_round)) {

    # Sample subset
    sample_idx <- sample(total_data_size, size = subset_data_size[j])
    temp_data_list <- list(
      data_list[[1]][sample_idx, ],
      data_list[[2]][sample_idx]
    )

    total_ss_euclidean <- calc_total_ss(temp_data_list, user_weights, "euclidean")

    n_neurons <- vars <- topos <- c()

    # --------------------------------------------------------------------------
    # Evaluate each configuration
    # --------------------------------------------------------------------------
    for (k in current_configs) {
      config <- all_configs[all_configs$ConfigID == k, ]
      xdim <- config$x_dim; ydim <- config$y_dim
      n_neuron <- config$n_neurons
      neighborhood_fnc <- config$neighborhood_fnc
      radius_fraction <- config$radius

      print(glue("Y={ydim}, X={xdim}, N={n_neuron}, neighbor={neighborhood_fnc}, ",
                 "radius={radius_fraction}, subset={subset_data_size[j]}, iter={i}"))

      init_radius <- quantile2radius(radius_fraction, xdim, ydim, shape = "hexagonal")
      inits <- init_prototypes(rotation_matrix, pc1_range, pc2_range, xdim, ydim)

      som <- supersom(
        data = temp_data_list,
        radius = init_radius,
        dist.fcts = "euclidean",
        grid = somgrid(xdim, ydim, topo = "hexagonal", toroidal = FALSE,
                       neighbourhood.fct = neighborhood_fnc),
        user.weights = user_weights,
        rlen = 24,
        keep.data = TRUE,
        init = list(inits$init1, inits$init2),
        mode = "pbatch",
        cores = -1,
        normalizeDataLayers = FALSE
      )

      var_explained <- -1 * calc_percent_var_explained(som, total_ss_euclidean)
      topo_error <- topo_error_parallel(som, num_cores = 15)

      vars <- c(vars, var_explained)
      topos <- c(topos, topo_error)
      n_neurons <- c(n_neurons, n_neuron)
    }

    # --------------------------------------------------------------------------
    # Non-dominated sorting
    # --------------------------------------------------------------------------
    objectives <- cbind(n_neurons, vars, topos)
    fronts <- fastNonDominatedSorting(objectives)

    front_column <- rep(NA, nrow(objectives))
    for (m in seq_along(fronts)) front_column[fronts[[m]]] <- m

    config_performance_df <- cbind(
      all_configs[match(current_configs, all_configs$ConfigID), ],
      vars, topos, front_column
    )
    colnames(config_performance_df) <- c(colnames(all_configs), "Pct.Var.Explained", "Topo.Error", "Front")

    output_file <- file.path(paste0("snp_round", i), paste0(n_configs_each_round[j], "configs.csv"))
    write.csv(config_performance_df, file = file.path(output_dir, output_file), row.names = FALSE)

    # --------------------------------------------------------------------------
    # Select configs for next iteration
    # --------------------------------------------------------------------------
    if (j < length(n_configs_each_round)) {
      n_configs_to_keep <- n_configs_each_round[j + 1]

      if (n_configs_to_keep < length(fronts[[1]])) {
        current_configs <- config_performance_df[config_performance_df$Front == 1, ]$ConfigID
      } else {
        cd <- crowdingDist4frnt(config_performance_df, fronts,
                                apply(objectives, 2, max) - apply(objectives, 2, min))
        cd_sum <- rowSums(cd)

        n_configs <- 0; current_front <- 0
        while (n_configs < n_configs_to_keep) {
          current_front <- current_front + 1
          n_configs <- n_configs + length(fronts[[current_front]])
        }
        trunc_front_idx <- fronts[[current_front]]

        cd_for_front <- data.frame(
          ConfigID = config_performance_df[trunc_front_idx, ]$ConfigID,
          CrowdingDistance = cd_sum[trunc_front_idx]
        ) %>% arrange(desc(CrowdingDistance))

        current_configs <- unlist(lapply(1:(current_front - 1), function(f) {
          config_performance_df[fronts[[f]], ]$ConfigID
        }))
        n_left <- n_configs_to_keep - length(current_configs)
        current_configs <- c(current_configs, cd_for_front$ConfigID[1:n_left])
      }
    }
  }
}

# ==============================================================================
# 5. Visualize Results (use to select hyperparameter configuration)
# ==============================================================================

round1 <- read.csv(file.path(output_dir, "snp_round1", "32configs.csv"))
round2 <- read.csv(file.path(output_dir, "snp_round2", "32configs.csv"))

best_configs <- bind_rows(round1, round2) %>%
  distinct(ConfigID, .keep_all = TRUE)

sort_df <- best_configs[, c("n_neurons", "Pct.Var.Explained", "Topo.Error")]
sorted_fronts <- fastNonDominatedSorting(sort_df)
front1_configs <- best_configs[sorted_fronts[[1]], ]

fig <- front1_configs %>%
  plot_ly(
    type = "parcoords",
    line = list(color = ~Topo.Error, hoverinfo = "ConfigID", width = 3),
    dimensions = list(
      list(range = c(0, 1),    label = "Radius", values = ~radius),
      list(range = c(9, 63),   label = "X Dim",  values = ~x_dim),
      list(range = c(3, 5),    label = "Y Dim",  values = ~y_dim),
      list(range = c(27, 315), label = "Number of Neurons", values = ~n_neurons),
      list(range = c(3, 13),   label = "X/Y Ratio", values = ~x_y_ratio),
      list(range = c(-0.95, -0.72), label = "Pct.Var.Explained", values = ~Pct.Var.Explained),
      list(range = c(0, 0.7),  label = "Topo Error", values = ~Topo.Error)
    )
  ) %>%
  layout(margin = list(l = 100, r = 100, b = 10, t = 10, pad = 3),
         font = list(size = 16))

saveWidget(as_widget(fig), file.path(output_dir, "nondom_config_pc_plot.html"))

# ==============================================================================
# 6. Epoch Test on Selected Configuration
# ==============================================================================

selected_config_id <- 318  # chosen from PC plot

x_dim <- all_configs$x_dim[selected_config_id]
y_dim <- all_configs$y_dim[selected_config_id]
neighborhood_fnc <- all_configs$neighborhood_fnc[selected_config_id]
radius_fraction <- all_configs$radius[selected_config_id]

init_radius <- quantile2radius(radius_fraction, x_dim, y_dim, shape = "hexagonal")
inits <- init_prototypes(rotation_matrix, pc1_range, pc2_range, x_dim, y_dim)

total_ss_euclidean <- calc_total_ss(data_list, user_weights, "euclidean")

epochs_to_test <- 12:36
vars <- topos <- c()

for (epochs in epochs_to_test) {
  som <- supersom(
    data = data_list,
    radius = init_radius,
    dist.fcts = "euclidean",
    grid = somgrid(xdim = x_dim, ydim = y_dim, topo = "hexagonal",
                   toroidal = FALSE, neighbourhood.fct = neighborhood_fnc),
    user.weights = user_weights,
    rlen = epochs,
    keep.data = TRUE,
    init = list(inits$init1, inits$init2),
    mode = "pbatch",
    cores = -1,
    normalizeDataLayers = FALSE
  )

  percent_var_explained <- -1 * calc_percent_var_explained(som, total_ss_euclidean)
  topo_error <- topo_error_parallel(som, 15)

  print(glue("Epochs: {epochs}, Pct.Var.Explained: {percent_var_explained}, Topo.Error: {topo_error}"))

  vars <- c(vars, percent_var_explained)
  topos <- c(topos, topo_error)
}

epoch_results <- data.frame(
  N.Epochs = epochs_to_test,
  Pct.Var.Explained = vars,
  Topo.Error = topos
)

write.csv(epoch_results, file = file.path(output_dir, "epoch_test_results.csv"), row.names = FALSE)
