import numpy as np
import pandas as pd
import copy
import datetime
import pickle
import codes.pop as cpop

popweighted_suffix = "popwt"
exclude_from_popweights = [
    "testing_regime",
    "travel_ban_intl_in",
    "travel_ban_intl_out",
]

# def assign_policy_variable_from_mask(adm_cases, policy_on_mask, policy, intensity, weight, policy_level):
#     """Deprecated"""
#     """Assigns a policy as a (weighted or non-weighted) indicator to a DataFrame
#     Args:
#         adm_cases (pandas.DataFrame): DataFrame to assign `policy` column
#         policy_on_mask (array-like) (same length as `adm_cases`): Mask where True values
#             correspond to rows of `adm_cases` that the policy applies to
#         policy (str): Name of policy variable to assign
#         intensity (float): Intensity of policy on a (0, 1] scale.
#             This is used for non-pop-weighted policy variables
#         weight (float): Policy weighted by population and intensity, on a (0, 1] scale
#             This is used for pop-weighted policy variables

#     Returns:
#         pandas.DataFrame: `adm_cases` with a new column named after `policy`, and, if
#             applicable, a new column named after `policy` with `popweighted_suffix` appended
#     """
#     adm_cases.loc[policy_on_mask, f'{policy}_{str(policy_level)}'] = intensity

#     if policy not in exclude_from_popweights:
#         adm_cases.loc[policy_on_mask, f'{policy}_{popweighted_suffix}_{str(policy_level)}'] = weight

#     return adm_cases

# def get_mask(adm_cases, adm_names, adm_levels, date_start, date_end):
#     """Deprecated"""
#     """Assigns a policy as a (weighted or non-weighted) indicator to a DataFrame
#     Args:
#         adm_cases (pandas.DataFrame): DataFrame to assign policy column
#         adm_names (list of str): List of administrative unit names specified in a row of `adm_cases`
#             e.g. ["California", "Alameda County", "Berkeley"]
#         adm_levels (list of int): List of administrative unit levels specified in `adm_cases`
#             e.g. [1, 2, 3]
#         date_start (numpy.datetime64): Date when policy is enacted
#         date_end (numpy.datetime64): Date when policy is revoked

#     Returns:
#         pandas.Series (same length as `adm_cases`): Mask where True values
#             correspond to rows of `adm_cases` that the policy applies to
#     """
#     # All policies on or after policy was enacted, where each of these conditions applies:
#         # This row's date falls within the period of the policy
#         # This row's specified adm's match the policy's, either as specified or as all, for each adm
#     date_in_bounds = (adm_cases['date'] >= date_start) & (adm_cases['date'] <= date_end)

#     adms_covered = np.ones_like(adm_cases['date'], dtype=bool)
#     for i in range(len(adm_names)):
#         adms_covered = (
#             (adms_covered) &
#             (
#                 (adm_names[i] == adm_cases[f'adm{adm_levels[i]}_name']) | (adm_names[i] == 'All')
#             )
#         )

#     policy_on_mask = (date_in_bounds) & (adms_covered)
#     return policy_on_mask

# def initialize_policy_variables(adm_cases, adm_policies, policy_level):
#     """Deprecated"""
#     """Assigns a policy as 0 (not enacted) to all rows of a DataFrame
#     Args:
#         adm_cases (pandas.DataFrame): DataFrame to assign policy columns
#         adm_policies (pandas.DataFrame): DataFrame of policies, with all
#             unique policy categories listed in the 'policy' column

#     Returns:
#         pandas.DataFrame: `adm_cases` with new columns for all `adm_policies`
#             (and their pop-weighted forms, where applicable)
#     """

#     # Initialize policy columns in health data
#     for policy_name in adm_policies['policy'].unique():
#         adm_cases[f'{policy_name}_{str(policy_level)}'] = 0

#         # Include pop-weighted column for policies applied within the country
#         if policy_name not in exclude_from_popweights:
#             adm_cases[f'{policy_name}_{popweighted_suffix}_{str(policy_level)}'] = 0

#     return adm_cases

# def get_relevant_policy_cols(adm_levels, adm_cases_level):
#     """Deprecated"""
#     """Get list of columns in a policies DataFrame that are needed to create indicator variables
#     Args:
#         adm_levels (list of int): List of administrative unit levels specified in DataFrame that
#             policy variables will be assigned to
#             e.g. [1, 2, 3]
#         adm_cases_level (int): Administrative unit level used for analysis of policy effects
#             i.e. (usually) the lowest level (highest `adm_level`) which pop-weights have been applied to

#     Returns:
#         list of str: list of columns in a policies DataFrame that are needed to create indicator variables
#     """
#     adm_names = [f'adm{adm_level}_name' for adm_level in adm_levels]
#     non_adm_name_cols = ['date_start', 'date_end', 'policy', 'policy_intensity', f'adm{adm_cases_level}_pop_intensity_weight']
#     return adm_names + non_adm_name_cols

# def get_relevant_policy_set(policies, adm_levels, adm_cases_level, policy_level):
#     """Deprecated"""
#     """Get a version of `policies` with the relevant columns included, and duplicates dropped
#     Args:
#         policies (pandas.DataFrame): Full DataFrame of policies
#         adm_levels (list of int): List of administrative unit levels specified in DataFrame that
#             policy variables will be assigned to
#             e.g. [1, 2, 3]
#         adm_cases_level (int): Administrative unit level used for analysis of policy effects
#             i.e. (usually) the lowest level (highest `adm_level`) which pop-weights have been applied to

#     Returns:
#         pandas.DataFrame: a version of `policies` with the relevant columns included, and duplicates dropped
#     """
#     policy_cols = get_relevant_policy_cols(adm_levels, adm_cases_level)
#     groupby_cols = [col for col in policy_cols if col != 'policy_intensity'] + ['policy_level']

#     max_policy_intensities = policies.groupby(groupby_cols)[['policy_intensity']].max()

#     policies = pd.merge(policies[groupby_cols], max_policy_intensities, left_on=groupby_cols, right_index=True)

#     return policies.loc[policies['policy_level'] == policy_level][policy_cols].drop_duplicates()

# def get_popwt_policy(adm_cases, policies, policy, adm_cases_intensity_higher_cols, adm_cases_popwt_higher, adm_cases_intensity_lower, default_intensity):
#     """Deprecated"""
#     # Where higher-level intensity is higher, use weights
#     adm_cases[f'{policy}_{popweighted_suffix}'] = 0
#     pop_accounted_for = np.zeros_like(adm_cases[policy])
#     for i in range(len(adm_cases_intensity_higher_cols)):
#         col = adm_cases_intensity_higher_cols[i]
#         pop_col = adm_cases_popwt_higher[i]

#         pop_this_col = adm_cases[pop_col].where(adm_cases[col] > default_intensity, 0)

#         adm_cases[f'{policy}_{popweighted_suffix}'] += (
#             pop_this_col *
#             adm_cases[col]
#         )
#         pop_accounted_for += pop_this_col

#     if len(adm_cases_intensity_lower) > 0:
#         adm_cases[f'{policy}_{popweighted_suffix}'] += (
#             default_intensity *
#             (1 - pop_accounted_for)
#         )

#     return adm_cases[f'{policy}_{popweighted_suffix}']

# def get_default_intensity(adm_cases_intensity_lower, adm_cases, policy):
#     if len(adm_cases_intensity_lower) > 0:
#         default_intensity = np.amax(adm_cases_intensity_lower, axis=0)
#     else:
#         default_intensity = np.zeros_like(adm_cases[policy])

#     return default_intensity

# def aggregate_policies_across_levels(adm_cases, policies, adm_level, max_adm_level):
#     """Deprecated"""
#     all_policies = policies['policy'].unique()
#     for policy in all_policies:
#         # Get max of mandatory policy intensities (lower)
#         # Get max of optional policy intensities (lower)
#         # For lower levels, choose default_mandatory, else default_optional
#         # For higher levels, choose max(mandatory, default_mandatory) if > 0, else
#             # max(optional, default_optional)
#         if '_opt' in policy:
#             continue

#         policy_opt = policy + '_opt'

#         adm_cases_policy_cols = [col for col in adm_cases if col[:len(policy)] == policy and '_opt' not in col]

#         # Get all popwt cols
#         adm_cases_popwt_cols = [col for col in adm_cases_policy_cols if popweighted_suffix in col]

#         # Get all intensity cols (indicators)
#         adm_cases_intensity_cols = [col for col in adm_cases_policy_cols if popweighted_suffix not in col]

#         # Get cols at or below (lower resolution) adm level of `adm_cases`
#         adm_cases_intensity_lower_cols = [col for col in adm_cases_intensity_cols if int(col[-1]) <= adm_level]

#         adm_cases_intensity_lower = [adm_cases[col] for col in adm_cases_intensity_cols if int(col[-1]) <= adm_level]

#         # Get cols above (higher resolution) adm level of `adm_cases`
#         adm_cases_intensity_higher_cols = [col for col in adm_cases_intensity_cols if int(col[-1]) > adm_level]

#         # Get pop-weighted cols above (higher resolution) adm level of `adm_cases`
#         adm_cases_popwt_higher = [col for col in adm_cases_popwt_cols if int(col[-1]) > adm_level]

#         # Assign non-weighted col to the maximum intensity across adm levels
#         adm_cases[policy] = np.max([adm_cases[col] for col in adm_cases_intensity_cols])

#         # Assign default intensity as highest intensity at or below resolution of adm level
#         default_intensity_mandatory = get_default_intensity(adm_cases_intensity_lower, adm_cases, policy)

#         if policy not in exclude_from_popweights:
#             adm_cases[f'{policy}_{popweighted_suffix}'] = get_popwt_policy(
#                 adm_cases, policies, policy,
#                 adm_cases_intensity_higher_cols,
#                 adm_cases_popwt_higher,
#                 adm_cases_intensity_lower,
#                 default_intensity_mandatory)

#         if policy_opt in all_policies:
#             adm_cases_policy_cols_opt = [col for col in adm_cases if col[:len(policy)] == policy and '_opt' in col]

#             # Get all popwt cols
#             adm_cases_popwt_cols_opt = [col for col in adm_cases_policy_cols_opt if popweighted_suffix in col]

#             # Get all intensity cols (indicators)
#             adm_cases_intensity_cols_opt = [col for col in adm_cases_policy_cols_opt if popweighted_suffix not in col]

#             # Get cols at or below (lower resolution) adm level of `adm_cases`
#             adm_cases_intensity_lower_cols_opt = [col for col in adm_cases_intensity_cols_opt if int(col[-1]) <= adm_level]

#             adm_cases_intensity_lower_opt = [adm_cases[col] for col in adm_cases_intensity_cols_opt if int(col[-1]) <= adm_level]

#             # Get cols above (higher resolution) adm level of `adm_cases`
#             adm_cases_intensity_higher_cols_opt = [col for col in adm_cases_intensity_cols_opt if int(col[-1]) > adm_level]

#             # Get pop-weighted cols above (higher resolution) adm level of `adm_cases`
#             adm_cases_popwt_higher_opt = [col for col in adm_cases_popwt_cols_opt if int(col[-1]) > adm_level]

#             # Assign non-weighted col to the maximum intensity across adm levels
#             adm_cases[policy_opt] = np.max([adm_cases[col] for col in adm_cases_intensity_cols_opt])

#             # Assign default intensity as highest intensity at or below resolution of adm level
#             default_intensity_optional = get_default_intensity(adm_cases_intensity_lower_opt, adm_cases, policy_opt)

#             # Use optional default policy only where mandatory default policy is 0
#             default_intensity_optional = np.where(default_intensity_mandatory == 0, default_intensity_optional, default_intensity_mandatory)

#             if policy_opt not in exclude_from_popweights:
#                 adm_cases[f'{policy_opt}_{popweighted_suffix}'] = get_popwt_policy(
#                     adm_cases, policies, policy_opt,
#                     adm_cases_intensity_higher_cols_opt,
#                     adm_cases_popwt_higher_opt,
#                     adm_cases_intensity_lower_opt,
#                     default_intensity_optional)

#         dropcols = adm_cases_intensity_cols + adm_cases_popwt_cols
#         if policy_opt in all_policies:
#             dropcols += adm_cases_intensity_cols_opt + adm_cases_popwt_cols_opt
#         adm_cases = adm_cases.drop(columns=dropcols)

#     return adm_cases

# def add_subregion_spec_col(policies, min_level, max_level):
#     """Deprecated"""
#     full = pd.DataFrame()
#     for policy in policies['policy'].unique():
#         pdf = policies.loc[policies['policy'] == policy].copy()

#         all_adm_names = [f'adm{level}_name' for level in range(min_level, max_level + 1)]
#         adm_dict_levels = ['optional', 'policy_intensity'] + all_adm_names

#         def add_to_state_tracker(adm_units_with_policy, x):
#             starting_point = adm_units_with_policy

#             for level in adm_dict_levels:
#                 val = str(x[level])
#                 if val not in starting_point:
#                     starting_point[val] = dict()

#                 starting_point = starting_point[val]

#             return adm_units_with_policy

#         pdf['last_today'] = pdf['date_start'].diff(-1) != datetime.timedelta(0)
#         df = pd.DataFrame(columns=['state'] + list(pdf.columns))
#         adm_units_with_policy = dict()
#         for row in pdf.itertuples():
#             row = row._asdict()

#             adm_units_with_policy = add_to_state_tracker(adm_units_with_policy, row)

#             if row['last_today']:
#                 # Freeze adm_units at the end of the day, so that previously assigned rows on this day
#                 # are updated to the end of the day, which is then preserved for all these rows
#                 # (but continues to be updated for the following rows)
#                 adm_units_with_policy = copy.deepcopy(adm_units_with_policy)

#             row['state'] = adm_units_with_policy

#             df = df.append(row, ignore_index=True)

#         def get_best_from_group(x, i):
#             if 'All' in x[x.columns[-i]].unique():
#                 x = x[x[x.columns[-i]] == 'All'].drop_duplicates()
#             return x

#         def get_policy_at_levels(x):
#             starting_point = copy.deepcopy(x)

#             def get_rows(starting_point, keys=[]):
#                 rows = []
#                 for key in starting_point:
#                     if len(starting_point[key]) == 0:
#                         rows.append(keys + [key])

#                     rows += get_rows(starting_point[key], keys + [key])

#                 return rows

#             res = pd.DataFrame(get_rows(starting_point), columns=adm_dict_levels)

#             for i in range(1, 2 + max_level - min_level):
#                 res = res.groupby(adm_dict_levels[:-i]).apply(lambda d: get_best_from_group(d, i)).reset_index(drop=True)
#             res = res.groupby(['optional'] + all_adm_names)[['policy_intensity']].max().reset_index(drop=False)
#             return res

#         df['policy_at_levels'] = df['state'].apply(get_policy_at_levels)
#         df = df.drop(columns=['state', 'last_today', 'Index'])

#         full = pd.concat([full, df], ignore_index=True)

#     return full

# def assign_adm_policy_variables(adm_cases, policies, adm_cases_level, max_adm_level):
#     """Assign all policy variables from `policies` to `adm_cases`
#     Args:
#         adm_cases (pandas.DataFrame): table to assign policy variables to,
#             typically with case data already assigned
#         policies (pandas.DataFrame): table of policies, listed by date and regions affected
#         adm_cases_level (int): Administrative unit level used for analysis of policy effects,
#             typically the lowest level (highest `adm_level`) which pop-weights have been applied to

#     Returns:
#         pandas.DataFrame: a version of `adm_cases` with all policies from `policies` assigned as new columns
#     """
#     adm_levels = list(range(1, adm_cases_level + 1))

#     policy_cols = get_relevant_policy_cols(adm_levels, adm_cases_level)

#     for policy_level in range(0, 4):
#         adm_policies = get_relevant_policy_set(policies, adm_levels, adm_cases_level, policy_level)
#         adm_cases = initialize_policy_variables(adm_cases, adm_policies, policy_level)

#         for *adms, date_start, date_end, policy, intensity, weight in adm_policies.to_numpy():
#             policy_on_mask = get_mask(adm_cases, adms, adm_levels, date_start, date_end)
#             adm_cases = assign_policy_variable_from_mask(adm_cases, policy_on_mask, policy, intensity, weight, policy_level)

#     adm_cases = aggregate_policies_across_levels(adm_cases, policies, adm_cases_level, max_adm_level)
#     # adm_cases = count_policies_enacted(adm_cases, adm_policies)

#     return adm_cases


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


def calculate_intensities_adm_day_policy(policies_to_date, adm_level):
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

    adm_levels = sorted([int(col[3]) for col in policies.columns if col.startswith('adm') and col.endswith('name')])

    policies_to_date = policies[(policies['policy'] == policy) & 
                                (policies['date_start'] <= date) &
                                (policies['date_end'] >= date) &
                                ((policies[adm_name] == adm) | (policies[adm_name].str.lower() == 'all')) &
                                ((policies['adm1_name'] == adm1) | (policies['adm1_name'].str.lower() == 'all'))
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
    date_min = cases_df['date'].min()
    date_max = cases_df['date'].max()
    
    # Initalize panel with same structure as `cases_df`
    policy_panel = pd.DataFrame(
        index=pd.MultiIndex.from_product([
            pd.date_range(date_min, date_max), 
            sorted(cases_df[f'adm{cases_level}_name'].unique())
        ]), 
        columns=policy_list + policy_popwts).reset_index().rename(
            columns={'level_0':'date', 'level_1':f'adm{cases_level}_name'}
        ).fillna(0)

    if cases_level == 2:
        adm2_to_adm1 = cases_df[['adm1_name', 'adm2_name']].drop_duplicates().set_index('adm2_name')['adm1_name']
        adm1s = policy_panel['adm2_name'].apply(lambda x: adm2_to_adm1.loc[x])
        policy_panel.insert(1, 'adm1_name', adm1s)

    return policy_panel

def assign_policies_to_panel(cases_df, policies, cases_level, aggregate_vars=[], get_latlons=True, errors='raise'):
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
        policies['optional'] = policies['optional'].fillna(0).astype(int)
    
    policies['optional'] = policies['optional'].fillna(0)
    if errors == 'raise':
        assert len(policies['optional'].unique()) <= 2
    elif errors == 'warn':
        if len(policies['optional'].unique()) > 2:
            print('there were more than two values for optional: {0}'.format(policies['optional'].unique()))

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
        tmp = policy_panel.apply(lambda row: get_policy_vals(policies, policy, row['date'], row[f'adm{cases_level}_name'], row[f'adm1_name'], cases_level, policy_pickle_dict), axis=1)
        
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
        policy_panel = policy_panel.drop(columns=['adm1_name'])
        
    # Merge panel with `cases_df`
    merged = pd.merge(
        cases_df,
        policy_panel,
        left_on=["date", f"adm{cases_level}_name"],
        right_on=["date", f"adm{cases_level}_name"],
    )

    return merged
