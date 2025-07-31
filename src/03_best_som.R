# ==============================================================================
# 1. Load Libraries and Utility Functions
# ==============================================================================

library(here)
library(arrow)
source(here("src", "utils", "som_library.R"))

# ==============================================================================
# 2. Define Output Directory and Load Data
# ==============================================================================

output_dir <- here("output", "03_final_som")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# Load scaled CFD data (years as columns)
cfd_data <- as.matrix(read_parquet(here("data", "processed", "ff_cfd_scaled.parquet")))
colnames(cfd_data) <- 2027:2056

# Load scaled initial storage data
ic_data <- as.matrix(read_parquet(here("data", "processed", "ff_init_storage_scaled.parquet")))

# Combine both into a single matrix for PCA
combined_data <- cbind(cfd_data, ic_data)

# ==============================================================================
# 3. Principal Component Analysis (PCA)
# ==============================================================================

cov_matrix <- cov(combined_data)
eigen_decomp <- eigen(cov_matrix)
rotation_matrix <- eigen_decomp$vectors[, 1:2]

principal_components <- combined_data %*% rotation_matrix
pc1_range <- range(principal_components[, 1])
pc2_range <- range(principal_components[, 2])

# ==============================================================================
# 4. Prepare Data and Best Configuration
# ==============================================================================

# Define SOM input and weights
data_list <- list(cfd_data, ic_data)
user_weights <- c(0.25, 0.75)

# Free memory
rm(cov_matrix, eigen_decomp, principal_components, combined_data, cfd_data, ic_data)
gc()

# Load best configuration
config_id <- 318
epochs <- 18
all_configs <- read.csv(here("output", "02_som_hyperparameter_tuning", "all_configs.csv"))

x_dim <- all_configs$x_dim[config_id]
y_dim <- all_configs$y_dim[config_id]
neighborhood_fnc <- all_configs$neighborhood_fnc[config_id]
radius_fraction <- all_configs$radius[config_id]

# Compute neighborhood radius
init_radius <- quantile2radius(
  fraction = radius_fraction,
  x = x_dim, 
  y = y_dim,
  shape = 'hexagonal'
)

# Initialize neuron prototypes using PCA space
d1 <- seq(from = pc1_range[1], to = pc1_range[2], length.out = x_dim)
d2 <- seq(from = pc2_range[1], to = pc2_range[2], length.out = y_dim)
pc_grid <- expand.grid(d1, d2)
init_matrix <- as.matrix(pc_grid) %*% t(rotation_matrix)

init1 <- as.matrix(init_matrix[, 1:30], ncol = 30)
init2 <- as.matrix(init_matrix[, 31], ncol = 1)

# ==============================================================================
# 5. Train the Final SOM
# ==============================================================================

best_som <- supersom(
  data = data_list,
  radius = init_radius,
  dist.fcts = 'euclidean',
  grid = somgrid(
    xdim = x_dim,
    ydim = y_dim,
    topo = 'hexagonal',
    toroidal = FALSE,
    neighbourhood.fct = neighborhood_fnc
  ),
  user.weights = user_weights,
  rlen = epochs,
  keep.data = TRUE,
  init = list(init1, init2),
  mode = 'pbatch',
  cores = -1,
  normalizeDataLayers = FALSE
)

# Save SOM object for future use in R
saveRDS(best_som, file = file.path(output_dir, "best_som.rds"))

# ==============================================================================
# 6. Write SOM Outputs to Disk for Analysis and Use in Python
# ==============================================================================

# 6.1 Prototype vectors for each neuron (SOM codes)
som_codes <- cbind(best_som$codes[[1]], best_som$codes[[2]])
colnames(som_codes) <- c(2027:2056, "InitStorage")
write.csv(som_codes, file.path(output_dir, "som_codes_scaled.csv"), row.names = FALSE)

# 6.2 Assignment of each SOW to a SOM neuron
neuron_ids <- data.frame(
  SOW = 1:nrow(data_list[[1]]),
  Neuron = best_som$unit.classif
)
write_parquet(x = neuron_ids, sink = file.path(output_dir, "som_sow_neuron_ids.parquet"))

# 6.3 Coordinates of each neuron on the SOM grid
neuron_coordinates <- data.frame(best_som$grid$pts)
write.csv(neuron_coordinates, file.path(output_dir, "som_neuron_coordinates.csv"), row.names = FALSE)

# 6.4 Update SOW info file to include neuron assignments
ff_sow_info <- read_parquet(here::here("data", "processed", "ff_sow_info.parquet"))
ff_sow_info$Neuron <- best_som$unit.classif

temp_path <- here::here("data", "processed", "ff_sow_info_temp.parquet")
write_parquet(ff_sow_info, sink = temp_path)
file.rename(temp_path, here::here("data", "processed", "ff_sow_info.parquet"))
