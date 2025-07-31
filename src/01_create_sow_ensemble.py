from dataclasses import dataclass
import numpy as np
import pandas as pd
from pathlib import Path
from sklearn.preprocessing import scale

from src.utils import ids
from src.utils.functions_library import calculate_trace_metrics


# ---------------------------------
# --------- Configuration ---------
# ---------------------------------

@dataclass
class Config:
    start_year: int = 2027
    end_year: int = 2057
    trace_file: Path = Path("data/raw/natural_flow_traces.csv")
    ic_demand_file: Path = Path("data/raw/initial_condition_demand_samples.csv")
    output_dir: Path = Path("data/processed")


# ---------------------------------
# ------- Utility Functions -------
# ---------------------------------

def load_and_filter_traces(filepath: Path, start_year: int, end_year: int) -> pd.DataFrame:
    """Load trace data and filter to the desired simulation years."""
    df = pd.read_csv(filepath)
    df = df[(df[ids.YEAR] >= start_year) & (df[ids.YEAR] <= end_year)]
    return df


def assemble_trace_info(trace_df: pd.DataFrame) -> pd.DataFrame:
    """Return trace identifiers and computed metrics."""
    base_info = trace_df[[ids.TRACE, ids.SCENARIO, ids.TRACE_NUMBER]].drop_duplicates().reset_index(drop=True)
    metrics = calculate_trace_metrics(trace_df)
    return pd.concat(objs=[base_info, metrics], axis=1)


def create_full_factorial_ensemble(
        traces_info: pd.DataFrame,
        ic_demand_samples: pd.DataFrame,
        n_traces: int
) -> pd.DataFrame:
    """Create a full-factorial ensemble of trace and system condition combinations."""
    ff_traces = traces_info.loc[traces_info.index.repeat(len(ic_demand_samples))].reset_index(drop=True)
    repeated_scd = pd.concat([ic_demand_samples] * n_traces, ignore_index=True)
    return pd.concat(objs=[ff_traces, repeated_scd], axis=1)


def calculate_cumulative_timeseries(trace_df: pd.DataFrame, ensemble_df: pd.DataFrame, n_years: int) -> np.ndarray:
    """Compute cumulative time series (trace - demand) for each SOW in the ensemble."""
    trace_array = trace_df[[ids.TRACE, ids.LF_ANNUAL]].to_numpy()
    ensemble_array = ensemble_df[[ids.TRACE, ids.DEMAND, ids.INIT_STORAGE]].to_numpy()

    n_sow = ensemble_array.shape[0]
    cum_ts_array = np.zeros((n_years, n_sow))

    for i in range(n_sow):
        trace = ensemble_array[i, 0]
        demand = ensemble_array[i, 1]
        init_storage = ensemble_array[i, 2]

        lf_annual = trace_array[trace_array[:, 0] == trace, 1]
        cum_ts_array[:, i] = np.cumsum(lf_annual - demand) + init_storage

    return cum_ts_array


def save_ensemble_data(ensemble_df: pd.DataFrame, cumulative_timeseries_array: np.ndarray, output_dir: Path) -> None:
    """Save SOW metadata, raw and scaled cumulative time series, and scaling factors."""
    output_dir.mkdir(parents=True, exist_ok=True)

    # Save SOW info (one row per SOW)
    ensemble_df.to_csv(output_dir / "ff_sow_info.csv", index=False)

    # Save cumulative time series (columns = SOWs, rows = years)
    np.savetxt(output_dir / "ff_cumulative_timeseries.csv", cumulative_timeseries_array, delimiter=",")

    # Scale cumulative time series (for SOM input) and save
    cum_ts_scaled = scale(cumulative_timeseries_array.T)
    np.savetxt(output_dir / "ff_cumulative_timeseries_scaled.csv", cum_ts_scaled, delimiter=",")

    # Save mean and std used for scaling (along time axis)
    means = np.mean(cumulative_timeseries_array, axis=1)
    stds = np.std(cumulative_timeseries_array, axis=1)
    pd.DataFrame({'Mean': means, 'Std': stds}).to_csv(
        output_dir / "ff_cumulative_timeseries_scaling_factors.csv", index=False
    )


# ---------------------------------
# ------------- Main --------------
# ---------------------------------
def main(config: Config) -> None:
    # Set simulation years
    sim_years = np.arange(config.start_year, config.end_year)
    n_years = len(sim_years)

    # Load and filter raw hydrologic trace data
    trace_df = load_and_filter_traces(config.trace_file, config.start_year, config.end_year)

    # Compute summary metrics for each trace
    traces_info = assemble_trace_info(trace_df)
    n_traces = traces_info.shape[0]

    # Load initial condition and demand samples
    ic_demand_samples = pd.read_csv(config.ic_demand_file)

    # Create full-factorial (ff) ensemble (all combinations of traces and initial conditions)
    ff_ensemble = create_full_factorial_ensemble(traces_info, ic_demand_samples, n_traces)

    # Compute cumulative time series for each SOW in the ff ensemble
    ff_ensemble_cumulative_timeseries = calculate_cumulative_timeseries(trace_df, ff_ensemble, n_years)

    # Save results
    save_ensemble_data(ff_ensemble, ff_ensemble_cumulative_timeseries, config.output_dir)


if __name__ == '__main__':
    main()
