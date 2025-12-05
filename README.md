# **M**apping **A**lternative **P**erformance across **S**OWs (MAPS) Framework

This repository contains the codebase accompanying the paper “A Framework for …”. This README provides an overview of the repository structure, instructions for cloning the project, and guidance on which scripts can be executed directly from the cloned version. Due to GitHub storage limitations, some large intermediary datasets (e.g., raw CRSS outputs) could not be uploaded. However, all essential datasets required to reproduce the figures—such as SOW characteristics and objective values from all simulations—are included. As a result, not every script is fully runnable from the cloned repository, but all are provided to document the complete analytical workflow.

## Repository Structure

```text
maps_project/
├── data/
│   ├── processed/
│   └── raw/
├── src/
│   ├── configs/
│   ├── utils/
│   ├── 01_create_sow_ensemble.py
│   ├── 02_som_hyperparameter_tuning.R
│   ├── 03_best_som.R
│   ├── 04_subsampling_experiment.R
│   ├── 05_create_subsampled_ensemble.R
│   ├── 06_sow_input_files_for_riverware.R
│   ├── 07_consolidate_riverware_output.R
│   ├── 08_condition_layers.py
│   └── 09_performance_layers.py
├── output/
├── .gitignore
├── maps_env.yaml
└── README.md
```

## Content Description

### `data/` directory

- **`raw/`** — Contains input datasets used in the analysis, including:
  - `natural_flow_traces.csv`: Annual natural flow values for each of the 5,970 streamflow traces.
  - `initial_condition_and_demand_samples.csv`: The set of 1,000 initial condition and demand samples.
  - `policy_decision_variables.csv`: Decision variables defining the alternatives.

- **`processed/`** — Populated after running `01_create_sow_ensemble.py`. Contains datasets describing the full-factorial (ff) State-of-the-World (SOW) ensemble, including:
  - SOW feature values  
  - Scaling factors associated with each feature  
  - Additional SOW metadata (e.g., median annual flow and other summary statistics)

### `src/` directory

- **`configs/`** — Contains configuration files specifying which condition and performance layers to create, along with certain visualization settings.
- **`utils/`** — Contains Python and R utility scripts that support the primary scripts in `src`.
- **`01_create_sow_ensemble.py`** — Processes the hydrologic traces and initial condition/demand samples to generate the full-factorial ensemble. Computes cumulative flow minus demand (cfd) time series, scales features for SOM input, and saves those data in
both unscaled and scaled form in `data/processed/`.
- **`02_som_hyperparameter_tuning.R`** — Samples SOM hyperparameter configurations using Latin Hypercube Sampling and evaluates them using Successive Non-Dominated Pruning.
- **`03_best_som.R`** — Trains a SOM (i.e., the SOW Map) using the selected hyperparameter configuration and outputs information such as prototype vectors and SOW-to-neuron assignments.
- **`04_subsampling_experiment.R`** — Implements a subsampling experiment to determine how many SOWs need to be sampled from each neuron to adequately represent the diversity and characteristics of the SOWs within each neuron.
- **`05_create_subsampled_ensemble.R`** — Creates the subsampled SOW ensemble for simulation by sampling SOWs from each neuron using Conditioned Latin Hypercube Sampling, based on the sample size identified in the previous script.
- **`06_sow_input_files_for_riverware.R`** — Generates the required input files for CRSS for each SOW in the subsampled ensemble.
- **`07_consolidate_riverware_output.R`** — Consolidates objective values from all simulation runs into a single file.
- **`08_condition_layers.py`** — Creates condition layers for the SOW Map, including feature (e.g., initial combined storage) and non-feature (e.g., median annual flow) layers.
- **`09_performance_layers.py`** — Creates performance layers for Alternatives A, B, and Compromise for multiple objectives, including Powell 3525 and LB Delivery Reduction.

### `output/` directory

Contains subdirectories associated with each of the main `src` scripts, storing their respective outputs. These may include generated figures, intermediate datasets, and other artifacts produced during the analysis.

### `maps_env.yaml`

Specifies the Conda environment used in this project for running the Python components, including Python 3.10 and core dependencies such as NumPy, Pandas, scikit-learn, Matplotlib, PyQt, and PyArrow.

## Cloning the Repository

To obtain a local copy of the repository, clone it using Git:

```bash
git clone https://github.com/madrpernat/MAPS-Framework.git
cd MAPS-Framework
```

If you do not have Git installed, you can also download the repository as a ZIP file directly from the GitHub interface: **Code → Download ZIP**. After downloading, extract the ZIP archive to your preferred directory to access the project files.

## Environment Setup

### Python

The recommended way to create the Python environment for this project is to use Conda with the specifications provided in `maps_env.yaml`. If you do not already have Conda installed, a lightweight installer such as [Miniconda](https://docs.conda.io/en/latest/miniconda.html) is recommended.

To create the environment, run:

```bash
# first, ensure you are in the project directory, then:
conda env create -f maps_env.yaml
```

### R

[R](https://cran.r-project.org/) must be installed to run the R components of this project. The primary R scripts source a utility file (`src/utils/install_packages.R`) that installs required packages automatically (if missing) when each script is executed. Therefore, no additional configuration is necessary beyond having R (we used version 4.2.3) available on your system.

