library(stats)
library(data.table)
library(lhs)
library(kohonen)
library(plyr)
library(dplyr)
library(plotly)
library(htmlwidgets)
library(aweSOM)

############################# SOM HELPER FUNCTIONS #############################
##################### Coded by Nathan Bonham - March 2022 ######################
################ (https://doi.org/10.1016/j.envsoft.2022.105491) ###############

# Function to transform continuous values to discrete categories
continuous_to_discrete <- function(unit_cube, probs, categories) {
  for (i in 1:(length(probs)-1)) {
    indices <- which(unit_cube > probs[i] & unit_cube <= probs[i+1])
    unit_cube[indices] <- categories[i]
  }
  return(unit_cube)
}


quantile2radius=function(fraction, x,y,shape){
  
  # I took this code from the source code of the supersom function in Kohonen 
  # package and turned it into a function to calculate the radius given a 
  # fraction of the max node-to-node distance
  
  grid = somgrid(x,y,shape)
  grid <- check.somgrid(grid)
  nhbrdist <- unit.distances(grid)
  radius = quantile(nhbrdist, fraction)
  
  return(radius)
  
}


check.somgrid=function (grd) # taken from Kohonen source code
{
  mywarn <- FALSE
  if (is.null(grd$toroidal)) {
    mywarn <- TRUE
    grd$toroidal <- FALSE
  }
  if (is.null(grd$neighbourhood.fct)) {
    mywarn <- TRUE
    grd$neighbourhood.fct <- factor("bubble", levels = c("bubble", 
                                                         "gaussian"))
  }
  if (mywarn) 
    warning("Added defaults for somgrid object - ",
            "you are probably using the somgrid function ", 
            "from the class library...")
  grd
}


unit.distances=function (grid, toroidal) # taken from Kohonen source code
{
  if (missing(toroidal)) 
    toroidal <- grid$toroidal
  if (!toroidal) {
    if (grid$topo == "hexagonal") {
      return(as.matrix(stats::dist(grid$pts)))
    }
    else {
      return(as.matrix(stats::dist(grid$pts, method = "maximum")))
    }
  }
  np <- nrow(grid$pts)
  maxdiffx <- grid$xdim/2
  maxdiffy <- max(grid$pts[, 2])/2
  result <- matrix(0, np, np)
  for (i in 1:(np - 1)) {
    for (j in (i + 1):np) {
      diffs <- abs(grid$pts[j, ] - grid$pts[i, ])
      if (diffs[1] > maxdiffx) 
        diffs[1] <- 2 * maxdiffx - diffs[1]
      if (diffs[2] > maxdiffy) 
        diffs[2] <- 2 * maxdiffy - diffs[2]
      if (grid$topo == "hexagonal") {
        result[i, j] <- sum(diffs^2)
      }
      else {
        result[i, j] <- max(diffs)
      }
    }
  }
  if (grid$topo == "hexagonal") {
    sqrt(result + t(result))
  }
  else {
    result + t(result)
  }
}
