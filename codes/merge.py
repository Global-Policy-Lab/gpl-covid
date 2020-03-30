import numpy as np
import pandas as pd

popweighted_suffix = 'popwt'
exclude_from_popweights = ['testing_regime', 'travel_ban_intl_in', 'travel_ban_intl_out']

def assign_policy_variable_from_mask(adm_cases, policy_on_mask, policy, intensity, weight, policy_level):
    """Assigns a policy as a (weighted or non-weighted) indicator to a DataFrame
    Args:
        adm_cases (pandas.DataFrame): DataFrame to assign `policy` column
        policy_on_mask (array-like) (same length as `adm_cases`): Mask where True values
            correspond to rows of `adm_cases` that the policy applies to
        policy (str): Name of policy variable to assign
        intensity (float): Intensity of policy on a (0, 1] scale.
            This is used for non-pop-weighted policy variables
        weight (float): Policy weighted by population and intensity, on a (0, 1] scale
            This is used for pop-weighted policy variables

    Returns:
        pandas.DataFrame: `adm_cases` with a new column named after `policy`, and, if
            applicable, a new column named after `policy` with `popweighted_suffix` appended
    """    
    adm_cases.loc[policy_on_mask, f'{policy}_{str(policy_level)}'] = intensity
    
    if policy not in exclude_from_popweights:
        adm_cases.loc[policy_on_mask, f'{policy}_{popweighted_suffix}_{str(policy_level)}'] = weight
    
    return adm_cases

def get_mask(adm_cases, adm_names, adm_levels, date_start, date_end):
    """Assigns a policy as a (weighted or non-weighted) indicator to a DataFrame
    Args:
        adm_cases (pandas.DataFrame): DataFrame to assign policy column
        adm_names (list of str): List of administrative unit names specified in a row of `adm_cases`
            e.g. ["California", "Alameda County", "Berkeley"]
        adm_levels (list of int): List of administrative unit levels specified in `adm_cases`
            e.g. [1, 2, 3]
        date_start (numpy.datetime64): Date when policy is enacted
        date_end (numpy.datetime64): Date when policy is revoked

    Returns:
        pandas.Series (same length as `adm_cases`): Mask where True values
            correspond to rows of `adm_cases` that the policy applies to
    """
    # All policies on or after policy was enacted, where each of these conditions applies:
        # This row's date falls within the period of the policy
        # This row's specified adm's match the policy's, either as specified or as all, for each adm
    date_in_bounds = (adm_cases['date'] >= date_start) & (adm_cases['date'] <= date_end)

    adms_covered = np.ones_like(adm_cases['date'], dtype=bool)
    for i in range(len(adm_names)):
        adms_covered = (
            (adms_covered) & 
            (
                (adm_names[i] == adm_cases[f'adm{adm_levels[i]}_name']) | (adm_names[i] == 'All')
            )
        )

    policy_on_mask = (date_in_bounds) & (adms_covered)
    return policy_on_mask

def initialize_policy_variables(adm_cases, adm_policies, policy_level):
    """Assigns a policy as 0 (not enacted) to all rows of a DataFrame
    Args:
        adm_cases (pandas.DataFrame): DataFrame to assign policy columns
        adm_policies (pandas.DataFrame): DataFrame of policies, with all
            unique policy categories listed in the 'policy' column

    Returns:
        pandas.DataFrame: `adm_cases` with new columns for all `adm_policies`
            (and their pop-weighted forms, where applicable)
    """

    # Initialize policy columns in health data
    for policy_name in adm_policies['policy'].unique():
        adm_cases[f'{policy_name}_{str(policy_level)}'] = 0
        
        # Include pop-weighted column for policies applied within the country
        if policy_name not in exclude_from_popweights:
            adm_cases[f'{policy_name}_{popweighted_suffix}_{str(policy_level)}'] = 0

    return adm_cases

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

def get_relevant_policy_cols(adm_levels, adm_cases_level):
    """Get list of columns in a policies DataFrame that are needed to create indicator variables
    Args:
        adm_levels (list of int): List of administrative unit levels specified in DataFrame that
            policy variables will be assigned to
            e.g. [1, 2, 3]
        adm_cases_level (int): Administrative unit level used for analysis of policy effects
            i.e. (usually) the lowest level (highest `adm_level`) which pop-weights have been applied to

    Returns:
        list of str: list of columns in a policies DataFrame that are needed to create indicator variables
    """
    adm_names = [f'adm{adm_level}_name' for adm_level in adm_levels]
    non_adm_name_cols = ['date_start', 'date_end', 'policy', 'policy_intensity', f'adm{adm_cases_level}_pop_intensity_weight']
    return adm_names + non_adm_name_cols

def get_relevant_policy_set(policies, adm_levels, adm_cases_level, policy_level):
    """Get a version of `policies` with the relevant columns included, and duplicates dropped
    Args:
        policies (pandas.DataFrame): Full DataFrame of policies
        adm_levels (list of int): List of administrative unit levels specified in DataFrame that
            policy variables will be assigned to
            e.g. [1, 2, 3]
        adm_cases_level (int): Administrative unit level used for analysis of policy effects
            i.e. (usually) the lowest level (highest `adm_level`) which pop-weights have been applied to

    Returns:
        pandas.DataFrame: a version of `policies` with the relevant columns included, and duplicates dropped
    """
    policy_cols = get_relevant_policy_cols(adm_levels, adm_cases_level)
    groupby_cols = [col for col in policy_cols if col != 'policy_intensity'] + ['policy_level']

    max_policy_intensities = policies.groupby(groupby_cols)[['policy_intensity']].max()

    policies = pd.merge(policies[groupby_cols], max_policy_intensities, left_on=groupby_cols, right_index=True)

    return policies.loc[policies['policy_level'] == policy_level][policy_cols].drop_duplicates()

def aggregate_policies_across_levels(adm_cases, policies, adm_level, max_adm_level):

    for policy in policies['policy'].unique():
        if '_opt' in policy:
            adm_cases_policy_cols = [
                col for col in adm_cases if col[:len(policy)] == policy
            ]
        else:
            adm_cases_policy_cols = [
                col for col in adm_cases if col[:len(policy)] == policy and '_opt' not in col
            ]

        # Get all popwt cols
        adm_cases_popwt_cols = [
            col for col in adm_cases_policy_cols if popweighted_suffix in col
        ]

        # Get all intensity cols (indicators)
        adm_cases_intensity_cols = [
            col for col in adm_cases_policy_cols if popweighted_suffix not in col
        ]

        # Assign non-weighted col to the maximum intensity across adm levels
        adm_cases[policy] = np.max([adm_cases[col] for col in adm_cases_intensity_cols])

        # Get cols at or below (lower resolution) adm level of `adm_cases`
        adm_cases_intensity_lower_cols = [
            col for col in adm_cases_intensity_cols if int(col[-1]) <= adm_level
        ]

        adm_cases_intensity_lower = [
            adm_cases[col] for col in adm_cases_intensity_cols if int(col[-1]) <= adm_level
        ]

        # Get cols above (higher resolution) adm level of `adm_cases`
        adm_cases_intensity_higher_cols = [
            col for col in adm_cases_intensity_cols if int(col[-1]) > adm_level
        ]

        # Get pop-weighted cols above (higher resolution) adm level of `adm_cases`
        adm_cases_popwt_higher = [
            col for col in adm_cases_popwt_cols if int(col[-1]) > adm_level
        ]

        # Assign default intensity as highest intensity at or below resolution of adm level
        if len(adm_cases_intensity_lower) > 0:
            default_intensity = np.amax(adm_cases_intensity_lower, axis=0)
        else:
            default_intensity = np.zeros_like(adm_cases[policy])

        if policy not in exclude_from_popweights:
            # Where higher-level intensity is higher, use weights
            adm_cases[f'{policy}_{popweighted_suffix}'] = 0
            pop_accounted_for = np.zeros_like(adm_cases[policy])
            for i in range(len(adm_cases_intensity_higher_cols)):
                col = adm_cases_intensity_higher_cols[i]
                pop_col = adm_cases_popwt_higher[i]

                pop_this_col = adm_cases[pop_col].where(adm_cases[col] > default_intensity, 0)

                adm_cases[f'{policy}_{popweighted_suffix}'] += (
                    pop_this_col *
                    adm_cases[col]
                )
                pop_accounted_for += pop_this_col

            if len(adm_cases_intensity_lower) > 0:
                adm_cases[f'{policy}_{popweighted_suffix}'] += (
                    default_intensity *
                    (1 - pop_accounted_for)
                )

        adm_cases = adm_cases.drop(columns=adm_cases_intensity_cols + adm_cases_popwt_cols)

    return adm_cases

def assign_adm_policy_variables(adm_cases, policies, adm_cases_level, max_adm_level):
    """Assign all policy variables from `policies` to `adm_cases`
    Args:
        adm_cases (pandas.DataFrame): table to assign policy variables to, 
            typically with case data already assigned
        policies (pandas.DataFrame): table of policies, listed by date and regions affected
        adm_cases_level (int): Administrative unit level used for analysis of policy effects,
            typically the lowest level (highest `adm_level`) which pop-weights have been applied to

    Returns:
        pandas.DataFrame: a version of `adm_cases` with all policies from `policies` assigned as new columns
    """
    adm_levels = list(range(1, adm_cases_level + 1))

    policy_cols = get_relevant_policy_cols(adm_levels, adm_cases_level)

    for policy_level in range(0, 4):
        adm_policies = get_relevant_policy_set(policies, adm_levels, adm_cases_level, policy_level)
        adm_cases = initialize_policy_variables(adm_cases, adm_policies, policy_level)

        for *adms, date_start, date_end, policy, intensity, weight in adm_policies.to_numpy():
            policy_on_mask = get_mask(adm_cases, adms, adm_levels, date_start, date_end)
            adm_cases = assign_policy_variable_from_mask(adm_cases, policy_on_mask, policy, intensity, weight, policy_level)
    
    adm_cases = aggregate_policies_across_levels(adm_cases, policies, adm_cases_level, max_adm_level)
    # adm_cases = count_policies_enacted(adm_cases, adm_policies) 

    return adm_cases