import warnings

import numpy as np
import pandas as pd

import src.utils as cutil


def check_population_col_is_filled(df, adm_col, pop_col, errors="raise"):
    """Check if population column is filled

    Args:
        df (pandas.DataFrame): DataFrame containing population column and adm-unit column
        adm_col (str): Name of adm-unit column in `df`
        pop_col (str): Name of population column in `df`
        errors (str): Error-handling behavior. Options are "raise" (default), "ignore", and "warn"

    Returns:
        tuple of (bool, list):
            `col_is_valid`: True if column is valid, else False
            `null_adm`: List of adm-units missing populations

    """
    df_without_pop = df.loc[(df[adm_col].str.lower() != "all") & (df[pop_col].isnull())]
    col_is_valid = len(df_without_pop) == 0

    if not (col_is_valid or errors == "ignore"):
        null_adm = sorted(set(df_without_pop[adm_col]))
        message = f"Population not found for {adm_col}: {null_adm}"
        if errors == "warn":
            warnings.warn(message)
        elif errors == "raise":
            raise ValueError(message)
        else:
            raise ValueError("Choice of value for ``errors'' is not valid.")


def get_adm_fields(adm_level, field_name="name"):
    """Get list of adm-fields from `adm_level` up to the adm1 level"""
    return [f"adm{i}_" + field_name for i in range(1, adm_level + 1)]


def get_adm_pops(adm_level, country_code, latlons=False):
    """Get all populations at an adm-level within a country

    Args:
        adm_level (int): Adm-level of requested populations.
        country_code (str): Three-letter country code of requested populations

    Returns:
        pandas.DataFrame: List of populations at `adm_level` within country corresponding to `country_code`.
            Indexed by all levels from "adm1" (first level) up to "adm{`adm_level`}"" (last level)

    """

    # hard code in for US adm3 data
    if (country_code == "USA") and (adm_level == 3):
        path_adm = cutil.DATA_RAW / "usa" / "adm3_pop.csv"
        adm_df = pd.read_csv(path_adm)
    else:
        path_adm = (
            cutil.DATA_INTERIM / "adm" / f"adm{adm_level}" / f"adm{adm_level}.csv"
        )
        adm_df = pd.read_csv(path_adm)

    get_cols = ["population"]
    if latlons:
        get_cols += ["latitude", "longitude"]

    indices = get_adm_fields(adm_level)
    return (
        adm_df.loc[adm_df["adm0_name"] == country_code]
        .set_index(indices)[get_cols]
        .rename(
            columns={
                "population": f"adm{adm_level}_pop",
                "latitude": "lat",
                "longitude": "lon",
            }
        )
    )


def merge_policies_with_population_on_level(
    policies, adm_level, country_code, errors="raise"
):
    """Assign all populations at an adm-level to DataFrame of policies

    Args:
        policies (pandas.DataFrame): List of policies as formatted in ```data/raw/{`country_code`}/{`country_code`}_policy_data_sources.csv```
        adm_level (int): Adm-level of requested populations.
        country_code (str): Three-letter country code of requested populations
    Kwargs:
       errors (str): Error-handling behavior. Options are "raise" (default), "ignore", and "warn"

    Returns:
        pandas.DataFrame: `policies` with a new column, "adm_{`adm_level`}_pop"

    """
    adm_pop = get_adm_pops(adm_level, country_code)
    policies = pd.merge(
        policies,
        adm_pop,
        how="left",
        left_on=get_adm_fields(adm_level),
        right_index=True,
    )

    # Check that all non-"All" populations are assigned
    check_population_col_is_filled(
        policies, f"adm{adm_level}_name", f"adm{adm_level}_pop", errors
    )

    return policies


def merge_policies_with_population(
    policies, country_code, max_adm_level, errors="raise"
):
    """Assign all populations at all adm-levels to DataFrame of policies

    Args:
        policies (pandas.DataFrame): List of policies as formatted in ```data/raw/{`country_code`}/{`country_code`}_policy_data_sources.csv```
        country_code (str): Three-letter country code of requested populations
        max_adm_level (int): Adm-level at and below which populations should be assigned, down to adm1
            e.g. `max_adm_level` == 3 would assign populations at adm-levels 1, 2, and 3
    Kwargs:
       errors (str): Error-handling behavior. Options are "raise" (default), "ignore", and "warn"

    Returns:
        pandas.DataFrame: `policies` with new columns, "adm_{`adm_level`}_pop" for each `adm_level` from 1 to `max_adm_level`

    """
    for adm_level in range(1, max_adm_level + 1):
        policies = merge_policies_with_population_on_level(
            policies, adm_level, country_code, errors
        )

    return policies


def merge_cases_with_population_on_level(
    epi_df, adm_level, country_code, get_latlons=True, errors="raise"
):
    """Assign all populations at a given adm-level to DataFrame of epidemiological (cases) data

    Args:
        epi_df (pandas.DataFrame): List of cases as formatted in ```data/processed/{`adm_level`}/{`country_code`}_processed.csv```
        adm_level (int): Adm-level of requested populations.
        country_code (str): Three-letter country code of requested populations
    Kwargs:
       errors (str): Error-handling behavior. Options are "raise" (default), "ignore", and "warn".

    Returns:
        pandas.DataFrame: `epi_df` with a new column, "population"

    """
    adm_pops = get_adm_pops(adm_level, country_code, latlons=get_latlons)
    result = pd.merge(
        epi_df,
        adm_pops,
        how="left",
        right_index=True,
        left_on=get_adm_fields(adm_level),
    ).rename(columns={f"adm{adm_level}_pop": "population"})

    # Check that all non-"All" populations are assigned
    check_population_col_is_filled(result, f"adm{adm_level}_name", "population", errors)

    return result


def check_pops_in_policies(policies, max_level, errors="raise"):
    # Check that population weights are all there
    if errors == "raise":
        assert len(policies[policies["adm3_pop"].isnull()]["adm3_name"].unique()) == 1
        assert len(policies[policies["adm2_pop"].isnull()]["adm2_name"].unique()) == 1
        assert len(policies[policies["adm1_pop"].isnull()]["adm1_name"].unique()) == 1
    elif errors == "warn":
        if len(policies[policies["adm3_pop"].isnull()]["adm3_name"].unique()) != 1:
            warnings.warn("adm3 pop is null for some adm3 level")
        if len(policies[policies["adm2_pop"].isnull()]["adm2_name"].unique()) != 1:
            warnings.warn("adm2 pop is null for some adm2 level")
        if len(policies[policies["adm1_pop"].isnull()]["adm1_name"].unique()) != 1:
            warnings.warn("adm1 pop is null for some adm1 level")


def check_pops_in_cases(cases_df, errors="raise"):
    if errors == "raise":
        assert cases_df["population"].isnull().sum() == 0
    elif errors == "warn":
        if cases_df["population"].isnull().sum() != 0:
            print("there where some entries with Null population values")


def assign_all_populations(
    policies, cases_df, cases_level, get_latlons=True, errors="raise"
):
    all_adm0 = policies["adm0_name"].unique()
    assert len(all_adm0) == 1
    country_code = all_adm0[0]

    max_adm_level = max(
        [
            int(col[3])
            for col in policies.columns
            if col.startswith("adm") and col.endswith("name")
        ]
    )

    cases_df = merge_cases_with_population_on_level(
        cases_df, cases_level, country_code, get_latlons=get_latlons, errors=errors
    )
    policies = merge_policies_with_population(
        policies, country_code, max_adm_level, errors=errors
    )

    check_pops_in_policies(policies, max_adm_level, errors=errors)
    check_pops_in_cases(cases_df, errors=errors)

    return policies, cases_df
