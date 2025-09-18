from src.utils import ids


BOXPLOT_Y_TICKS = {
    ids.MEDIAN_FLOW: [7, 14.5, 22],
    ids.DEMAND: [4, 5, 6],
    ids.INIT_STORAGE: [2, 20, 38]
}

BOXPLOT_Y_LABELS = {
    ids.MEDIAN_FLOW: "Median Annual\nFlow (MAF)",
    ids.DEMAND: "Annual UB Demand\n(MAF)",
    ids.INIT_STORAGE: "Initial Combined\nStorage (MAF)"
}

PLOT_TITLES = {
    ids.MEDIAN_FLOW: 'Median Annual Lees Ferry Flow (MAF)',
    ids.DEMAND: 'Annual Upper Basin Demand (MAF)',
    ids.INIT_STORAGE: 'Initial Combined Storage (Powell + Mead, MAF)',
}


COLOR_SCHEMES = {
    ids.MEDIAN_FLOW: 'red_blue',
    ids.DEMAND: 'red_blue',
    ids.INIT_STORAGE: 'red_blue'
}

COLORBAR_RANGES = {
    ids.MEDIAN_FLOW: (10, 17),
    ids.DEMAND: (4.8, 5.5),
    ids.INIT_STORAGE: (12, 29)
}


INVERSE_COLORBAR = {
    ids.MEDIAN_FLOW: True,
    ids.DEMAND: False,
    ids.INIT_STORAGE: False
}
