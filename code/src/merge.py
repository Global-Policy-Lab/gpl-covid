import copy
import datetime
import pickle

import numpy as np
import pandas as pd

import src.pop as cpop

popweighted_suffix = "popwt"
exclude_from_popweights = [
    "testing_regime",
    "travel_ban_intl_in",
    "travel_ban_intl_out",
]

def count_policies_enacted(df, policy_list):
    """Count number of (non-pop-weighted) policy variables enacted on each row of `df`
    Args:
        df (pandas.DataFrame): DataFrame with policies as columns
        policy_list (pandas.DataFrame): DataFrame of policies, with all
            unique policy categories listed in the 'policy' column

    Returns:
        pandas.DataFrame: `df` with a new column counting number of non-pop-weighted
            policy variables in place, for each row
    """
    df["policies_enacted"] = 0
    for policy_name in policy_list:
        df["policies_enacted"] += df[policy_name]

    return df


def get_policy_level(row):
    # Assign policy_level to distinguish policies specified at different admin-unit levels
    adm_levels = sorted(
        [
            int(col[3])
            for col in row.keys()
            if col.startswith("adm") and col.endswith("name")
        ],
        reverse=True,
    )
    for level in adm_levels:
        if row[f"adm{level}_name"].lower() != "all":
            return level
    return 0


def get_intensities(policies, adm_level):
    if len(policies) == 0:
        return (0, 0)

    adm_levels = sorted(
        [
            int(col[3])
            for col in policies.columns
            if col.startswith("adm") and col.endswith("name")
        ]
    )
    adm_lower_levels = [l for l in adm_levels if l <= adm_level]
    adm_higher_levels = [l for l in adm_levels if l > adm_level]

    # Calculate max intensity of units at this level and below (lower res), and set as default against which
    # other levels will compare
    default_policy_intensity = np.nanmax(
        [
            policies.loc[
                policies["policy_level"].isin(adm_lower_levels), "policy_intensity"
            ].max(),
            0,
        ]
    )

    # Initialize final reported intensity to default intensity
    total_intensity = default_policy_intensity
    max_intensity = policies["policy_intensity"].max()

    level2_adm_intensities = pd.DataFrame()
    for level in adm_higher_levels:
        if level == 3 and len(adm_higher_levels) == 2:
            # Set policy_intensity to maximum between this policy_intensity and the highest policy_intensity
            # applied at the adm2 level for this adm3's adm2
            # check the lists to see if there is an adm2_policy which matches adm2's level and has a higher intensity
            has_adm2_intensity = (policies["policy_level"] == 3) & (
                policies["adm2_name"].isin(level2_adm_intensities.index)
            )

            policies["adm2_policy_intensity"] = 0
            policies.loc[has_adm2_intensity, "adm2_policy_intensity"] = policies.loc[
                has_adm2_intensity, "adm2_name"
            ].apply(lambda x: level2_adm_intensities.loc[x, "policy_intensity"])

            use_adm3_and_has_adm2 = (has_adm2_intensity) & (
                policies["policy_intensity"] > policies["adm2_policy_intensity"]
            )

            additional_policy_intensities = (
                policies.loc[use_adm3_and_has_adm2, "policy_intensity"]
                - policies.loc[use_adm3_and_has_adm2, "adm2_policy_intensity"]
            ) * (
                policies.loc[use_adm3_and_has_adm2, f"adm3_pop"]
                / policies.loc[use_adm3_and_has_adm2, f"adm{adm_level}_pop"]
            )

            total_intensity += additional_policy_intensities.sum()

            # Make sure not to count these ones again (but we don't continue the loop because there may be
            # other adm3 policies with higher policy_intensity than default intensity, without corresponding
            # adm2 intensities. Save maximum intensity found here in case it is the max in the whole dataset
            # because then we want the `policy` column to reflect this maximum
            policies.loc[use_adm3_and_has_adm2, "policy_intensity"] = 0

        elif level == 2 and len(adm_higher_levels) == 2:
            # Assign maximum adm2 policy intensities so that adm3 can compare
            level2_adm_intensities = (
                policies[policies["policy_level"] == 2]
                .groupby("adm2_name")[["policy_intensity"]]
                .max()
            )

        this_adm_higher_than_adm = (policies["policy_level"] == level) & (
            policies["policy_intensity"] > default_policy_intensity
        )
        additional_policy_intensities = (
            policies.loc[this_adm_higher_than_adm, "policy_intensity"]
            - default_policy_intensity
        ) * (
            policies.loc[this_adm_higher_than_adm, f"adm{level}_pop"]
            / policies.loc[this_adm_higher_than_adm, f"adm{adm_level}_pop"]
        )

        total_intensity += additional_policy_intensities.sum()

    assert total_intensity <= 1

    return total_intensity, max_intensity

def calculate_intensities_usa(policies_to_date, adm_level):

    weights = {
        "opt food/drink closure": .16,
        "opt all non-essentials": .16,
        "food/drink closure": .33,
        "recreation": .33,
        "all non-essentials": 1
    }
    
    replaces = {
        "food/drink closure": ["opt food/drink closure"],
        "all non-essentials": ["opt all non-essentials", "opt food/drink closure", "food/drink closure", "recreation"],
    }



    return (0, 0, 0, 0)

def calculate_intensities_adm_day_policy(policies_to_date, adm_level, method='ITA'):
    if method == 'USA':
        return calculate_intensities_usa(policies_to_date, adm_level)
    else:
        adm_name = f"adm{adm_level}_name"
        adm_intensity = f"adm{adm_level}_policy_intensity"
        adm_levels = sorted(
            [
                int(col[3])
                for col in policies_to_date.columns
                if col.startswith("adm") and col.endswith("name")
            ]
        )
        adm_lower_levels = [l for l in adm_levels if l <= adm_level]
        adm_higher_levels = [l for l in adm_levels if l > adm_level]

        def in_other(row, other):
            """Find any rows in `other` that cover the area covered by the policy `row`, returning the maximum
            intensity in `other` so that the full optional intensity (but no more) will be accounted for in the
            overlap DataFrame
            """
            other_contains_row = np.ones_like(other["adm0_name"], dtype=bool)
            for level in adm_levels:
                other_contains_row = (other_contains_row) & (
                    other[f"adm{level}_name"].isin([row[f"adm{level}_name"], "all", "All"])
                )

            if other_contains_row.sum() == 0:
                return 0

            return other.loc[other_contains_row, "policy_intensity"].max()

        is_opt = policies_to_date["optional"] == 1
        policies_opt = policies_to_date[is_opt].copy()
        policies_mand = policies_to_date[~is_opt].copy()

        if len(policies_opt) > 0 and len(policies_mand) > 0:
            # Apply logic of calculating mandatory policies fully,
            # calculating optional policies by taking the full value
            # and subtracting the value of those policies that have
            # overlap with mandatory policies

            policies_opt["intensity_in_mand"] = policies_opt.apply(
                lambda row: in_other(row, policies_mand), axis=1
            )
            policies_opt = policies_opt[policies_opt["intensity_in_mand"] == 0]
            policies_mand["intensity_in_opt"] = policies_mand.apply(
                lambda row: in_other(row, policies_opt), axis=1
            )

            # Set `policies_overlap` to the mandatory policies that are found in `policies_opt`, with `policy_intensity`
            # replaced by the intensity found in the corresponding row of `policies_opt`
            policies_overlap = policies_mand[policies_mand["intensity_in_opt"] > 0].copy()
            policies_overlap = policies_overlap.drop(columns=["policy_intensity"])
            policies_overlap = policies_overlap.rename(
                columns={"intensity_in_opt": "policy_intensity"}
            )

            total_mandatory_intensity, mandatory_intensity_indicator = get_intensities(
                policies_mand, adm_level
            )
            subtotal_optional_intensity, optional_intensity_indicator = get_intensities(
                policies_opt, adm_level
            )
            total_overlap_intensity, overlap_intensity_indicator = get_intensities(
                policies_overlap, adm_level
            )

            total_optional_intensity = subtotal_optional_intensity - total_overlap_intensity
            assert total_optional_intensity >= 0
        else:
            # If there are not both mandatory and optional policies, just get the intensities of those DataFrames
            # individually, without worrying about overlap
            if len(policies_opt) == 0:
                total_optional_intensity, optional_intensity_indicator = (0, 0)
            else:
                total_optional_intensity, optional_intensity_indicator = get_intensities(
                    policies_opt, adm_level
                )

            if len(policies_mand) == 0:
                total_mandatory_intensity, mandatory_intensity_indicator = (0, 0)
            else:
                total_mandatory_intensity, mandatory_intensity_indicator = get_intensities(
                    policies_mand, adm_level
                )

        # For the policy indicator, ensure that not both are counted
        if optional_intensity_indicator > 0 and mandatory_intensity_indicator > 0:
            optional_intensity_indicator = 0

        result = (
            total_mandatory_intensity,
            mandatory_intensity_indicator,
            total_optional_intensity,
            optional_intensity_indicator,
        )
        return result


def get_policy_vals(policies, policy, date, adm, adm1, adm_level, policy_pickle_dict):
    """Assign all policy variables from `policies` to `cases_df`
    Args:
        policies (pandas.DataFrame): table of policies, listed by date and regions affected
        policy (str): name of policy category to be applied
        date (datetime.datetime): date on which policies are applied
        adm (str): name of admin-unit on which policies are applied
        adm1 (str) name of adm1 unit within which policies are applied (necessary if `adm` is an adm2 unit)
        adm_level (int): level of admin-unit on which policies are applied
        policy_pickle_dict (dict of dicts): Dictionary with keys `adm` and a pickled version of
            `policies_to_date` (computed within this function) to get result if it has already
            been computed. Though messy, this saves a lot of time

    Returns:
        tuple of (float, float): Tuple representing (intensity, pop-weighted-intensity) of `adm`
            on `date` for `policy`
    """
    adm_name = f"adm{adm_level}_name"

    adm_levels = sorted(
        [
            int(col[3])
            for col in policies.columns
            if col.startswith("adm") and col.endswith("name")
        ]
    )

    policies_to_date = policies[
        (policies["policy"] == policy)
        & (policies["date_start"] <= date)
        & (policies["date_end"] >= date)
        & ((policies[adm_name] == adm) | (policies[adm_name].str.lower() == "all"))
        & (
            (policies["adm1_name"] == adm1)
            | (policies["adm1_name"].str.lower() == "all")
        )
    ].copy()

    if len(policies_to_date) == 0:
        return (0, 0, 0, 0)

    # Check if `policies_to_date` result has already been computed for `adm`, use that result if so
    psave = pickle.dumps(policies_to_date)
    if adm not in policy_pickle_dict:
        policy_pickle_dict[adm] = dict()
    if psave in policy_pickle_dict[adm]:
        return policy_pickle_dict[adm][psave]
    else:
        result = calculate_intensities_adm_day_policy(policies_to_date, adm_level)
        policy_pickle_dict[adm][psave] = result

    return result


def initialize_panel(cases_df, cases_level, policy_list, policy_popwts):
    date_min = cases_df["date"].min()
    date_max = cases_df["date"].max()

    # Initalize panel with same structure as `cases_df`
    policy_panel = (
        pd.DataFrame(
            index=pd.MultiIndex.from_product(
                [
                    pd.date_range(date_min, date_max),
                    sorted(cases_df[f"adm{cases_level}_name"].unique()),
                ]
            ),
            columns=policy_list + policy_popwts,
        )
        .reset_index()
        .rename(columns={"level_0": "date", "level_1": f"adm{cases_level}_name"})
        .fillna(0)
    )

    if cases_level == 2:
        adm2_to_adm1 = (
            cases_df[["adm1_name", "adm2_name"]]
            .drop_duplicates()
            .set_index("adm2_name")["adm1_name"]
        )
        adm1s = policy_panel["adm2_name"].apply(lambda x: adm2_to_adm1.loc[x])
        policy_panel.insert(1, "adm1_name", adm1s)

    return policy_panel


def assign_policies_to_panel(
    cases_df, policies, cases_level, aggregate_vars=[], get_latlons=True, errors="raise"
):
    """Assign all policy variables from `policies` to `cases_df`
    Args:
        cases_df (pandas.DataFrame): table to assign policy variables to,
            typically with case data already assigned
        policies (pandas.DataFrame): table of policies, listed by date and regions affected
        cases_level (int): Adminisrative unit level used for analysis of policy effects,
            typically the lowest level which pop-weights have been applied to
        aggregate_vars (list of str): list of policy variables where optional version
            should be treated independently of mandatory version

    Returns:
        pandas.DataFrame: a version of `cases_df` with all policies from `policies` assigned as new columns
    """

    # Make sure policies input doesn't change unexpectedly
    policies = policies.copy()

    # Convert 'optional' to indicator variable
    if not np.issubdtype(policies["optional"].dtype, np.number):
        policies["optional"] = policies["optional"].replace({"Y": 1, "N": 0})
        # fill any nans with 0
        policies["optional"] = policies["optional"].fillna(0).astype(int)

    policies["optional"] = policies["optional"].fillna(0)
    if errors == "raise":
        assert len(policies["optional"].unique()) <= 2
    elif errors == "warn":
        if len(policies["optional"].unique()) > 2:
            print(
                "there were more than two values for optional: {0}".format(
                    policies["optional"].unique()
                )
            )

    policies["date_end"] = policies["date_end"].fillna(pd.to_datetime("2099-12-31"))

    # Assign population columns to `policies` and `cases_df`
    policies, cases_df = cpop.assign_all_populations(
        policies, cases_df, cases_level, get_latlons=get_latlons, errors=errors
    )

    # Assign policy_level to distinguish policies specified at different admin-unit levels
    policies["policy_level"] = policies.apply(get_policy_level, axis=1)

    # Treat policies in `aggregate_vars` as independent policies (just like mandatory policies)
    # Set optional to 0 to avoid applying normal optional logic in `get_policy_vals()`
    for policy in aggregate_vars:
        policies.loc[policies["optional"] == 1, "policy"] = (
            policies.loc[policies["optional"] == 1, "policy"] + "_opt"
        )
        policies.loc[policies["optional"] == 1, "optional"] = 0

    policy_list = list(policies["policy"].unique())
    policy_popwts = [
        p + "_popwt" for p in policy_list if p not in exclude_from_popweights
    ]

    policy_panel = initialize_panel(cases_df, cases_level, policy_list, policy_popwts)

    # Assign each policy one-by-one to the panel
    for policy in policy_list:
        policy_pickle_dict = dict()

        # Get Series of 4-tuples for mandatory pop-weighted, mandatory indicator,
        # optional pop-weighted, optional indicator
        tmp = policy_panel.apply(
            lambda row: get_policy_vals(
                policies,
                policy,
                row["date"],
                row[f"adm{cases_level}_name"],
                row[f"adm1_name"],
                cases_level,
                policy_pickle_dict,
            ),
            axis=1,
        )

        # Assign regular policy indicator
        policy_panel[policy] = tmp.apply(lambda x: x[1])

        # Assign opt-column if there's anything there
        opt_col = tmp.apply(lambda x: x[3])
        use_opt_col = opt_col.sum() > 0
        if use_opt_col:
            policy_panel[policy + "_opt"] = tmp.apply(lambda x: x[3])

        # Assign pop-weighted column if it's not excluded from pop-weighting, and opt-pop-weighted if
        # Optional and pop-weighted are both used
        if policy not in exclude_from_popweights:
            policy_panel[policy + "_popwt"] = tmp.apply(lambda x: x[0])
            if use_opt_col:
                policy_panel[policy + "_opt_popwt"] = tmp.apply(lambda x: x[2])

    policy_panel = count_policies_enacted(policy_panel, policy_list)

    if cases_level == 2:
        policy_panel = policy_panel.drop(columns=["adm1_name"])

    # Merge panel with `cases_df`
    merged = pd.merge(
        cases_df,
        policy_panel,
        left_on=["date", f"adm{cases_level}_name"],
        right_on=["date", f"adm{cases_level}_name"],
    )

    return merged
