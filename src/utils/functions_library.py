from typing import Dict, List, Tuple, Optional

import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import matplotlib.patches as patches
from matplotlib.gridspec import GridSpec
import numpy as np
import pandas as pd

from src.utils import ids


def calculate_trace_metrics(trace_timeseries: pd.DataFrame) -> pd.DataFrame:
    """
    Calculates various hydrological metrics for each of the provided traces.

    Parameters
    ----------
    trace_timeseries : pd.DataFrame
        Tidy DataFrame containing annual flow data. Each row represents a single year's data for a specific trace. At a
        minimum, the DataFrame should include the following columns:
          - 'Trace': Unique identifier for each trace
          - 'LF_Annual': Annual flow value for each year of the trace

    Returns
    -------
    pd.DataFrame
        DataFrame containing the calculated metrics for each trace, including:
          - Median: Median annual flow for each trace
          - Max: Maximum annual flow for each trace
          - Min: Minimum annual flow for each trace
          - SD: Standard deviation of annual flows for each trace
          - IQR: Inter-quartile range of annual flows for each trace
    """

    n_traces = max(trace_timeseries[ids.TRACE])

    metrics = {
        "Median": [], "Max": [], "Min": [], "SD": [], "IQR": []
    }

    for trace_id in range(1, n_traces + 1):
        trace_data = trace_timeseries[trace_timeseries[ids.TRACE] == trace_id][ids.LF_ANNUAL].to_numpy()

        metrics["Median"].append(np.median(trace_data))
        metrics["Max"].append(np.max(trace_data))
        metrics["Min"].append(np.min(trace_data))
        metrics["SD"].append(np.std(trace_data))
        metrics["IQR"].append(np.subtract(*np.percentile(trace_data, [75, 25])))

    return pd.DataFrame(metrics)


def create_cumulative_timeseries_som_view(
        sow_info: pd.DataFrame,
        sow_cumulative_timeseries: pd.DataFrame,
        start_year: int,
        end_year: int,
        x_ticks: list[int],
        y_ticks: list[int],
        color: str,
        rows: int = 5,
        cols: int = 17
) -> plt.Figure:
    """
    Create a SOM visualization where each neuron is shown as a cumulative timeseries plot.

    Each subplot corresponds to a neuron in a hexagonal SOM grid. For a given neuron,
    all States of the World (SOWs) assigned to that neuron have their cumulative
    flow–minus–demand (CFD) timeseries plotted in the specified highlight color,
    while all other SOWs are shown in gray for context.

    Parameters
    ----------
    sow_info : pd.DataFrame
        DataFrame of SOW metadata. Must include:
            - 'Neuron': Neuron assignment for each SOW (integer, starting at 1).
    sow_cumulative_timeseries : pd.DataFrame
        Cumulative CFD timeseries for each SOW.
        Shape: (n_years, n_sows), with rows = simulation years and columns = SOWs.
    start_year : int
        First simulation year (inclusive).
    end_year : int
        Last simulation year (exclusive).
    x_ticks : list of int
        Values to display as x-axis ticks (e.g., selected simulation years).
    y_ticks : list of int
        Values to display as y-axis ticks (e.g., CFD values).
    color : str
        Matplotlib color string for highlighting SOWs within a neuron.
    rows : int, optional
        Number of rows in the SOM grid. Default is 5.
    cols : int, optional
        Number of columns in the SOM grid. Default is 17.

    Returns
    -------
    matplotlib.figure.Figure
        Figure containing the cumulative timeseries SOM view.
    """
    n_neurons = rows * cols
    sim_years = np.arange(start_year, end_year)

    fig = plt.figure(figsize=(19, 9.5))
    gs = GridSpec(
        nrows=rows,
        ncols=2 * cols + 1,  # double number of columns and add 1 to allow for shifting of rows
        figure=fig
    )

    ## Plotting loop
    neurons = np.unique(sow_info[ids.NEURON])

    for neuron in neurons:
        x, y = get_subplot_coordinates(
            neuron=neuron,
            rows=rows,
            cols=cols
        )
        ax = fig.add_subplot(gs[x, y:y + 2])

        ## Determine which SOWs are in neuron and which are not
        indices = sow_info.index[sow_info["Neuron"] == neuron]
        non_indices = sow_info.index[sow_info["Neuron"] != neuron]

        plot_cumulative_timeseries(
            sim_years=sim_years,
            cumulative_timeseries=sow_cumulative_timeseries,
            indices=indices,
            non_indices=non_indices,
            ax=ax,
            color=color
        )
        ax.set_title(
            label=f"Neuron\n{int(neuron)}",
            y=1.0,
            pad=-26,
            fontsize=12,
            fontweight="bold",
            loc='center'
        )

        ## For plots on the bottom, add x-axis tick labels
        if x == (rows - 1):
            ax.tick_params(
                labelbottom=True,
                bottom=True,
                length=0
            )
            ax.set_xticks(
                ticks=x_ticks
            )
            ax.set_xticklabels(
                labels=x_ticks,
                fontsize=12,
                rotation=90
            )

        ## For plots on the left, add y-axis tick labels
        if y == 0 or y == 1:
            ax.tick_params(
                left=True,
                labelleft=True,
                length=0
            )
            ax.set_yticks(
                ticks=y_ticks
            )
            ax.set_yticklabels(
                labels=y_ticks,
                fontsize=12
            )

    fig.subplots_adjust(
        wspace=0.6,
        hspace=0.1,
        left=0.05,
        right=0.95,
        top=0.95,
        bottom=0.07
    )

    return fig


def create_boxplot_som_view(
    sow_info: pd.DataFrame,
    feature: str,
    y_ticks: list[float],
    color: str,
    rows: int = 5,
    cols: int = 17,
) -> plt.Figure:
    """
    Create a SOM visualization where each neuron is shown as a boxplot of a given feature.

    Each subplot corresponds to a neuron in a hexagonal SOM grid. For the SOWs assigned to a
    given neuron, the distribution of the selected feature is summarized as a boxplot. The
    box and whiskers are styled using the specified color. Neuron IDs are overlaid as labels.

    Parameters
    ----------
    sow_info : pd.DataFrame
        DataFrame of SOW metadata. Must include:
            - 'Neuron': Neuron assignment for each SOW (integer, starting at 1).
            - <feature>: Column with the feature to be plotted.
    feature : str
        Name of the column in `sow_info` to visualize with boxplots.
    y_ticks : list of float
        Tick values for the y-axis (shared across neurons).
    color : str
        Matplotlib color string for styling boxplots.
    rows : int, optional
        Number of rows in the SOM grid. Default is 5.
    cols : int, optional
        Number of columns in the SOM grid. Default is 17.

    Returns
    -------
    matplotlib.figure.Figure
        Figure containing the boxplot SOM view.
    """

    fig = plt.figure(figsize=(19, 9.5))
    gs = GridSpec(
        nrows=rows,
        ncols=2 * cols + 1,  # double number of columns and add 1 to allow for shifting of rows
        figure=fig
    )

    ## Plotting loop
    neurons = np.unique(sow_info[ids.NEURON])

    for neuron in neurons:
        x, y = get_subplot_coordinates(
            neuron=neuron,
            rows=rows,
            cols=cols
        )
        ax = fig.add_subplot(gs[x, y:y + 2])

        ## Determine which SOWs are in neuron and which are not
        indices = sow_info.index[sow_info["Neuron"] == neuron]

        ax.set_title("")  # Clear default title

        ax.text(
            x=0.02,  # adjust this value to move more or less leftward
            y=.87,  # slightly above the plot
            s=f"{int(neuron)}",
            fontsize=12,
            fontweight="bold",
            transform=ax.transAxes,  # position is relative to axes
            ha='left', va='bottom',
            zorder=5
        )

        ax.boxplot(
            sow_info.loc[indices, feature],
            boxprops=dict(color=color),
            whiskerprops=dict(color=color),
            capprops=dict(color=color),
            widths=1
        )

        ax.set_xlim(0, 2)
        ax.set_ylim(y_ticks[0], y_ticks[-1])
        ax.tick_params(left=False, right=False, labelleft=False, labelbottom=False, bottom=False)
        ax.set_xticks([])

        if y == 0 or y == 1:
            ax.tick_params(
                left=True,
                labelleft=True,
                length=0
            )
            ax.set_yticks(
                ticks=y_ticks
            )
            ax.set_yticklabels(
                labels=y_ticks,
                fontsize=12
            )

    fig.subplots_adjust(
        wspace=0.6,
        hspace=0.1,
        left=0.05,
        right=0.95,
        top=0.95,
        bottom=0.07
    )

    return fig


def get_subplot_coordinates(
        neuron: int,
        rows: int,
        cols: int
) -> [int, int]:
    """
    Calculate the GridSpec row and column positions for a subplot based on the neuron index in a Self-Organizing Map
    (SOM).

    Assumptions:
        - The SOM configuration is hexagonal, meaning that alternating rows are shifted. Rows shifted to the right are
          those starting with the bottom row and every other row going up.
        - The GridSpec configuration for plotting the subplot has twice the number of SOM columns plus one (e.g., if the
          SOM has 17 columns, the GridSpec configuration has 35 columns: 12 * 2 + 1).
        - Neurons are numbered starting from 1 in the bottom-left corner, increasing along the bottom row. Numbering
          continues from left to right in the next row up, and so on, with the last neuron being in the top-right corner

    Parameters
    ----------
    neuron : int
        The index of the neuron (starting at 1) for which to calculate the subplot coordinates.
    rows : int
        The number of rows in the SOM.
    cols : int
        The number of columns in the SOM.

    Returns
    -------
    Tuple[int, int]
        A tuple containing the row and column GridSpec coordinates for the neuron subplot.
    """
    n_neurons = rows * cols
    x = int(np.floor((n_neurons - neuron) / cols))
    y = int(((neuron - 1) % cols)) * 2

    if rows % 2 == 0:
        if x % 2 != 0:
            y += 1
    else:
        if x % 2 == 0:
            y += 1

    return int(x), int(y)


def plot_cumulative_timeseries(
        sim_years: np.ndarray,
        cumulative_timeseries: pd.DataFrame,
        indices: List[int],
        non_indices: List[int],
        ax: plt.Axes,
        color: str
) -> None:
    """
    Plots cumulative timeseries onto a single matplotlib Axes object. Timeseries specified by 'non_indices' (i.e., those
    not in the neuron being plotted) are colored gray, and timeseries specified by 'indices' (i.e., those in the neuron
    being plotted) are colored in the specified color.

    Parameters
    ----------
    sim_years : np.ndarray
        A 1-dimensional numpy array containing the simulation years.
    cumulative_timeseries : pd.DataFrame)
        A DataFrame containing the cumulative timeseries data. Each column represents a timeseries.
    indices : List[int]
        A list of indices representing the timeseries to be highlighted in the specified color.
    non_indices : List[int]
        A list of indices representing the timeseries to be colored gray.
    ax : plt.Axes
        The matplotlib Axes object on which the timeseries will be plotted.
    color : str
        The color used to highlight the timeseries specified by 'indices'.

    Returns
    -------
    None
        This function does not return anything. It directly modifies the provided Axes object.
    """

    # Plot non_indices timeseries
    for idx in non_indices:
        ax.plot(
            sim_years,
            cumulative_timeseries.iloc[idx, :],
            color='gray',
            linewidth=0.5
        )

    # Plot indices timeseries
    for idx in indices:
        ax.plot(
            sim_years,
            cumulative_timeseries.iloc[idx, :],
            color=color,
            linewidth=0.5
        )

    # Set axis limits and tick params
    ax.set_xlim(
        left=sim_years[0],
        right=sim_years[-1]
    )
    ax.set_ylim(
        bottom=0,
        top=510
    )
    ax.tick_params(
        left=False,
        right=False,
        labelleft=False,
        labelbottom=False,
        bottom=False
    )


def create_condensed_som_figure(
        title: str,
        colorbar_label: str,
        neuron_values: List[float],
        neuron_coordinates: pd.DataFrame,
        color_scheme: str,
        n_digits: int,
        inverse_colorbar: bool,
        value_range: Optional[Tuple[float, float]] = None,
        rows: int = 5,
        cols: int = 17
) -> plt.Figure:
    """
    Creates a visual representation of a Self-Organizing Map (SOM) where each neuron is depicted as a hexagon with a
    fill color corresponding to its specified value and the specified color scheme.

    Parameters
    ----------
    title : str
        The title of the figure.
    colorbar_label : str
        The label for the colorbar.
    neuron_values : List[float]
        A list of values corresponding to each neuron. The length must be the same as the number of entries in
        neuron_coordinates.
    neuron_coordinates : pd.DataFrame
        A DataFrame containing the x and y coordinates of each neuron. Required columns:
           - 'x': The x-coordinate of each neuron.
           - 'y': The y-coordinate of each neuron.
    color_scheme : str
        The name of the color scheme to be used for the hexagons.
    n_digits : int
        The number of digits to round the neuron values to for display.
    inverse_colorbar : bool
        Whether to invert the colorbar to have the largest value on the left.
    value_range : Tuple[float, float], optional
        Colorbar range for plotting. Defaults to min/max of provided data.
    rows : int, optional
        The number of rows in the subplot grid. Default is 5.
    cols : int, optional
        The number of columns in the subplot grid. Default is 17.

    Returns
    -------
    plt.Figure
        A Matplotlib figure object containing the condensed (hexagonal) SOM.
    """

    if value_range is None:
        value_range = (
            np.floor(np.min(neuron_values)),
            np.ceil(np.max(neuron_values))
        )

    # Create figure object
    fig, ax = plt.subplots(figsize=(1.5 * cols, 2 * rows + 1.5))
    ax.set_aspect('equal')

    # Set figure parameters
    grid_width, grid_height = cols, rows
    hex_radius = 0.52

    # Set color scheme
    colors, text_color = get_color_scheme(color_scheme)
    cmap = mcolors.LinearSegmentedColormap.from_list(name='cmap', colors=colors)

    for idx, row in neuron_coordinates.iterrows():

        value = neuron_values[idx]
        neuron_face_color = map_value_to_color(
            value=value,
            value_range=value_range,
            cmap=cmap
        )

        x, y = row['x'], row['y']

        hexagon = patches.RegularPolygon(
            xy=(x, y),
            numVertices=6,
            radius=hex_radius,
            orientation=np.radians(0),
            facecolor=neuron_face_color,
            edgecolor='black'
        )
        ax.add_patch(hexagon)

        ax.text(
            x=x,
            y=y,
            s=round(value, n_digits) if n_digits > 0 else round(value),
            ha='center',
            va='center',
            fontsize=27,
            color=text_color
        )

    # Colorbar
    norm = plt.Normalize(
        vmax=value_range[1],
        vmin=value_range[0]
    )
    sm = plt.cm.ScalarMappable(
        cmap=cmap,
        norm=norm
    )
    sm.set_array([])

    ## Add colorbar to fig
    cbar_ax = fig.add_axes([0.11, 0.2, 0.775, 0.03])
    cbar = fig.colorbar(
        mappable=sm,
        cax=cbar_ax,
        orientation='horizontal'
    )
    cbar.set_label(
        label='Color/Text: ' + colorbar_label,
        fontsize=30,
        labelpad=10
    )
    cbar.ax.tick_params(labelsize=28)

    ## Inverse colorbar to have the largest value on the left
    if inverse_colorbar:
        cbar.ax.invert_xaxis()

    # Set limits and turn off axes
    ax.set_xlim([0, 2 * hex_radius * grid_width + 2])
    ax.set_ylim([0, 2 * hex_radius * grid_height + 1])
    ax.axis('off')

    fig.subplots_adjust(
        left=0.048,
        right=0.997,
        top=0.965,
        bottom=0.151
    )

    title_y = 0.88 if '\n' in title else 0.835
    fig.suptitle(title, fontsize=35, y=title_y)

    return fig


def get_color_scheme(scheme_name: str) -> Tuple[List[Tuple[float, str]], str]:
    """
    Retrieves a predefined color scheme and an appropriate text color.

    Parameters
    ----------
    scheme_name : str
        The name of the color scheme to retrieve. Available schemes are:
            - 'good_bad': Green → Yellow → Red
            - 'good_bad_reverse': Red → Yellow → Green
            - 'red_blue': OrangeRed → Blue
            - 'blue_red': Blue → OrangeRed

    Returns
    -------
    Tuple[List[Tuple[float, str]], str]
        - A list of (position, hex color) tuples representing the color scheme.
        - A string for the recommended text color ("black" or "white").
    """

    schemes: Dict[str, List[Tuple[float, str]]] = {
        "good_bad": [
            (0, "#008000"), (0.5, "#FFFF00"), (1, "#FF0000")
        ],
        "good_bad_reverse": [
            (0, "#FF0000"), (0.5, "#FFFF00"), (1, "#008000")
        ],
        "red_blue": [
            (0, "#FF4500"), (1, "#0000FF")
        ],
        "blue_red": [
            (0, "#0000FF"), (1, "#FF4500")
        ],
    }

    text_colors: Dict[str, str] = {
        "good_bad": "black",
        "good_bad_reverse": "black",
        "red_blue": "white",
        "blue_red": "white",
    }

    if scheme_name not in schemes:
        raise ValueError(
            "Please provide an existing color scheme "
            "('good_bad', 'good_bad_reverse', 'red_blue', 'blue_red')"
        )

    return schemes[scheme_name], text_colors[scheme_name]


def map_value_to_color(
        value: float,
        value_range: Tuple[float, float],
        cmap: mcolors.LinearSegmentedColormap
) -> Tuple[float, float, float, float]:
    """
    Maps a given value to a color in a specified colormap based on the value's position within a defined range.

    Parameters
    ----------
    value : float
        The value to be mapped to a color.
    value_range : Tuple[float, float]
        A tuple containing the minimum and maximum values of the range.
    cmap : mcolors.LinearSegmentedColormap
        A Matplotlib colormap used to map the normalized value to a color.

    Returns
    -------
    Tuple[float, float, float, float]
        A tuple representing the RGBA color mapped from the input value.
    """

    # Normalize the value to the range [0, 1]
    normalized_value = (value - value_range[0]) / (value_range[1] - value_range[0])

    # Map the normalized value to a color in the gradient
    return cmap(normalized_value)


def get_policy_reevaluation_data(
        reevaluation_data: pd.DataFrame,
        sow_info: pd.DataFrame,
        policy: str
) -> pd.DataFrame:
    """
    Filters the reevaluation data for a given experiment and policy, merges it with SOW neuron information, and pivots
    the data to a wide format where each objective is a column.

    Parameters
    ----------
    reevaluation_data : pd.DataFrame
        DataFrame containing the reevaluation data with columns:
          - 'Experiment': The name of the experiment.
          - 'Policy': The policy ID.
          - 'SOW': The state of the world identifier.
          - 'Objective': The objective being measured.
          - 'Value': The value of the objective.
    sow_info : pd.DataFrame
        DataFrame containing SOW information including neuron assignments. Necessary columns:
          - 'SOW': The numerical state of the world identifier.
          - 'Neuron': The neuron number in the SOM to which the SOW is assigned.
    policy : int
        The policy ID to filter the data by.

    Returns
    -------
    pd.DataFrame
        A DataFrame in wide format for the specified experiment/policy where rows represent SOWs and each objective is a
         separate column.
    """

    policy_data = reevaluation_data[(reevaluation_data[ids.POLICY] == policy)]
    policy_data = pd.merge(
        left=policy_data,
        right=sow_info[[ids.SOW, ids.NEURON]],
        on=ids.SOW,
        how='left'
    )
    policy_data_wide = policy_data.pivot(
        index=[ids.POLICY, ids.SOW, ids.NEURON],
        columns=ids.OBJECTIVE,
        values='Value'
    ).reset_index()

    return policy_data_wide
