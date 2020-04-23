import os

import numpy as np

import code.utils as cutil
import pandas as pd

states_url = "https://covidtracking.com/api/states/daily"
path_to_data = cutil.DATA

# rename the states
state_acronyms_to_names = {
    "all": "all",
    "AL": "Alabama",
    "AK": "Alaska",
    "AZ": "Arizona",
    "AR": "Arkansas",
    "AS": "American Samoa",
    "CA": "California",
    "CO": "Colorado",
    "CT": "Connecticut",
    "DE": "Delaware",
    "DC": "District of Columbia",
    "FL": "Florida",
    "GA": "Georgia",
    "GU": "Guam",
    "HI": "Hawaii",
    "ID": "Idaho",
    "IL": "Illinois",
    "IN": "Indiana",
    "IA": "Iowa",
    "KS": "Kansas",
    "KY": "Kentucky",
    "LA": "Louisiana",
    "ME": "Maine",
    "MD": "Maryland",
    "MA": "Massachusetts",
    "MI": "Michigan",
    "MN": "Minnesota",
    "MP": "Northern Marianas",
    "MS": "Mississippi",
    "MO": "Missouri",
    "MT": "Montana",
    "NE": "Nebraska",
    "NV": "Nevada",
    "NH": "New Hampshire",
    "NJ": "New Jersey",
    "NM": "New Mexico",
    "NY": "New York",
    "NC": "North Carolina",
    "ND": "North Dakota",
    "OH": "Ohio",
    "OK": "Oklahoma",
    "OR": "Oregon",
    "PA": "Pennsylvania",
    "PR": "Puerto Rico",
    "RI": "Rhode Island",
    "SC": "South Carolina",
    "SD": "South Dakota",
    "TN": "Tennessee",
    "TX": "Texas",
    "UT": "Utah",
    "VT": "Vermont",
    "VA": "Virginia",
    "VI": "Virgin Islands",
    "WA": "Washington",
    "WV": "West Virginia",
    "WI": "Wisconsin",
    "WY": "Wyoming",
}


def acc_to_statename(acc):
    return state_acronyms_to_names[acc]


# redo the date
def format_covid_tracking_date(date):
    date_str = str(date)
    year = date_str[:4]
    month = date_str[4:6]
    day = date_str[6:8]
    return "{y}-{m}-{d}".format(m=month, d=day, y=year)


def download_and_save_data_raw(save_locally=True):

    raw_state_data = pd.read_json(states_url)

    if save_locally:
        raw_fp = os.path.join(path_to_data, "raw/usa")
        raw_fn = "US_states_covidtrackingdotcom_raw.csv"
        raw_state_data.to_csv(os.path.join(raw_fp, raw_fn), index=False)

    return raw_state_data


def process_and_save_data_int(states_data_raw, save_locally=True):

    # 1. setup dataframe
    states_columns_to_keep = [
        "date",
        "adm0_name",
        "adm1_name",
        "cumulative_confirmed_cases",
        "cumulative_tests",
        "cumulative_deaths",
    ]

    # rename total to be more descriptive
    states_data = states_data_raw.rename(columns={"total": "total_inc_pending"})

    # make sure none of the neg cases are nan if previously reported cases aren't nan
    # do this by state!
    for state in np.unique(states_data["state"]):
        state_idxs = states_data["state"] == state
        states_data.loc[state_idxs, "negative"] = states_data.loc[
            state_idxs, "negative"
        ].fillna(method="bfill")

    # add total not including pending.
    states_data["total_pos_plus_neg"] = (
        states_data["positive"].values + states_data["negative"].values
    )

    #    states_data['total_pos_plus_neg_no_nan'] = states_data['positive'].fillna(0, inplace=False) + \
    #                                           states_data['negative'].fillna(0, inplace=False)

    states_data["total_pos_plus_neg_no_nan"] = (
        states_data["positive"] + states_data["negative"]
    )

    # redo the date
    states_data["date"] = states_data["date"].apply(format_covid_tracking_date)

    # iso3
    states_data["adm0_name"] = "USA"

    # rename state, deaths
    # count any positive and negatives (not pending and count NaN as zero)
    # toward  total testings
    states_data.rename(
        columns={
            "state": "adm1_name",
            "positive": "cumulative_confirmed_cases",
            "total_pos_plus_neg_no_nan": "cumulative_tests",
            "death": "cumulative_deaths",
        },
        inplace=True,
    )

    # rename state names.
    states_data.loc[:, "adm1_name"] = states_data["adm1_name"].apply(acc_to_statename)

    states_data = states_data[states_columns_to_keep]

    if save_locally:
        raw_fp = os.path.join(path_to_data, "interim/usa")
        raw_fn = "usa_states_covidtrackingdotcom_int.csv"
        states_data.to_csv(os.path.join(raw_fp, raw_fn), index=False)

    return states_data


def main():
    # 1. download latest datset from covidtracking.com
    raw_states_data = download_and_save_data_raw(save_locally=True)

    # 2. process according to formatting instructions and put in int
    int_data = process_and_save_data_int(raw_states_data, save_locally=True)

    # 3. for processing the testing regime changes, use the notebook in the
    # same folder as this script. It shows you where there are reported regime
    # changes so you can spot check the automated decisions.


if __name__ == "__main__":
    main()
