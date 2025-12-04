# **M**apping **A**lternative **P**erformance across **S**OWs (MAPS) Framework

This repository contains the codebase accompanying the paper “A Framework for …”. It provides an overview of the repository structure, instructions for cloning the project, and guidance on which scripts can be executed directly from the cloned version. Due to GitHub storage limitations, some large intermediary datasets (e.g., raw CRSS outputs) could not be uploaded. However, all essential datasets required to reproduce the figures—such as SOW characteristics and objective values from all simulations—are included. As a result, not every script is fully runnable from the cloned repository, but all are provided to document the complete analytical workflow and to illustrate each technical step used in the study.

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

- **`processed/`** — Populated after running `01_create_sow_ensemble.py`. Contains datasets describing the full-factorial State-of-the-World (SOW) ensemble, including:
  - SOW feature values  
  - Scaling factors associated with each feature  
  - Additional SOW metadata (e.g., median annual flow and other summary statistics)

### `src/` directory

- **`configs/`** — Configuration files defining which condition and performance layers to create and some specific visual settings.
- **`utils/`** — Python and R utility scripts that support the primary scripts in `src`.
- **`01_create_sow_ensemble.py`** —
- **`02_som_hyperparameter_tuning.R`** —
- **`03_best_som.R`** —
- **`04_subsampling_experiment.R`** —
- **`05_create_subsampled_ensemble.R`** —
- **`06_sow_input_files_for_riverware.R`** —
- **`07_consolidate_riverware_output.R`** —
- **`08_condition_layers.py`** —
- **`09_performance_layers.py`** —

### `output/` directory

- Contains subdirectories associated with each of the main `src` scripts, storing their respective outputs. These may include generated figures, intermediate datasets, and other artifacts produced during the analysis.
