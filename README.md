# **M**apping **A**lternative **P**erformance across **S**OWs (MAPS) Framework

This repository contains the codebase accompanying the paper “…”. This README provides an overview of the repository structure, instructions for cloning the project, and guidance on which scripts can be executed directly from the cloned version. Due to GitHub storage limitations, some large intermediary datasets (e.g., raw CRSS outputs) could not be uploaded. However, all essential datasets required to reproduce the figures—such as SOW characteristics and objective values from all simulations—are included. As a result, not every script is fully runnable from the cloned repository, but all are provided to document the complete analytical workflow.

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
├── MAPS-Framework.Rproj
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
- **`07_consolidate_riverware_output.R`** — Consolidates objective values from all CRSS simulations into a single file.
- **`08_condition_layers.py`** — Creates condition layers for the SOW Map, including feature (e.g., initial combined storage) and non-feature (e.g., median annual flow) layers.
- **`09_performance_layers.py`** — Creates performance layers for Alternatives A, B, and Compromise for multiple objectives, including Powell 3525 and LB Delivery Reduction.

### `output/` directory

Contains subdirectories associated with each of the main `src` scripts, storing their respective outputs. These may include generated figures, intermediate datasets, and other artifacts produced during the analysis.

### `maps_env.yaml`

Specifies the Conda environment used in this project for running the Python components, including Python 3.10 and core dependencies such as NumPy, Pandas, scikit-learn, Matplotlib, PyQt, and PyArrow.

### `MAPS-Framework.Rproj`

RStudio project file that configures the working directory.

## Cloning and Running

It is not likely that 

## Cloning the Repository

To obtain a local copy of the repository, clone it using Git:

```bash
git clone https://github.com/madrpernat/MAPS-Framework.git
cd MAPS-Framework
```

If you do not have Git installed, you can also download the repository as a ZIP file directly from the GitHub interface: **Code → Download ZIP**. After downloading, extract the ZIP archive to your preferred directory to access the project files.

## Environment Setup

### Python

The recommended way to create the Python environment is to use Conda with the specifications provided in `maps_env.yaml`. If you do not already have Conda installed, a lightweight installer such as [Miniconda](https://docs.conda.io/en/latest/miniconda.html) is recommended.

To create the environment, run (from the project root):

```bash
conda env create -f maps_env.yaml
```

### R

[R](https://cran.r-project.org/) must be installed to run the R components of this project. The primary R scripts source a utility file (`src/utils/install_packages.R`) that installs required packages automatically (if missing) when each script is executed. Therefore, no additional configuration is necessary beyond having R (we used version 4.2.3) available on your system.

## How to Run

### Python

The Python scripts in this project can be run through an IDE (which is what we did—using PyCharm, with steps provided below) or from the command line if desired.

#### PyCharm

1. Open the project folder (`MAPS-Framework`) in PyCharm.
2. Ensure the project interpreter is set to the Conda environment created from `maps_env.yaml`.
3. In the file browser, open the desired script inside the `src/` directory.
4. Run the script using the green forward-arrow button above the editor window.

PyCharm automatically handles the working directory and resolves imports such as `from src.utils import …` without requiring additional configuration.

#### Command Line

Scripts can also be executed directly from the command line. When doing so, they must be run in module form so that Python correctly interprets `src` as the project’s module directory.

1) Activate the Conda environment:

    ```bash
    conda activate maps_env
    ```

2) From the project root:

    ```bash
    python -m src.<script_name without file extension>
    ```

    For example:

    ```bash
    python -m src.01_create_sow_ensemble
    ```

    This ensures that imports (`from src.utils import …`) function correctly when running outside the IDE.

### R

We recommend running R scripts from within [RStudio](https://posit.co/download/rstudio-desktop/).

1. Open the project using the provided `MAPS-Framework.Rproj` file to ensure the working directory is correctly set to the project root. This ensures that relative paths resolve correctly.
2. Navigate to the desired script, open it, and execute it within the RStudio environment.

## Which Scripts Can Be Run

The list below summarizes which scripts can be run using only the data provided in the repository, as well as which scripts depend on outputs generated by earlier steps.

1. **01_create_sow_ensemble.py** — Can be run.
2. **02_som_hyperparameter_tuning.R** — Can be run after Script 01 has been executed. However, all relevant outputs are already included in `output/02_som_hyperparameter_tuning/`.
3. **03_best_som.R** — Can be run after Script 01 has been executed. However, all relevant outputs are already included in `output/03_best_som/`.
4. **04_subsampling_experiment.R** — Can be run after Script 01 has been executed. However, all relevant outputs are already included in `output/04_subsampling_experiment/`.
5. **05_create_subsampled_ensemble.R** — Can be run after Script 01 has been executed. However, all relevant outputs are already included in `output/05_create_subsampled_ensemble/`.
6. **06_sow_input_files_for_riverware.R** — Cannot be run (required input data is not included in the repository).
7. **07_consolidate_riverware_output.R** — Cannot be run (required input data is not included in the repository).
8. **08_condition_layers.py** — Can be run after Script 01 has been executed. Users may run this script if they want to create condition layers beyond those specified in `src/configs/condition_layer_configs.py` (i.e., beyond those already in `output/condition_layers/`).
9. **09_performance_layers.py** — Can be run. Users may run this script if they want to create performance layers beyond those specified in `src/configs/condition_layer_configs.py` (i.e., beyond those already in `output/performance_layers/`).

The scripts that cannot be run (Scripts 06 and 07) rely on a directory called `RiverSMART/`, which contained the full CRSS model setup, policy and SOW input files, and the associated simulation outputs. These files were too large to include in the repository, and therefore the components of the workflow that depend on them cannot be executed from the cloned version.
