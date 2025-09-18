# Mapping of policy names to IDs
POLICIES = {
    2: "A",
    22: "B",
    11: "Compromise"
}

# List of objectives to evaluate
OBJECTIVES = [
    "LB_Shortage_Volume",
    "Mead_1000",
    "Powell_3525",
    "Powell_Release_LTEMP",
]

OBJECTIVES_SETTINGS = {

        "LB_Shortage_Volume": {
            'label': "Average Annual LB Delivery Reduction",
            'label_w_unit': "Average Annual LB Delivery Reduction (MAF)",
            'unit': 'MAF',
            'scale': 1e6,
            'n_digits': 1,
            'range': (0, 3.1)
        },

        "Mead_1000": {
            'label': "Mead 1000",
            'label_w_unit': 'Mead 1000 (%)',
            'unit': '%',
            'scale': 1,
            'n_digits': 1,
            'range': (0, 90)
        },

        "Powell_3525": {
            'label': "Powell 3525",
            'label_w_unit': 'Powell 3525 (%)',
            'unit': '%',
            'scale': 1,
            'n_digits': 1,
            'range': (0, 75)
        },

        "Powell_Release_LTEMP": {
            'label': "Powell LTEMP Release",
            'label_w_unit': 'Powell LTEMP Release (%)',
            'unit': '%',
            'scale': 1,
            'n_digits': 1,
            'range': (0, 37)
        }
    }
