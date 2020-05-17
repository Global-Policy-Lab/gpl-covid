import os

import numpy as np
import pandas as pd

# local imports
import src.utils as cutil

# flag whether to save this output in the /data/interim/usa folder
save_notebook_output = True

path_to_int_data = cutil.DATA_INTERIM / "usa"
fn_out = "usa_states_covidtrackingdotcom_int_with_testing_regimes.csv"
fp_out = os.path.join(path_to_int_data, fn_out)


def state_data_to_time_series(state_data):
    state_data_sorted = state_data.sort_values("date", inplace=False)

    timeseries_state_data = pd.Series(
        state_data_sorted["cumulative_tests"].values,
        pd.DatetimeIndex([pd.to_datetime(x) for x in state_data_sorted["date"].values]),
    )

    return state_data_sorted, timeseries_state_data


def calculate_testing_regimes(state_data, pct_chg_thresh=0.4, abs_chg_thresh=50):
    # calculates testing regimes as changing whenever the pct_chg of total tests
    # between previous. current dates is above pct_chg_thresh

    state_data_sorted, timeseries_state_data = state_data_to_time_series(state_data)

    pct_changes_in_testing = timeseries_state_data.pct_change(freq="D").values
    abs_changes_in_testing = timeseries_state_data.diff()

    testing_regimes = np.zeros(len(pct_changes_in_testing))
    regime = 0

    # transition to a new regime if the absolute *and* percent changes exceed the
    # thresholds
    for i, (pct_change, abs_change) in enumerate(
        zip(pct_changes_in_testing, abs_changes_in_testing)
    ):
        if pct_change > pct_chg_thresh and abs_change > abs_chg_thresh:
            regime += 1
        testing_regimes[i] = regime

    # return the pandas indices and the
    return testing_regimes, state_data_sorted.index


def main():
    # 1. download the data locally
    states_data = pd.read_csv(os.path.join(fp_out.replace("_with_testing_regimes", "")))

    # 2. add variable for testing regime
    states_data["testing_regime"] = 1

    state_names = np.unique(states_data["adm1_name"])
    print(len(state_names), "states represented")

    # These factors determine what is programatically considered as a testing regime
    # change candidate
    pct_change_thresh = 2.5
    abs_change_thresh = 150

    for state in state_names:
        # find the testing regimes for this state
        state_data = states_data[states_data["adm1_name"] == state]
        state_testing_regimes, state_data_idxs = calculate_testing_regimes(
            state_data,
            pct_chg_thresh=pct_change_thresh,
            abs_chg_thresh=abs_change_thresh,
        )

        states_data.loc[state_data_idxs, "testing_regime"] = state_testing_regimes

    # 3. + 4. (notebook only)
    # if you want to manually inspect and change results, use the notebook with the
    # same name as this script.

    # 5. Save data
    print("writing csv with testing regime changes to {0}".format(fp_out))
    states_data.to_csv(fp_out, index=False)


if __name__ == "__main__":
    main()
