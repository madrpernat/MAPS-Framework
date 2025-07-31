from dataclasses import dataclass
import numpy as np
import pandas as pd
from pathlib import Path
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


def calculate_cumulative_flow_minus_demand(
        trace_df: pd.DataFrame,
        ensemble_df: pd.DataFrame,
        n_years: int
) -> np.ndarray:
    """Compute cumulative time series (trace - demand) for each SOW in the ensemble."""
    trace_array = trace_df[[ids.TRACE, ids.LF_ANNUAL]].to_numpy()
    ensemble_array = ensemble_df[[ids.TRACE, ids.DEMAND, ids.INIT_STORAGE]].to_numpy()

    n_sow = ensemble_array.shape[0]
    cfd_array = np.zeros((n_sow, n_years))

    for i in range(n_sow):
        trace = ensemble_array[i, 0]
        demand = ensemble_array[i, 1]

        lf_annual = trace_array[trace_array[:, 0] == trace, 1]
        cfd_array[i, :] = np.cumsum(lf_annual - demand)

    return cfd_array


def save_ensemble_data(
    ensemble_df: pd.DataFrame,
    cfd_array: np.ndarray,
    output_dir: Path
) -> None:
    """Save SOW metadata, raw and scaled CFD timeseries, scaled init storage, and scaling factors."""
    output_dir.mkdir(parents=True, exist_ok=True)

    # Save SOW info
    ensemble_df.to_parquet(output_dir / "ff_sow_info.parquet", index=False)

    # Save CFD timeseries
    cfd_df = pd.DataFrame(cfd_array)
    cfd_df.to_parquet(output_dir / "ff_cfd.parquet", index=False)

    # Scale CFD timeseries (for SOM input)
    cfd_scaler = MinMaxScaler(feature_range=(0, 1))
    cfd_scaled = cfd_scaler.fit_transform(cfd_array)
    pd.DataFrame(cfd_scaled).to_parquet(output_dir / "ff_cfd_scaled.parquet", index=False)

    # Save CFD scaling factors (CSV)
    pd.DataFrame({
        'Min': cfd_scaler.data_min_,
        'Max': cfd_scaler.data_max_
    }).to_csv(output_dir / "ff_cfd_scaling_factors.csv", index=False)

    # Scale INIT_STORAGE column
    init_storage = ensemble_df[[ids.INIT_STORAGE]].to_numpy()
    init_storage_scaler = MinMaxScaler(feature_range=(0, 1))
    init_storage_scaled = init_storage_scaler.fit_transform(init_storage)
    pd.DataFrame(init_storage_scaled, columns=["InitStorage"]).to_parquet(
        output_dir / "ff_init_storage_scaled.parquet", index=False
    )

    # Save INIT_STORAGE scaling factors (CSV)
    pd.DataFrame({
        'Min': [init_storage_scaler.data_min_[0]],
        'Max': [init_storage_scaler.data_max_[0]]
    }).to_csv(output_dir / "ff_init_storage_scaling_factors.csv", index=False)


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

    # Compute cumulative flow minus demand (cfd) for each SOW in the ff ensemble
    ff_cfd = calculate_cumulative_flow_minus_demand(trace_df, ff_ensemble, n_years)

    # Save results
    save_ensemble_data(ff_ensemble, ff_cfd, config.output_dir)


if __name__ == '__main__':
    main(Config())
