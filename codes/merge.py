import numpy as np

popweighted_suffix = '_popwt'
exclude_from_popweights = ['testing_regime', 'travel_ban_intl_in', 'travel_ban_intl_out']

def assign_policy_variable_from_mask(adm_cases, policy_on_mask, policy, intensity, weight):
    policy_on_value = 1
    
    adm_cases.loc[policy_on_mask, policy] = policy_on_value * intensity
    
    if policy not in exclude_from_popweights:
        adm_cases.loc[policy_on_mask, policy + popweighted_suffix] = weight
    
    return adm_cases

def get_mask(adm_cases, adm_names, adm_levels, date_start, date_end):
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

def initialize_policy_variables(adm_cases, adm_policies):
    # Initialize policy columns in health data
    for policy_name in adm_policies['policy'].unique():
        adm_cases[policy_name] = 0
        
        # Include pop-weighted column for policies applied within the country
        if policy_name not in exclude_from_popweights:
            adm_cases[policy_name + popweighted_suffix] = 0

    return adm_cases

def count_policies_enacted(adm_cases, adm_policies):
    adm_cases['policies_enacted'] = 0
    for policy_name in adm_policies['policy'].unique():
        adm_cases['policies_enacted'] += adm_cases[policy_name]

    return adm_cases

def assign_adm_policy_variables(adm_cases, adm_policies, adm_cases_level):
    adm_cases = initialize_policy_variables(adm_cases, adm_policies)

    adm_levels = list(range(1, adm_cases_level + 1))
    adm_names = [f'adm{adm_level}_name' for adm_level in adm_levels]
    adm_values = adm_policies[adm_names].to_numpy()
    other_values = adm_policies[
        ['date_start', 'date_end', 'policy', 'optional', f'adm{adm_cases_level}_pop_intensity_weight', 'policy_intensity']
    ].to_numpy()

    for i in range(len(adm_values)):
        date_start, date_end, policy, optional, weight, intensity = other_values[i]
        adms = adm_values[i]
        policy_on_mask = get_mask(adm_cases, adms, adm_levels, date_start, date_end)
        adm_cases = assign_policy_variable_from_mask(adm_cases, policy_on_mask, policy, intensity, weight)
       
    adm_cases = count_policies_enacted(adm_cases, adm_policies) 
    return adm_cases