# Vector of packages you want to ensure are installed
packages <- c(
  "here", "glue", "arrow", "dplyr", "readxl", "magrittr", "nsga2R", "parallel", 
  "foreach", "doParallel", "ecr", "stats", "data.table", "lhs", "kohonen", 
  "plyr", "plotly", "htmlwidgets", "aweSOM", "clhs", "DiceDesign", "ggplot2",
  "kneedle"
)

# Install any that are missing
install_if_missing <- function(pkg_list) {
  # Find which packages are not installed
  missing <- pkg_list[!(pkg_list %in% installed.packages()[, "Package"])]
  
  # Install missing packages
  if (length(missing) > 0) {
    message("Installing missing packages: ", paste(missing, collapse = ", "))
    install.packages(missing, dependencies = TRUE)
  } else {
    message("All packages already installed.")
  }
}

# Run the install check
install_if_missing(packages)