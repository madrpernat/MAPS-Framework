# ==============================================================================
# SOM Error Functions
#   - Total sum of squares
#   - Percent variance explained
#   - Topographic error (parallelized)
# ==============================================================================

library(nsga2R)
library(parallel)
library(foreach)
library(doParallel)
library(ecr)

# ------------------------------------------------------------------------------
# Calculate total sum of squares (SS) for given data and weights
# ------------------------------------------------------------------------------
calc_total_ss <- function(data_list, user_weights, distance_metric) {

  custom_distance <- function(data_point, code1, code2, weight1, weight2, metric) {
    if (metric == "euclidean") {
      dist1 <- sqrt(sum((data_point[[1]] - code1)^2))
      dist2 <- sqrt(sum((data_point[[2]] - code2)^2))
    } else if (metric == "manhattan") {
      dist1 <- sum(abs(data_point[[1]] - code1))
      dist2 <- sum(abs(data_point[[2]] - code2))
    } else if (metric == "sumofsquares") {
      dist1 <- sum((data_point[[1]] - code1)^2)
      dist2 <- sum((data_point[[2]] - code2)^2)
    } else {
      stop("Invalid distance metric. Choose 'euclidean', 'manhattan', or 'sumofsquares'.")
    }
    return(weight1 * dist1 + weight2 * dist2)
  }

  data_matrix <- cbind(data_list[[1]], data_list[[2]])
  centroid <- colMeans(data_matrix)

  total_ss <- sum(sapply(1:nrow(data_matrix), function(data_index) {
    custom_distance(
      list(data_list[[1]][data_index, ], data_list[[2]][data_index]),
      centroid[1:30],
      centroid[31],
      user_weights[1], user_weights[2],
      distance_metric
    )^2
  }))

  return(total_ss)
}

# ------------------------------------------------------------------------------
# Calculate percent variance explained by a SOM
# ------------------------------------------------------------------------------
calc_percent_var_explained <- function(som, total_ss) {
  quant_error <- sum((som$distances)^2)
  return(1 - (quant_error / total_ss))
}

# ------------------------------------------------------------------------------
# Calculate topographic error in parallel
# ------------------------------------------------------------------------------
topo_error_parallel <- function(som, num_cores) {

  custom_distance <- function(data_point, code1, code2, weight1, weight2) {
    dist1 <- sqrt(sum((data_point[[1]] - code1)^2))
    dist2 <- sqrt(sum((data_point[[2]] - code2)^2))
    return(weight1 * dist1 + weight2 * dist2)
  }

  data1 <- som$data[[1]]
  data2 <- som$data[[2]]
  codes1 <- som$codes[[1]]
  codes2 <- som$codes[[2]]
  weight1 <- som$user.weights[1]
  weight2 <- som$user.weights[2]
  bmus <- som$unit.classif

  compute_error_for_point <- function(i) {
    bmu1 <- bmus[i]

    distances <- sapply(1:nrow(codes1), function(code_index) {
      custom_distance(
        list(data1[i, ], data2[i, ]),
        codes1[code_index, ],
        codes2[code_index, ],
        weight1, weight2
      )
    })

    # Ignore BMU itself
    distances[bmu1] <- Inf
    bmu2 <- which.min(distances)

    unit1_coords <- som$grid$pts[bmu1, ]
    unit2_coords <- som$grid$pts[bmu2, ]
    dist <- dist(rbind(unit1_coords, unit2_coords), method = "euclidean")[1]

    if (dist > 1) return(1) else return(0)
  }

  cl <- makeCluster(num_cores)
  on.exit({
    stopCluster(cl)
    registerDoSEQ()
  })

  topographic_errors <- parLapply(cl, 1:nrow(data1), compute_error_for_point)

  return(sum(unlist(topographic_errors)) / nrow(data1))
}
