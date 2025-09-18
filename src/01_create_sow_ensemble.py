"""
Build Full-Factorial Ensemble of States of the World (SOWs).

This script processes hydrologic traces and initial condition/demand samples to generate a full-factorial (ff) ensemble.
It computes cumulative flow minus demand (CFD) time series, scales key variables for SOM input, and saves results in
both raw and scaled form.

Outputs (saved in /data/processed):
    - ff_sow_info.parquet
    - ff_cfd.parquet
    - ff_cfd_scaled.parquet
    - ff_cfd_scaling_factors.csv
    - ff_init_storage_scaled.parquet
    - ff_init_storage_scaling_factors.csv
"""

from dataclasses import dataclass
import logging
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.preprocessing import MinMaxScaler

from src.utils import ids
from src.utils.functions_library import calculate_trace_metrics


# ---------------------------------
# --------- Configuration ---------
# ---------------------------------

@dataclass
class Config:
    base_dir: Path = Path(__file__).resolve().parent.parent  # goes up from /src/
    start_year: int = 2027
    end_year: int = 2057

    @property
    def trace_file(self) -> Path:
        return self.base_dir / "data/raw/natural_flow_traces.csv"

    @property
    def ic_demand_file(self) -> Path:
        return self.base_dir / "data/raw/initial_condition_demand_samples.csv"

    @property
    def output_dir(self) -> Path:
        return self.base_dir / "data/processed"


# ---------------------------------
# ------- Utility Functions -------
# ---------------------------------

def load_and_filter_traces(filepath: Path, start_year: int, end_year: int) -> pd.DataFrame:
    """
    Load raw hydrologic trace data and filter to the target simulation years.

    The input file must be in tidy format: each row corresponds to a single year of a single trace (e.g., a 30-year
    trace is represented by 30 rows). The input file includes the following columns defined in `utils/ids.py`:

        - ids.YEAR : Simulation year
        - ids.TRACE : Unique trace identifier
        - ids.SCENARIO : Scenario identifier
        - ids.TRACE_NUMBER : Trace number within scenario
        - ids.LF_ANNUAL : Annual flow value

    Parameters
    ----------
    filepath : Path
        Path to the CSV file containing natural flow traces.
    start_year : int
        First year (inclusive) of the simulation period.
    end_year : int
        Last year (inclusive) of the simulation period.

    Returns
    -------
    pd.DataFrame
        Filtered DataFrame containing only the specified simulation years.
    """
    if not filepath.exists():
        raise FileNotFoundError(f"Trace file not found: {filepath}")

    df = pd.read_csv(filepath)

    required_cols = [ids.YEAR, ids.TRACE, ids.SCENARIO, ids.TRACE_NUMBER, ids.LF_ANNUAL]
    missing = [c for c in required_cols if c not in df.columns]
    if missing:
        raise ValueError(f"Trace file is missing required columns: {missing}")

    df = df[(df[ids.YEAR] >= start_year) & (df[ids.YEAR] <= end_year)]
    logging.info("Loaded %d rows of trace data for years %d–%d", len(df), start_year, end_year)
    return df


def load_ic_demand_samples(filepath: Path) -> pd.DataFrame:
    """
    Load initial condition and demand (SCD) samples.

    The input file is a CSV, where each row represents one sample of system state at the beginning of the simulation.
    It includes the following columns defined in `utils/ids.py`:

        - ids.DEMAND : Annual demand value applied to each trace
        - ids.INIT_STORAGE : Initial reservoir storage or system state value

    Parameters
    ----------
    filepath : Path
        Path to the CSV file containing initial condition and demand samples.

    Returns
    -------
    pd.DataFrame
        DataFrame of SCD samples.
    """
    if not filepath.exists():
        raise FileNotFoundError(f"SCD file not found: {filepath}")

    df = pd.read_csv(filepath)

    required_cols = [ids.DEMAND, ids.INIT_STORAGE]
    missing = [c for c in required_cols if c not in df.columns]
    if missing:
        raise ValueError(f"SCD file is missing required columns: {missing}")

    logging.info("Loaded %d system condition/demand samples", len(df))
    return df


def assemble_trace_info(trace_df: pd.DataFrame) -> pd.DataFrame:
    """
    Construct a summary table of trace identifiers and computed metrics.

    Parameters
    ----------
    trace_df : pd.DataFrame
        DataFrame of hydrologic trace data. Includes the columns defined by `ids.TRACE`, `ids.SCENARIO`, and `
        ids.TRACE_NUMBER` in `utils/ids.py`

    Returns
    -------
    pd.DataFrame
        DataFrame containing unique trace identifiers joined with trace-level summary metrics (e.g., mean, variance) as
        computed by `calculate_trace_metrics`.
    """
    base_info = trace_df[[ids.TRACE, ids.SCENARIO, ids.TRACE_NUMBER]].drop_duplicates().reset_index(drop=True)
    metrics = calculate_trace_metrics(trace_df)
    logging.info("Assembled trace info with %d unique traces", len(base_info))
    return pd.concat(objs=[base_info, metrics], axis=1)


def create_full_factorial_ensemble(
        traces_info: pd.DataFrame,
        ic_demand_samples: pd.DataFrame,
        n_traces: int
) -> pd.DataFrame:
    """
    Build a full-factorial ensemble of hydrologic traces and system conditions. Each trace is paired with every initial
    condition/demand sample.

    Parameters
    ----------
    traces_info : pd.DataFrame
        DataFrame of trace identifiers and metrics (from `assemble_trace_info`).
    ic_demand_samples : pd.DataFrame
        DataFrame of initial condition and demand sample values.
    n_traces : int
        Number of unique traces in `traces_info`.

    Returns
    -------
    pd.DataFrame
        Full-factorial ensemble DataFrame where each row represents one SOW.
    """
    ff_traces = traces_info.loc[traces_info.index.repeat(len(ic_demand_samples))].reset_index(drop=True)
    repeated_scd = pd.concat([ic_demand_samples] * n_traces, ignore_index=True)
    ff_ensemble = pd.concat(objs=[ff_traces, repeated_scd], axis=1)
    logging.info("Created full-factorial ensemble with %d SOWs", len(ff_ensemble))
    return ff_ensemble


def calculate_cumulative_flow_minus_demand(
        trace_df: pd.DataFrame,
        ff_ensemble_info: pd.DataFrame,
        n_years: int
) -> np.ndarray:
    """
    Compute cumulative (flow - demand) time series for each ensemble member.

    For each State of the World (SOW), the function subtracts annual demand from the corresponding hydrologic trace,
    then accumulates the differences across each year.

    Parameters
    ----------
    trace_df : pd.DataFrame
        DataFrame of hydrologic trace data
        (must include `ids.TRACE` and `ids.LF_ANNUAL`).
    ff_ensemble_info : pd.DataFrame
        Ensemble DataFrame containing trace identifiers and demand values
        (must include `ids.TRACE`, `ids.DEMAND`, and `ids.INIT_STORAGE`).
    n_years : int
        Number of years in the simulation period.

    Returns
    -------
    np.ndarray
        Array of shape (n_sow, n_years), where each row is a CFD time series
        for one ensemble member.
    """
    trace_array = trace_df[[ids.TRACE, ids.LF_ANNUAL]].to_numpy()
    ff_ensemble_array = ff_ensemble_info[[ids.TRACE, ids.DEMAND, ids.INIT_STORAGE]].to_numpy()

    n_sow = ff_ensemble_array.shape[0]
    cfd_array = np.zeros((n_sow, n_years))

    for i in range(n_sow):
        trace = ff_ensemble_array[i, 0]
        demand = ff_ensemble_array[i, 1]
        lf_annual = trace_array[trace_array[:, 0] == trace, 1]
        cfd_array[i, :] = np.cumsum(lf_annual - demand)

    logging.info("Computed CFD time series for %d SOWs", n_sow)
    return cfd_array


def save_ensemble_data(
    ensemble_df: pd.DataFrame,
    cfd_array: np.ndarray,
    output_dir: Path
) -> None:
    """
    Save ensemble metadata, CFD time series (raw and scaled), and scaling factors.

    Creates a set of parquet and CSV files in `output_dir` that contain:
      - SOW metadata (`ff_sow_info.parquet`)
      - CFD time series, raw (`ff_cfd.parquet`) and scaled (`ff_cfd_scaled.parquet`)
      - Scaling factors for CFD (`ff_cfd_scaling_factors.csv`)
      - Initial storage values, scaled (`ff_init_storage_scaled.parquet`)
      - Scaling factors for initial storage (`ff_init_storage_scaling_factors.csv`)

    Parameters
    ----------
    ensemble_df : pd.DataFrame
        DataFrame of the full-factorial ensemble (SOW metadata).
    cfd_array : np.ndarray
        CFD time series of shape (n_sow, n_years) for each ensemble member.
    output_dir : Path
        Directory where output files will be saved. Created if it does not exist.

    Returns
    -------
    None
    """
    output_dir.mkdir(parents=True, exist_ok=True)

    ensemble_df.to_parquet(output_dir / "ff_sow_info.parquet", index=False)
    logging.info("Saved SOW metadata")

    cfd_df = pd.DataFrame(cfd_array)
    cfd_df.to_parquet(output_dir / "ff_cfd.parquet", index=False)

    cfd_scaler = MinMaxScaler(feature_range=(0, 1))
    cfd_scaled = cfd_scaler.fit_transform(cfd_array)
    pd.DataFrame(cfd_scaled).to_parquet(output_dir / "ff_cfd_scaled.parquet", index=False)
    pd.DataFrame({"Min": cfd_scaler.data_min_, "Max": cfd_scaler.data_max_}).to_csv(
        output_dir / "ff_cfd_scaling_factors.csv", index=False
    )
    logging.info("Saved CFD timeseries and scaling factors")

    init_storage = ensemble_df[[ids.INIT_STORAGE]].to_numpy()
    init_storage_scaler = MinMaxScaler(feature_range=(0, 1))
    init_storage_scaled = init_storage_scaler.fit_transform(init_storage)
    pd.DataFrame(init_storage_scaled, columns=["InitStorage"]).to_parquet(
        output_dir / "ff_init_storage_scaled.parquet", index=False
    )
    pd.DataFrame({
        "Min": [init_storage_scaler.data_min_[0]],
        "Max": [init_storage_scaler.data_max_[0]]
    }).to_csv(output_dir / "ff_init_storage_scaling_factors.csv", index=False)
    logging.info("Saved initial storage values and scaling factors")


# ---------------------------------
# ------------- Main --------------
# ---------------------------------

def main(config: Config) -> None:
    """Run the workflow: load data, compute trace metrics, build ensemble, and save outputs."""
    logging.info("Starting ensemble generation...")

    sim_years = np.arange(config.start_year, config.end_year)
    n_years = len(sim_years)

    trace_df = load_and_filter_traces(config.trace_file, config.start_year, config.end_year)
    traces_info = assemble_trace_info(trace_df)
    n_traces = traces_info.shape[0]

    ic_demand_samples = load_ic_demand_samples(config.ic_demand_file)
    ff_ensemble_info = create_full_factorial_ensemble(traces_info, ic_demand_samples, n_traces)

    ff_cfd = calculate_cumulative_flow_minus_demand(trace_df, ff_ensemble_info, n_years)
    save_ensemble_data(ff_ensemble_info, ff_cfd, config.output_dir)

    logging.info("Ensemble generation complete. Results saved to %s", config.output_dir)


if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    main(Config())
