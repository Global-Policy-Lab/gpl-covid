import numpy as np
import pandas as pd
import copy
import datetime
import pickle

popweighted_suffix = 'popwt'
exclude_from_popweights = ['testing_regime', 'travel_ban_intl_in', 'travel_ban_intl_out']

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

def count_policies_enacted(adm_cases, adm_policies):
    """Count number of (non-pop-weighted) policy variables enacted on each row of `adm_cases`
    Args:
        adm_cases (pandas.DataFrame): DataFrame with policies as columns
        adm_policies (pandas.DataFrame): DataFrame of policies, with all
            unique policy categories listed in the 'policy' column

    Returns:
        pandas.DataFrame: `adm_cases` with a new column counting number of non-pop-weighted
            policy variables in place, for each row
    """
    adm_cases['policies_enacted'] = 0
    for policy_name in adm_policies['policy'].unique():
        adm_cases['policies_enacted'] += adm_cases[policy_name]

    return adm_cases


def get_policy_vals(policies, policy, date, adm, adm_level, policy_pickle_dict):
    """Assign all policy variables from `policies` to `cases_df`
    Args:
        policies (pandas.DataFrame): table of policies, listed by date and regions affected
        policy (str): name of policy category to be applied
        date (datetime.datetime): date on which policies are applied
        adm (str): name of admin-unit on which policies are applied
        adm_level (int): level of admin-unit on which policies are applied
        policy_pickle_dict (dict of dicts): Dictionary with keys `adm` and a pickled version of
            `policies_to_date` (computed within this function) to get result if it has already
            been computed. Though messy, this saves a lot of time

    Returns:
        pandas.DataFrame: a version of `cases_df` with all policies from `policies` assigned as new columns
    """
    adm_name = f'adm{adm_level}_name'
    adm_intensity = f'adm{adm_level}_policy_intensity'
    adm_levels = sorted([int(col[3]) for col in policies.columns if col.startswith('adm') and col.endswith('name')])
    adm_lower_levels = [l for l in adm_levels if l <= adm_level]
    adm_higher_levels = [l for l in adm_levels if l > adm_level]
    policies_to_date = policies[(policies['policy'] == policy) & 
                                (policies['date_start'] <= date) &
                                (policies['date_end'] >= date) &
                                ((policies[adm_name] == adm) | (policies[adm_name] == 'All'))
                               ].copy()

    if len(policies_to_date) == 0:
        return (0, 0)

    # Check if `policies_to_date` result has already been computed for `adm`, use that result if so
    psave = pickle.dumps(policies_to_date)
    if adm not in policy_pickle_dict:
        policy_pickle_dict[adm] = dict()
    if psave in policy_pickle_dict[adm]:
        return policy_pickle_dict[adm][psave]

    # Calculate max intensity of units at this level and below (lower res), and set as default against which
    # other levels will compare
    default_policy_intensity = np.nanmax([policies_to_date.loc[policies_to_date['policy_level'].isin(adm_lower_levels), 'policy_intensity'].max(), 0])

    # Initialize final reported intensity to default intensity
    total_intensity = default_policy_intensity
    
    # For each higher level (higher res than `adm`), add any intensities that are higher than the intensities
    # at lower levels to the total intensity, and track the highest intensity for each policy up to that level
    for level in adm_higher_levels:
        this_adm_higher_than_adm = (
            (policies_to_date['policy_level'] == level) &
            (policies_to_date['policy_intensity'] > policies_to_date[adm_intensity])
        )

        additional_policy_intensities = (
            (policies_to_date.loc[this_adm_higher_than_adm, 'policy_intensity'] - policies_to_date[adm_intensity]) *
            (policies_to_date.loc[this_adm_higher_than_adm, f'adm{level}_pop'] / policies_to_date.loc[this_adm_higher_than_adm, f'adm{adm_level}_pop'])
        )

        policies_to_date.loc[this_adm_higher_than_adm, adm_intensity] += additional_policy_intensities

        total_intensity += additional_policy_intensities.sum()

    pop_weighted_intensity = min(total_intensity, 1.0)
    max_intensity = policies_to_date['policy_intensity'].max()
    policy_pickle_dict[adm][psave] = (pop_weighted_intensity, max_intensity)

    return (pop_weighted_intensity, max_intensity)

def assign_policies_to_panel(cases_df, policies, cases_level):
    """Assign all policy variables from `policies` to `cases_df`
    Args:
        cases_df (pandas.DataFrame): table to assign policy variables to, 
            typically with case data already assigned
        policies (pandas.DataFrame): table of policies, listed by date and regions affected
        cases_level (int): Administrative unit level used for analysis of policy effects,
            typically the lowest level which pop-weights have been applied to

    Returns:
        pandas.DataFrame: a version of `cases_df` with all policies from `policies` assigned as new columns
    """
    policy_list = list(policies['policy'].unique())
    policy_popwts = [p + '_popwt' for p in policy_list]

    date_min = cases_df['date'].min()
    date_max = cases_df['date'].max()

    # Initalize panel with same structure as `cases_df`
    df = pd.DataFrame(
        index=pd.MultiIndex.from_product([
            pd.date_range(date_min, date_max), 
            sorted(cases_df[f'adm{cases_level}_name'].unique())
        ]), 
        columns=policy_list + policy_popwts).reset_index().rename(
            columns={'level_0':'date', 'level_1':f'adm{cases_level}_name'}
        ).fillna(0)
    
    # Assign each policy one-by-one to the panel
    for policy in policy_list:
        policy_pickle_dict = dict()
        df[policy + '_tmp'] = df.apply(lambda row: get_policy_vals(policies, policy, row['date'], row[f'adm{cases_level}_name'], cases_level, policy_pickle_dict), axis=1)
        df[policy + '_popwt'] = df[policy + '_tmp'].apply(lambda x: x[0])
        df[policy] = df[policy + '_tmp'].apply(lambda x: x[1])
        drop_cols = [policy + '_tmp']

        if policy in exclude_from_popweights:
            drop_cols.append(policy + '_popwt')
        df = df.drop(columns=drop_cols)
        
    df['policies_enacted'] = count_policies_enacted(cases_df, policies)

    # Merge panel with `cases_df`
    merged = pd.merge(cases_df, df, left_on=['date', f'adm{cases_level}_name'], right_on=['date', f'adm{cases_level}_name'])
    
    return merged
