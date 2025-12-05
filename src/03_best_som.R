#' Train Final SOM Using Best Configuration
#'
#' @description
#' This script:
#'   1. Loads preprocessed full-factorial State of the World (SOW) ensemble data.
#'   2. Runs PCA to establish initialization space for SOM prototypes.
#'   3. Retrieves the best hyperparameter configuration from tuning results.
#'   4. Trains the final SOM with the selected configuration.
#'   5. Saves trained SOM and exports results for downstream analysis in R or Python.
#'
#' @details
#' Outputs are saved in:
#'   - `output/03_final_som/`:
#'       * `best_som.rds`: trained SOM object
#'       * `som_codes_scaled.csv`: neuron prototypes
#'       * `som_sow_neuron_ids.parquet`: mapping of each SOW to a neuron
#'       * `som_neuron_coordinates.csv`: neuron coordinates in SOM grid
#'   - `data/processed/`:
#'       * `ff_sow_info.parquet`: updated SOW metadata, now including neuron assignments
#'
#' @seealso
#'   - [som_library.R] for PCA, initialization, and utilities
#'   - [02_som_hyperparameter_tuning.R] for hyperparameter search

# ==============================================================================
# 1. Load Libraries and Utility Functions
# ==============================================================================

source(here::here("src", "utils", "install_packages.R"))

library(here)
library(arrow)
source(here::here("src", "utils", "som_library.R"))

# ==============================================================================
# 2. Define Output Directory and Load Data
# ==============================================================================

output_dir <- here::here("output", "03_final_som")
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

# SOM input layers
data_list <- list(som_data$cfd, som_data$ic)
user_weights <- c(0.25, 0.75)

rm(som_data, pca_res); gc()

# ==============================================================================
# 3. Load Best Configuration
# ==============================================================================

config_id <- 318   # chosen from hyperparameter tuning
epochs <- 18
all_configs <- read.csv(here::here("output", "02_som_hyperparameter_tuning", "all_configs.csv"))

x_dim <- all_configs$x_dim[config_id]
y_dim <- all_configs$y_dim[config_id]
neighborhood_fnc <- all_configs$neighborhood_fnc[config_id]
radius_fraction <- all_configs$radius[config_id]

# Compute neighborhood radius
init_radius <- quantile2radius(radius_fraction, x_dim, y_dim, shape = "hexagonal")

# Initialize neuron prototypes
inits <- init_prototypes(rotation_matrix, pc1_range, pc2_range, x_dim, y_dim)
init1 <- inits$init1
init2 <- inits$init2

# ==============================================================================
# 4. Train the Final SOM
# ==============================================================================

best_som <- supersom(
  data = data_list,
  radius = init_radius,
  dist.fcts = "euclidean",
  grid = somgrid(
    xdim = x_dim,
    ydim = y_dim,
    topo = "hexagonal",
    toroidal = FALSE,
    neighbourhood.fct = neighborhood_fnc
  ),
  user.weights = user_weights,
  rlen = epochs,
  keep.data = TRUE,
  init = list(init1, init2),
  mode = "pbatch",
  cores = -1,
  normalizeDataLayers = FALSE
)

# Save SOM object for reuse in R
saveRDS(best_som, file = file.path(output_dir, "best_som.rds"))

# ==============================================================================
# 5. Write SOM Outputs to Disk
# ==============================================================================

# 5.1 Prototype vectors for each neuron (SOM codes)
som_codes <- cbind(best_som$codes[[1]], best_som$codes[[2]])
colnames(som_codes) <- c(2027:2056, "InitStorage")
write.csv(som_codes, file.path(output_dir, "som_codes_scaled.csv"), row.names = FALSE)

# 5.2 Assignment of each SOW to a SOM neuron
neuron_ids <- data.frame(
  SOW = 1:nrow(data_list[[1]]),
  Neuron = best_som$unit.classif
)
write_parquet(neuron_ids, sink = file.path(output_dir, "som_sow_neuron_ids.parquet"))

# 5.3 Coordinates of each neuron on the SOM grid
neuron_coordinates <- data.frame(best_som$grid$pts)
write.csv(neuron_coordinates, file.path(output_dir, "som_neuron_coordinates.csv"), row.names = FALSE)

# 5.4 Update SOW info file with neuron assignments
ff_sow_info <- read_parquet(here::here("data", "processed", "ff_sow_info.parquet"))
ff_sow_info$Neuron <- best_som$unit.classif

temp_path <- here::here("data", "processed", "ff_sow_info_temp.parquet")
write_parquet(ff_sow_info, sink = temp_path)
file.rename(temp_path, here::here("data", "processed", "ff_sow_info.parquet"))
