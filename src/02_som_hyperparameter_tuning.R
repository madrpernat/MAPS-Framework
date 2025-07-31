# ==============================================================================
# 1. Load Libraries and Utility Functions
# ==============================================================================

library(here)
source(here("src", "utils", "som_library.R"))
source(here("src", "utils", "error_functions.R"))

# ==============================================================================
# 2. Define Output Directory
# ==============================================================================

output_dir <- here::here("output", "som_hyperparameter_tuning")

# ==============================================================================
# 3. Load and Prepare Full-Factorial SOW Ensemble Data
# ==============================================================================
# Load cumulative flow less demand (CFD) data and system condition and demand 
# (SCD) data. Perform PCA to calculate principal components and prepare data for 
# fitting supersom.

# Load CFD data
cfd_data <- as.matrix(
  read_parquet(file = here::here("data", "processed", "ff_cfd_scaled.parquet"))
)
colnames(cfd_data) <- 2027:2056

# Load initial combined storage data
ic_data <- as.matrix(
  read_parquet(file = here::here("data", "processed", "ff_init_storage_scaled.parquet"))
)

# Combine CFD and initial storage data
combined_data <- cbind(cfd_data, ic_data)

# Calculate covariance matrix and perform eigen decomposition
cov_matrix <- cov(combined_data)
eigen_decomp <- eigen(cov_matrix)
rotation_matrix <- eigen_decomp$vectors[, 1:2]  # Select first two PCs

# Compute principal components
principal_components <- combined_data %*% rotation_matrix

# Calculate the ratio of the first two eigenvalues
eigen_ratio <- eigen_decomp$values[1] / eigen_decomp$values[2]

# Determine ranges for the first two principal components
pc1_range <- range(principal_components[, 1])
pc2_range <- range(principal_components[, 2])

# Define data list (format required for supersom) and user-defined weights
data_list <- list(cfd_data, ic_data)
user_weights <- c(0.25, 0.75)

# Clean up temporary objects to free memory
rm(
  ic_data, 
  cov_matrix, 
  eigen_decomp, 
  principal_components, 
  combined_data, 
  cfd_data, 
  ic_data
)
gc()

# ==============================================================================
# 4. Sample Configurations with Latin Hypercube Sampling
# ==============================================================================
# Sample hyperparameter configurations using Latin Hypercube Sampling (LHS).
# Map the sampled unit cube to specified hyperparameter ranges for continuous
# and discrete variables.

# Define the number of samples
n_samples <- 1000

# Generate the Latin Hypercube Sample
cube <- as.data.frame(improvedLHS(n = n_samples, k = 4))
colnames(cube) <- c("radius", "y_dim", "x_y_ratio", "neighborhood_fnc")

# Define ranges for continuous hyperparameters
radius_range <- c(0.5, 1)
y_dim_range <- c(3, 5)
x_y_ratio_range <- c(floor(sqrt(eigen_ratio)), ceiling(eigen_ratio))

# Define options for discrete hyperparameters
neighborhood_fnc_opts <- c("gaussian", "bubble")

# Map cube samples (value between 0-1) to continuous hyperparameter ranges
cube$radius <- qunif(
  cube$radius, 
  min = radius_range[1], 
  max = radius_range[2]
)

cube$y_dim <- round(qunif(
  cube$y_dim,
  min = y_dim_range[1] - 0.5,
  max = y_dim_range[2] + 0.5
))

cube$x_y_ratio <- qunif(
  cube$x_y_ratio,
  min = x_y_ratio_range[1],
  max = x_y_ratio_range[2]
)

# Map cube samples (value between 0-1) to discrete hyperparameter options
neighborhood_probs <- seq(0, 1, length.out = length(neighborhood_fnc_opts) + 1)
cube$neighborhood_fnc <- continuous_to_discrete(
  cube = cube$neighborhood_fnc,
  probs = neighborhood_probs,
  categories = neighborhood_fnc_opts
)

# Derive additional hyperparameters based on sampled values
cube$x_dim <- round(cube$y_dim * cube$x_y_ratio)
cube$n_neurons <- cube$y_dim * cube$x_dim

# Add a configuration ID and reorder columns
cube$ConfigID <- 1:n_samples
all_configs <- cube[, c(7, 1:6)]

# Save the configurations
write.csv(
  x = all_configs,
  file = file.path(output_dir, "all_configs.csv"),
  row.names = FALSE
)

# Visualize hyperparameter distributions
hist(
  all_configs$radius, 
  main = "Distribution of Radius", 
  xlab = "Radius"
)
hist(
  all_configs$y_dim, 
  main = "Distribution of Y Dimension", 
  xlab = "Y Dimension"
)
hist(
  all_configs$x_y_ratio, 
  main = "Distribution of X/Y Ratio", 
  xlab = "X/Y Ratio"
)
hist(
  all_configs$n_neurons, 
  main = "Distribution of Number of Neurons", 
  xlab = "Number of Neurons"
)
table(all_configs$neighborhood_fnc)

# Clean up temporary objects
rm(
  cube, 
  radius_range, 
  y_dim_range, 
  x_y_ratio_range, 
  neighborhood_fnc_opts, 
  neighborhood_probs, 
  n_samples
)
gc()


# ==============================================================================
# 5. Perform Successive Non-Dominated Pruning
# ==============================================================================

# ------------------------------------------------------------------------------
# Define Search Parameters
# ------------------------------------------------------------------------------

n_configs_each_round <- c(1000, 500, 250, 125, 63, 32)
subset_data_size <- c(58970, 148126, 372076, 934612, 2347638, 5897000)
total_data_size <- nrow(data_list[[1]])

# ------------------------------------------------------------------------------
# Successive Non-Dominated Pruning (repeat twice)
# ------------------------------------------------------------------------------

for (i in 1:2){
  
  # Start with all configurations
  current_configs <- 1:1000
  
  for (j in seq_along(n_configs_each_round)){
    
    # --------------------------------------------------------------------------
    # Sample Data for the Current Iteration
    # --------------------------------------------------------------------------
    sample <- sample(
      x = total_data_size, 
      size = subset_data_size[j]
    )
    temp_data_list <- list(
      data_list[[1]][sample, ],
      data_list[[2]][sample]
    )
    
    # Calculate total sum of squares of sample (for % Var. Explained later)
    total_ss_euclidean <- calc_total_ss(
      data_list=temp_data_list, 
      user_weights=user_weights, 
      distance_metric="euclidean"
    )
    
    # Initialize lists to store objectives
    n_neurons <- c()
    vars <- c()
    topos <- c()
    
    # --------------------------------------------------------------------------
    # Evaluate Each Configuration Fit to THIS ITERATION'S Sample Data
    # --------------------------------------------------------------------------
    
    for (k in current_configs){
      
      # Extract configuration parameters
      config <- all_configs[all_configs$ConfigID == k, ]
      ydim <- config$y_dim
      xdim <- config$x_dim
      n_neuron <- config$n_neurons
      neighborhood_fnc <- config$neighborhood_fnc
      radius_fraction <- config$radius
      
      # Display configuration details
      print(paste(
        "Y =", ydim, 
        ", X =", xdim, 
        ", N =", n_neuron, 
        ", neighbor=", neighborhood_fnc, 
        ", radius =", radius_fraction, 
        ", subset data size =", subset_data_size[j],
        ", iteration =", i
      ))
      
      # Calculate initial neighborhood radius
      init_radius <- quantile2radius(
        fraction=radius_fraction,
        x=xdim, 
        y=ydim,
        shape='hexagonal'
      )
      
      # Generate neuron initialization matrices
      d1 <- seq(from = pc1_range[1], to = pc1_range[2], length.out = xdim)
      d2 <- seq(from = pc2_range[1], to = pc2_range[2], length.out = ydim)
      pc_grid <- expand.grid(d1, d2)
      init <- as.matrix(pc_grid) %*% t(rotation_matrix)

      init1 = as.matrix(init[, 1:30], ncol=30)  # flow/dem
      init2 = as.matrix(init[, 31], ncol=1)     # initial storage
      
      # Train the superSOM
      som <- supersom(
        data=temp_data_list,
        radius=init_radius,
        dist.fcts='euclidean',
        grid=somgrid(
          xdim=xdim,
          ydim=ydim,
          topo='hexagonal',
          toroidal=FALSE,
          neighbourhood.fct = neighborhood_fnc
        ),
        user.weights = user_weights,
        rlen=24,
        keep.data=TRUE,
        init=list(init1, init2),
        mode='pbatch',
        cores = -1,
        normalizeDataLayers = FALSE
      )
      
      # Calculate objectives/fit metrics (% Variance Explained and Topo Error)
      var_explained <- -1 * calc_percent_var_explained(som, total_ss_euclidean)
      topo_error <- topo_error_parallel(som=som, num_cores = 15)
      
      # Store and print objectives
      vars <- c(vars, var_explained)
      topos <- c(topos, topo_error)
      n_neurons <- c(n_neurons, n_neuron)
      
      print(c('percent var:', var_explained))
      print(c('topo error:', topo_error))
      
    }
    
    # --------------------------------------------------------------------------
    # Perform Non-Dominated Sorting
    # --------------------------------------------------------------------------
    
    # Perform non-dominated sorting based on our objective values
    objectives <- cbind(n_neurons, vars, topos)
    fronts <- fastNonDominatedSorting(objectives)
    
    # Assign a "front number" to each configuration
    front_column <- rep(NA, nrow(objectives))
    for (m in seq_along(fronts)){
      front_column[fronts[[m]]] <- m
    }
    
    # Create df to store configuration details, performance metrics, and front
    config_performance_df <- cbind(
      all_configs[match(current_configs, all_configs$ConfigID), ],
      vars,
      topos,
      front_column
    )
    colnames(config_performance_df) <- c(
      colnames(all_configs), 
      'Pct.Var.Explained', 
      'Topo.Error', 
      'Front'
    )
    
    # Save the configuration performance data for the current iteration
    output_file <- file.path(
      paste0("round", i), 
      paste0(n_configs_each_round[j], "configs.csv")
    )
    
    write.csv(
      x = config_performance_df,
      file = file.path(output_dir, output_file),
      row.names = FALSE
    )
    
    # --------------------------------------------------------------------------
    # Determine Configurations to Keep for Next Iteration
    # --------------------------------------------------------------------------
    # Select configurations for the next round based on non-dominated sorting.
    # Always retain all configurations from Front 1, and if necessary, truncate 
    # configurations from subsequent fronts using crowding distance.
    
    if (j < length(n_configs_each_round)){
      
      n_configs_to_keep <- n_configs_each_round[j + 1]
      
      if (n_configs_to_keep < length(fronts[[1]])){
        
        # Always keep all of Front 1
        current_configs <- config_performance_df[
          config_performance_df$Front == 1, 
          ]$ConfigID
        
      }else{
        
        # Calculate crowding distances
        cd <- crowdingDist4frnt(
          config_performance_df,
          fronts,
          apply(objectives, 2, max) - apply(objectives, 2, min)
        )
        cd_sum <- rowSums(cd)
        
        # Determine which Front needs to be truncated
        n_configs = 0
        current_front = 0
        while (n_configs < n_configs_to_keep){
          current_front <- current_front + 1
          n_configs <- n_configs + length(fronts[[current_front]])
        }
        front_to_truncate <- current_front
        
        # Extract row indices for the front to truncate
        trunc_front_idx <- fronts[[front_to_truncate]]
        
        # Create a dataframe for crowding distances in the truncated front
        cd_for_front <- data.frame(
          ConfigID = config_performance_df[trunc_front_idx, ]$ConfigID,
          CrowdingDistance = cd_sum[trunc_front_idx]
        )
        cd_for_front <- cd_for_front[
          order(cd_for_front$CrowdingDistance, decreasing = TRUE), 
        ]
        
        # Combine configs from full fronts and truncated front
        current_configs <- unlist(lapply(1:(front_to_truncate - 1), function(f){
          config_performance_df[fronts[[f]], ]$ConfigID
        }))
        n_left <- n_configs_to_keep - length(current_configs)
        current_configs <- c(current_configs, cd_for_front$ConfigID[1:n_left])
        
      }
    }
  }
}

# ==============================================================================
# 6. Visualize Results
# ==============================================================================

# Load the configuration data for the best-performing configurations
round1 <- read.csv(file.path(output_dir, "round1", "32configs.csv"))
round2 <- read.csv(file.path(output_dir, "round2", "32configs.csv"))

# Combine and remove duplicate configurations based on ConfigID
best_configs <- bind_rows(round1, round2) %>% 
  distinct(ConfigID, .keep_all = TRUE)

# Perform non-dominated sorting on the objective values
sort_df <- best_configs[, c("n_neurons", "Pct.Var.Explained", "Topo.Error")]
sorted_fronts <- fastNonDominatedSorting(sort_df)

# Extract the configurations in the first front
front1_configs <- best_configs[sorted_fronts[[1]], ]

# ------------------------------------------------------------------------------
# Create a Parallel Coordinates Plot
# ------------------------------------------------------------------------------

fig <- front1_configs %>% 
  
  plot_ly(
    type='parcoords',
    line=list(
      color = ~Topo.Error, 
      hoverinfo = 'ConfigID', 
      width = 3
    ),
    dimensions = list(
      list(
        range = c(0, 1),
        label = "Radius", 
        values = ~radius
      ),
      list(
        range = c(9, 63),
        label = "X Dim", 
        values = ~x_dim
      ),
      list(
        range = c(3, 5),
        label = "Y Dim", 
        values = ~y_dim
      ),
      list(
        range = c(27, 315),
        label = "Number of Neurons", 
        values = ~n_neurons
      ),
      list(
        range = c(3, 13),
        label = "X/Y Ratio", 
        values = ~x_y_ratio
      ),
      list(
        range = c(-0.95, -0.72),
        label = "Pct.Var.Explained", 
        values = ~Pct.Var.Explained
      ),
      list(
        range = c(0, 0.7),
        label = "Topo Error", 
        values = ~Topo.Error
      )
    )
  )

# ------------------------------------------------------------------------------
# Style the Plot and Save as an Interactive HTML Widget
# ------------------------------------------------------------------------------

fig <- fig %>% 
  layout(
    margin = list(l = 100, r = 100, b = 10, t = 10, pad = 3), 
    font=list(size=16)
  )

saveWidget(
  as_widget(fig), 
  file.path(output_dir, 'config_pc_plot.html')
)


# ==============================================================================
# 7. Epoch test on selected configuration
# ==============================================================================
# Using the chosen configuration, assess whether the number of training epochs 
# affects the fit metrics.

# Select a configuration by ConfigID (e.g., from parallel coordinates plot)
selected_config_id <- 318

# Extract configuration parameters
x_dim <- all_configs$x_dim[selected_config_id]
y_dim <- all_configs$y_dim[selected_config_id]
neighborhood_fnc <- all_configs$neighborhood_fnc[selected_config_id]
radius_fraction <- all_configs$radius[selected_config_id]

# Calculate initial neighborhood radius
init_radius <- quantile2radius(
  fraction = radius_fraction,
  x = x_dim, 
  y = y_dim,
  shape = 'hexagonal'
)

# Construct neuron initialization matrix from PCA space
d1 <- seq(from = pc1_range[1], to = pc1_range[2], length.out = x_dim)
d2 <- seq(from = pc2_range[1], to = pc2_range[2], length.out = y_dim)
pc_grid <- expand.grid(d1, d2)
init_matrix <- as.matrix(pc_grid) %*% t(rotation_matrix)
init1 <- as.matrix(init_matrix[, 1:30], ncol = 30)
init2 <- as.matrix(init_matrix[, 31], ncol = 1)

# Calculate total sum of squares for full dataset
total_ss_euclidean <- calc_total_ss(
  data_list = data_list, 
  user_weights = user_weights, 
  distance_metric = "euclidean"
)

# Define range of epochs to test
epochs_to_test <- 12:36

# Initialize vectors to store results
vars <- c()
topos <- c()

# Loop over epoch values and fit SOM each time
for (epochs in epochs_to_test) {
  
  som <- supersom(
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
  
  # Evaluate objectives
  percent_var_explained <- -1 * calc_percent_var_explained(som, total_ss_euclidean)
  topo_error <- topo_error_parallel(som, 15)
  
  # Print progress
  print(glue::glue("Epochs: {epochs}, Pct.Var.Explained: {percent_var_explained}, Topo.Error: {topo_error}"))
  
  # Store results
  vars <- c(vars, percent_var_explained)
  topos <- c(topos, topo_error)
  
}

# Combine and save results
epoch_results <- data.frame(
  N.Epochs = epochs_to_test,
  Pct.Var.Explained = vars,
  Topo.Error = topos
)

write.csv(
  epoch_results,
  file = file.path(output_dir, "epoch_test.csv"),
  row.names = FALSE
)
