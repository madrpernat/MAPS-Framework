"""
Generate Condition Layers for SOM Analysis.

This script creates condition-layer visualizations for a trained Self-Organizing Map (SOM).
It produces:
    - Cumulative time series plots of sampled SOWs.
    - Boxplot views of selected characteristics (flow, demand, initial storage).
    - Condensed SOM figures showing neuron-level averages.

Outputs (saved in /output/08_condition_layers):
    - som_cumulative_timeseries_view.png
    - <Characteristic>_boxplot_view.png
    - <Characteristic>_neuron_avg_view.png
"""

from dataclasses import dataclass
import logging
from pathlib import Path

import matplotlib
import matplotlib.pyplot as plt
import pandas as pd

from src.utils import ids
from src.configs import condition_layer_configs
from src.utils.functions_library import (
    create_cumulative_timeseries_som_view,
    create_condensed_som_figure,
    create_boxplot_som_view,
)

matplotlib.use("Qt5Agg")


# ---------------------------------
# --------- Configuration ---------
# ---------------------------------

@dataclass
class Config:
    base_dir: Path = Path(__file__).resolve().parent.parent  # goes up from /src/
    start_year: int = 2027
    end_year: int = 2057

    @property
    def ff_cfd_file(self) -> Path:
        return self.base_dir / "data/processed/ff_cfd.parquet"

    @property
    def ff_info_file(self) -> Path:
        return self.base_dir / "data/processed/ff_sow_info.parquet"

    @property
    def sampled_cfd_file(self) -> Path:
        return self.base_dir / "output/05_create_subsampled_ensemble/sampled_sow_cfd.parquet"

    @property
    def sampled_info_file(self) -> Path:
        return self.base_dir / "output/05_create_subsampled_ensemble/sampled_sow_info.parquet"

    @property
    def neuron_coordinate_file(self) -> Path:
        return self.base_dir / "output/03_final_som/som_neuron_coordinates.csv"

    @property
    def sow_neuron_ids_file(self) -> Path:
        return self.base_dir / "output/03_final_som/som_sow_neuron_ids.parquet"

    @property
    def output_dir(self) -> Path:
        return self.base_dir / "output/08_condition_layers"


# ---------------------------------
# ------- Utility Functions -------
# ---------------------------------

def save_cumulative_timeseries_plot(sampled_info, sampled_cfd, config: Config) -> None:
    """Generate and save cumulative timeseries SOM view for sampled SOWs."""
    fig = create_cumulative_timeseries_som_view(
        sow_info=sampled_info,
        sow_cumulative_timeseries=sampled_cfd,
        start_year=config.start_year,
        end_year=config.end_year,
        x_ticks=condition_layer_configs.CUMULATIVE_PLOT_X_TICKS,
        y_ticks=condition_layer_configs.CUMULATIVE_PLOT_Y_TICKS,
        color="blue"
    )
    output_file = config.output_dir / "som_cumulative_timeseries_view.png"
    fig.savefig(output_file, dpi=600, bbox_inches="tight")
    logging.info("Saved cumulative timeseries plot: %s", output_file)


def save_characteristic_plots(ff_info, neuron_coordinates, config: Config) -> None:
    """Generate boxplot and neuron-average SOM figures for selected characteristics."""
    characteristics = [ids.MEDIAN_FLOW, ids.DEMAND, ids.INIT_STORAGE]

    for characteristic in characteristics:
        logging.info("Processing characteristic: %s", characteristic)

        # --- Boxplot view ---
        fig = create_boxplot_som_view(
            sow_info=ff_info,
            feature=characteristic,
            y_ticks=condition_layer_configs.BOXPLOT_Y_TICKS.get(characteristic),
            color="blue",
        )
        output_file = config.output_dir / f"{characteristic}_boxplot_view.png"
        fig.savefig(output_file, dpi=600, bbox_inches="tight")
        logging.info("Saved boxplot view: %s", output_file)

        # --- Neuron-averaged SOM view ---
        avg_value_per_neuron = ff_info.groupby(ids.NEURON)[characteristic].mean().tolist()
        fig = create_condensed_som_figure(
            title="SOW Map Condition Layer",
            colorbar_label="Neuron Average "
            + condition_layer_configs.PLOT_TITLES.get(characteristic),
            neuron_values=avg_value_per_neuron,
            neuron_coordinates=neuron_coordinates,
            color_scheme=condition_layer_configs.COLOR_SCHEMES.get(characteristic),
            n_digits=1,
            inverse_colorbar=condition_layer_configs.INVERSE_COLORBAR.get(characteristic),
            value_range=condition_layer_configs.COLORBAR_RANGES.get(characteristic),
        )
        output_file = config.output_dir / f"{characteristic}_neuron_avg_view.png"
        fig.savefig(output_file, dpi=600, bbox_inches="tight", transparent=True)
        logging.info("Saved neuron-averaged SOM view: %s", output_file)


# ---------------------------------
# ------------- Main --------------
# ---------------------------------

def main(config: Config) -> None:
    """Run workflow: load data, generate cumulative plots, and save condition-layer views."""
    logging.info("Starting condition-layer generation...")

    ff_sow_info = pd.read_parquet(config.ff_info_file)
    sampled_sow_info = pd.read_parquet(config.sampled_info_file)
    sampled_cfd = pd.read_parquet(config.sampled_cfd_file)
    neuron_coordinates = pd.read_csv(config.neuron_coordinate_file)

    # Add Neuron column to ff_sow_info if it doesn't have it (needed if you cloned the repo and did NOT
    # run 03_best_som.R on your own
    if ids.NEURON not in ff_sow_info.columns:
        neurons = pd.read_parquet(config.sow_neuron_ids_file)
        ff_sow_info[ids.NEURON] = neurons["Neuron"].astype("int")

    config.output_dir.mkdir(parents=True, exist_ok=True)

    save_cumulative_timeseries_plot(sampled_sow_info, sampled_cfd, config)
    save_characteristic_plots(ff_sow_info, neuron_coordinates, config)

    logging.info("Condition-layer generation complete. Results saved to %s", config.output_dir)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    main(Config())
