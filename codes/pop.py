import codes.utils as cutil
import pandas as pd
import numpy as np

def get_adm_fields(adm_level, field_name='name'):
    """Get list of adm-fields from `adm_level` up to the adm1 level"""
    return [f'adm{i}_' + field_name for i in range(1, adm_level + 1)]

def get_adm_pops(adm_level, country_code):
    """Get all populations at an adm-level within a country

    Args:
        adm_level (int): Adm-level of requested populations.
        country_code (str): Three-letter country code of requested populations

    Returns:
        pandas.DataFrame: List of populations at `adm_level` within country corresponding to `country_code`.
            Indexed by all levels from "adm1" (first level) up to "adm{`adm_level`}"" (last level)

    """
    path_adm = cutil.DATA_INTERIM / 'adm' / f'adm{adm_level}' / f'adm{adm_level}.csv'
    adm_df = pd.read_csv(path_adm)
    indices = get_adm_fields(adm_level)
    return (adm_df.loc[adm_df['adm0_name'] == country_code]
            .set_index(indices)[['population']]
            .rename(columns={
                'population':f'adm{adm_level}_pop'
            }))

def merge_policies_with_population_on_level(policies, adm_level, country_code):
    """Assign all populations at an adm-level to DataFrame of policies

    Args:
        policies (pandas.DataFrame): List of policies as formatted in ```data/raw/{`country_code`}/{`country_code`}_policy_data_sources.csv```
        adm_level (int): Adm-level of requested populations.
        country_code (str): Three-letter country code of requested populations

    Returns:
        pandas.DataFrame: `policies` with a new column, "adm_{`adm_level`}_pop"

    """
    adm_pop = get_adm_pops(adm_level, country_code)
    policies = pd.merge(
        policies, 
        adm_pop, 
        how='left', 
        left_on=get_adm_fields(adm_level), 
        right_index=True,   
    )
    return policies

def merge_policies_with_population(policies, country_code, max_adm_level):
    """Assign all populations at all adm-levels to DataFrame of policies

    Args:
        policies (pandas.DataFrame): List of policies as formatted in ```data/raw/{`country_code`}/{`country_code`}_policy_data_sources.csv```
        country_code (str): Three-letter country code of requested populations
        max_adm_level (int): Adm-level at and below which populations should be assigned, down to adm1
            e.g. `max_adm_level` == 3 would assign populations at adm-levels 1, 2, and 3

    Returns:
        pandas.DataFrame: `policies` with new columns, "adm_{`adm_level`}_pop" for each `adm_level` from 1 to `max_adm_level`

    """
    for adm_level in range(1, max_adm_level + 1):
        policies = merge_policies_with_population_on_level(policies, adm_level, country_code)
    return policies

def merge_cases_with_population_on_level(epi_df, adm_level, country_code):
    """Assign all populations at a given adm-level to DataFrame of epidemiological (cases) data

    Args:
        epi_df (pandas.DataFrame): List of cases as formatted in ```data/processed/{`adm_level`}/{`country_code`}_processed.csv```
        adm_level (int): Adm-level of requested populations.
        country_code (str): Three-letter country code of requested populations
    Returns:
        pandas.DataFrame: `epi_df` with a new column, "population"

    """
    adm_pops = get_adm_pops(adm_level, country_code)
    return pd.merge(
        epi_df, 
        adm_pops, 
        right_index=True, 
        left_on=get_adm_fields(adm_level)
    ).rename(
        columns={f'adm{adm_level}_pop':'population'}
    )

def calculate_policy_popweights_each_row(policies, max_adm_level):
    """Assign population weights of a single policy row to DataFrame of policy data

    Args:
        policies (pandas.DataFrame): List of policies as formatted in ```data/raw/{`country_code`}/{`country_code`}_policy_data_sources.csv```,
            with "_pop" columns already assigned.
        max_adm_level (int): Adm-level at and below which population weights should be assigned, down to adm1
            e.g. `max_adm_level` == 3 would assign population weights at adm-levels 1, 2, and 3
    Returns:
        pandas.DataFrame: `policies` with a new column for each level up to `max_adm_level`
            i.e. "adm_{`adm_level`}_pop_weight_perc_newtoday" for each `adm_level` from 1 to `max_adm_level`

    """
    for adm_level in range(max_adm_level, 0, -1):
        lower_level = f'adm{adm_level + 1}_pop'
        this_level = f'adm{adm_level}_pop'
        lower_level_weight = f'adm{adm_level + 1}_pop_weight_perc_newtoday'
        this_level_weight = f'adm{adm_level}_pop_weight_perc_newtoday'
        policies[this_level_weight] = np.nan
        
        multiplier = policies[lower_level_weight] if lower_level_weight in policies.columns else 1
        
        policies.loc[
            policies[lower_level].notnull(),
            this_level_weight
        ] = (
            multiplier * policies[lower_level] / policies[this_level]
        )

        policies.loc[policies[lower_level].isnull(), this_level_weight] = 1

    return policies

def aggregate_policy_popweights(policies, adm_level, country_code):
    """Assign all population weights to DataFrame of policy data

    Args:
        policies (pandas.DataFrame): List of policies as formatted in ```data/raw/{`country_code`}/{`country_code`}_policy_data_sources.csv```,
            with "_pop" columns and "_pop_weight_perc_newtoday" already assigned.
        max_adm_level (int): Adm-level at and below which population weights should be assigned, down to adm1
            e.g. `max_adm_level` == 3 would assign population weights at adm-levels 1, 2, and 3
    Returns:
        pandas.DataFrame: `policies` with 
            1. a new column for each level up to `max_adm_level`
                i.e. "adm_{`adm_level`}_pop_weight_perc" for each `adm_level` from 1 to `max_adm_level`
            2. temporary column dropped "adm_{`adm_level`}_pop_weight_perc_newtoday"

    """
    sum_each_day = policies.sort_values('date_start').groupby(['date_start', 'policy', f'adm{adm_level}_name'])[f'adm{adm_level}_pop_weight_perc_newtoday'].sum().reset_index()

    sum_cumulative = sum_each_day.groupby([f'adm{adm_level}_name', 'policy'])[f'adm{adm_level}_pop_weight_perc_newtoday'].cumsum()
    sum_cumulative.name = f'cum_adm{adm_level}_pop_weight_perc'
    sum_cumulative.loc[sum_cumulative > 1] = 1

    sum_cumulative = sum_each_day.join(sum_cumulative)

    sum_cumulative = sum_cumulative.set_index(['date_start', 'policy', f'adm{adm_level}_name'])[[f'cum_adm{adm_level}_pop_weight_perc']]
    sum_cumulative.name = f'cum_adm{adm_level}_pop_weight_perc'
    policies = pd.merge(policies, sum_cumulative, how='left', left_on=['date_start', 'policy', f'adm{adm_level}_name'], right_index=True)

    policies[f'adm{adm_level}_pop_weight_perc'] = policies[f'cum_adm{adm_level}_pop_weight_perc']
    policies = policies.drop(columns=[
        f'cum_adm{adm_level}_pop_weight_perc', f'adm{adm_level}_pop_weight_perc_newtoday'
    ])
    return policies