"""
Generate Performance Layers for SOM Analysis.

This script creates performance-layer visualizations for a trained Self-Organizing Map (SOM).
For each policy–objective pair, it computes neuron-level average performance values and
renders condensed SOM figures with appropriate colorbars.

Inputs:
    - output/05_create_subsampled_ensemble/sampled_sow_info.parquet
    - output/07_consolidate_rw_output/reevaluation_objectives.parquet
    - output/03_final_som/som_neuron_coordinates.csv
    - src/configs/performance_layer_configs.py (POLICIES, OBJECTIVES, OBJECTIVES_SETTINGS)

Outputs (saved in /output/09_performance_layers):
    - Policy<PolicyID>__<Objective>_performance_layer.png
      e.g., Policy02__Avg_Mead_PE_performance_layer.png
"""

from dataclasses import dataclass
import logging
from pathlib import Path

import matplotlib
import pandas as pd
import numpy as np

from src.configs import performance_layer_configs
from src.utils import ids
from src.utils.functions_library import (
    create_condensed_som_figure,
    get_policy_reevaluation_data,
)

matplotlib.use("Qt5Agg")


# ---------------------------------
# --------- Configuration ---------
# ---------------------------------

@dataclass
class Config:
    base_dir: Path = Path(__file__).resolve().parent.parent  # goes up from /src/

    @property
    def sampled_sow_info_file(self) -> Path:
        return self.base_dir / "output/05_create_subsampled_ensemble/sampled_sow_info.parquet"

    @property
    def reevaluation_data_file(self) -> Path:
        return self.base_dir / "output/07_consolidate_rw_output/reevaluation_objectives.parquet"

    @property
    def neuron_coordinate_file(self) -> Path:
        return self.base_dir / "output/03_final_som/som_neuron_coordinates.csv"

    @property
    def output_dir(self) -> Path:
        return self.base_dir / "output/09_performance_layers"


# ---------------------------------
# ------- Utility Functions -------
# ---------------------------------

def create_and_save_performance_layer(
    policy_name: str,
    objective: str,
    neuron_values: pd.Series,
    neuron_coordinates: pd.DataFrame,
    settings: dict,
    output_dir: Path,
) -> None:
    """Render and save a condensed SOM figure for a single (policy, objective)."""
    scale = settings["scale"]
    positive = scale > 0
    color_scheme = "good_bad" if positive else "good_bad_reverse"

    # Scale values safely
    values_scaled = neuron_values / (scale if scale else 1.0)

    fig = create_condensed_som_figure(
        title=f"Policy {policy_name}\nObjective View: {settings['label']}",
        colorbar_label=f"Neuron Average {settings['label_w_unit']}",
        neuron_values=values_scaled.tolist(),
        neuron_coordinates=neuron_coordinates,
        color_scheme=color_scheme,
        n_digits=settings["n_digits"],
        inverse_colorbar=not positive,
        value_range=settings["range"],
    )

    output_file = output_dir / f"Policy{policy_name}__{objective}_performance_layer.png"
    fig.savefig(output_file, dpi=600, bbox_inches="tight")
    logging.info("Saved performance layer: %s", output_file)


def create_and_save_all_performance_layers(
    policies: dict,
    objectives: list,
    objective_settings: dict,
    sampled_sow_info: pd.DataFrame,
    reevaluation_data: pd.DataFrame,
    neuron_coordinates: pd.DataFrame,
    config: Config,
) -> None:
    """Loop through all policies and objectives to generate performance layers."""
    for policy_id, policy_name in policies.items():
        logging.info("Processing Policy: %s (ID=%02d)", policy_name, policy_id)

        policy_data = get_policy_reevaluation_data(
            reevaluation_data=reevaluation_data,
            sow_info=sampled_sow_info,
            policy=f"{policy_id:02}",
        )

        for objective in objectives:
            if objective not in objective_settings:
                logging.warning("Objective %s missing settings; skipping.", objective)
                continue

            settings = objective_settings[objective]
            objective_data = policy_data[[ids.NEURON, objective]]
            neuron_means = objective_data.groupby(ids.NEURON)[objective].mean()

            create_and_save_performance_layer(
                policy_name=policy_name,
                objective=objective,
                neuron_values=neuron_means,
                neuron_coordinates=neuron_coordinates,
                settings=settings,
                output_dir=config.output_dir,
            )


# ---------------------------------
# ------------- Main --------------
# ---------------------------------

def main(config: Config) -> None:
    """Run workflow: load data, compute performance layers, and save SOM visualizations."""
    logging.info("Starting performance layer generation...")

    policies = performance_layer_configs.POLICIES
    objectives = performance_layer_configs.OBJECTIVES
    objective_settings = performance_layer_configs.OBJECTIVES_SETTINGS

    sampled_sow_info = pd.read_parquet(config.sampled_sow_info_file).copy()
    sampled_sow_info["SOW"] = np.arange(1, sampled_sow_info.shape[0] + 1)

    reevaluation_data = pd.read_parquet(config.reevaluation_data_file)
    neuron_coordinates = pd.read_csv(config.neuron_coordinate_file)

    config.output_dir.mkdir(parents=True, exist_ok=True)

    create_and_save_all_performance_layers(
        policies, objectives, objective_settings,
        sampled_sow_info, reevaluation_data, neuron_coordinates, config
    )

    logging.info("Performance layer generation complete. Results saved to %s", config.output_dir)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    main(Config())
