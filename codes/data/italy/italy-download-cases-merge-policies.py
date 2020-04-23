#!/usr/bin/env python
# coding: utf-8

# # Process Italy health (epi) and policy data
# - Download and process health data from GitHub at the regional (`adm1`) and provincial (`adm2`) levels
# - Clean, standardize, and impute health data
# - Merge population data
# - Merge collected policies
# - Save outputs at `data/processed/adm1/ITA_processed.csv` and `data/processed/adm2/ITA_processed.csv`

import argparse

import numpy as np

import pandas as pd
from code import impute as cimpute
from code import merge as cmerge
from code import utils as cutil

parser = argparse.ArgumentParser()
parser.add_argument(
    "--nr",
    dest="r",
    action="store_false",
    help="do not reload raw health (GitHub) datasets",
)
parser.add_argument(
    "--p", dest="p", action="store_true", help="print out print statements"
)
parser.set_defaults(r=True, p=False)
args = parser.parse_args()
reload_raw = args.r
print_stuff = args.p

# #### Define paths

dir_italy_raw = cutil.DATA_RAW / "italy"
dir_italy_interim = cutil.DATA_INTERIM / "italy"

# Inputs
# CSV form of policies Google sheet
path_italy_policies = dir_italy_raw / "ITA_policy_data_sources.csv"
url_adm2_cases = "https://raw.githubusercontent.com/pcm-dpc/COVID-19/master/dati-province/dpc-covid19-ita-province.csv"
url_adm1_cases = "https://raw.githubusercontent.com/pcm-dpc/COVID-19/master/dati-regioni/dpc-covid19-ita-regioni.csv"

# Template for processed dataset (output of this notebook)
path_template = cutil.DATA_PROCESSED / "[country]_processed.csv"


# Outputs
## Intermediate outputs
path_italy_raw_province = dir_italy_raw / "italy-cases-by-province.csv"
path_italy_raw_region = dir_italy_raw / "italy-cases-by-region.csv"
path_italy_interim_province = dir_italy_interim / "italy-cases-by-province.csv"
path_italy_interim_region = dir_italy_interim / "italy-cases-by-region.csv"

## Final outputs
path_processed_region = cutil.DATA_PROCESSED / "adm1" / "ITA_processed.csv"
path_processed_province = cutil.DATA_PROCESSED / "adm2" / "ITA_processed.csv"

# ###### Settings
# Affixes defined in `data_dictionary.gsheet`
cumulative_prefix = "cum_"
imputed_suffix = "_imputed"
popweighted_suffix = "_popwt"
optional_suffix = "_opt"


def process_raw_and_interim_health():

    # ## Download and read raw data from Github

    # #### Read inputs

    # Italy-specific data
    adm2_cases = pd.read_csv(url_adm2_cases)
    adm1_cases = pd.read_csv(url_adm1_cases)

    # ##### Save raw case data from URL to project folder
    adm2_cases.to_csv(path_italy_raw_province, index=False)
    adm1_cases.to_csv(path_italy_raw_region, index=False)

    # ## Translate and clean health data

    # ### Translate field names from Italian to project naming scheme
    # Column names based on table descriptions here: https://github.com/pcm-dpc/COVID-19
    replace_dict = {
        "data": "date",
        "lat": "lat",
        "long": "lon",
        "stato": "adm0_name",
        "denominazione_regione": "adm1_name",
        "denominazione_provincia": "adm2_name",
        "codice_regione": "adm1_id",
        "codice_provincia": "adm2_id",
        "totale_positivi": "active_cases",
        "variazione_totale_positivi": "active_cases_new",
        "totale_casi": cumulative_prefix + "confirmed_cases",
        "ricoverati_con_sintomi": cumulative_prefix + "hospitalized_symptom",
        "terapia_intensiva": cumulative_prefix + "intensive_care",
        "totale_ospedalizzati": cumulative_prefix + "hospitalized",
        "isolamento_domiciliare": cumulative_prefix + "home_confinement",
        "dimessi_guariti": cumulative_prefix + "recoveries",
        "deceduti": cumulative_prefix + "deaths",
        "totale_casi": cumulative_prefix + "confirmed_cases",
        "tamponi": cumulative_prefix + "tests",
    }

    adm2_cases = adm2_cases.rename(columns=replace_dict)
    adm1_cases = adm1_cases.rename(columns=replace_dict)

    # Clean date column
    def extract_date_from_datetime(dates):
        return pd.to_datetime(dates.str[:10])

    adm2_cases["date"] = extract_date_from_datetime(adm2_cases["date"])
    adm1_cases["date"] = extract_date_from_datetime(adm1_cases["date"])

    # TODO: replace Emilia-Romagna with Emilia Romagna in adm info (official GitHub changed name)
    adm2_cases["adm1_name"] = adm2_cases["adm1_name"].replace(
        {"Emilia-Romagna": "Emilia Romagna"}
    )
    adm1_cases["adm1_name"] = adm1_cases["adm1_name"].replace(
        {"Emilia-Romagna": "Emilia Romagna"}
    )

    # Clean lat-lon coordinates
    adm2_cases.loc[:, ["lat", "lon"]] = adm2_cases.loc[:, ["lat", "lon"]].replace(
        0, np.nan
    )
    assert adm1_cases["lat"].isnull().sum() == 0
    assert adm1_cases["lon"].isnull().sum() == 0

    # Clean unknown province names
    # "In fase di definizione/aggiornamento" translates to "Being defined / updated". These observations are dropped from the final output
    adm2_cases["adm2_name"] = adm2_cases["adm2_name"].replace(
        "In fase di definizione/aggiornamento", "Unknown"
    )

    # Drop extraneous columns
    extra_cols_adm1 = [
        col for col in adm1_cases.columns if col not in replace_dict.values()
    ]
    extra_cols_adm2 = [
        col for col in adm2_cases.columns if col not in replace_dict.values()
    ]
    if print_stuff:
        print("Adm1 extra cols:", extra_cols_adm1)
        print("Adm2 extra cols:", extra_cols_adm2)

    adm1_cases = adm1_cases.drop(columns=extra_cols_adm1)
    adm2_cases = adm2_cases.drop(columns=extra_cols_adm2)

    # Impute cumulative confirmed cases at `adm2` level on the first day of the dataset (2/24/2020) from `adm1`
    def impute_day1_adm2_cases(adm1_cases, adm2_cases):
        # Adm1 totals computed by grouping on Adm1 in the Adm2 dataset
        adm1_cases_from_provinces = adm2_cases.groupby(["date", "adm1_name"])[
            "cum_confirmed_cases"
        ].sum()

        # Compute cumulative cases in the Adm1 dataset by mapping to totals from Adm2 dataset
        def get_province_total(region_row):
            return adm1_cases_from_provinces.loc[
                region_row["date"], region_row["adm1_name"]
            ]

        # This sum should match each adm1-level total for each day, except the first day in the dataset
        adm1_province_totals = adm1_cases.apply(get_province_total, axis=1)

        # Compute DataFrame mapping adm1 names to first-day case totals that are missing in `adm2_cases`
        day1_cases = adm1_cases[
            adm1_province_totals != adm1_cases["cum_confirmed_cases"]
        ][["adm1_name", "cum_confirmed_cases"]].set_index("adm1_name")

        # Mask to fill in adm2 rows with missing day 1 cum_confirmed_cases
        replace_day1_mask = (
            (adm2_cases["adm1_name"].isin(day1_cases.index))
            & (adm2_cases["date"] == "2020-02-24")
            & (adm2_cases["adm2_name"] == "Unknown")
        )

        # Set cum_confirmed_cases of "Unknown" adm2 rows to each corresponding adm1 total on day 1
        adm2_cases.loc[replace_day1_mask, "cum_confirmed_cases"] = adm2_cases.loc[
            replace_day1_mask, "adm1_name"
        ].apply(lambda x: day1_cases.loc[x])

        # Check that all regions with positive cases on day 1 are accounted for
        adm2_cases[
            (adm2_cases["adm1_name"].isin(day1_cases.index))
            & (adm2_cases["date"] == "2020-02-24")
            & (adm2_cases["adm2_name"] == "Unknown")
        ]

        return adm2_cases

    def code_as_null_where_missing(adm1_cases, adm2_cases):
        # ###### Check data limitations
        # Go to https://github.com/pcm-dpc/COVID-19 and check "Avvisi" for any documented data issues

        # #### Fill known missing cumulative totals as nulls
        # Information on missingness gathered from GitHub "Avvisi" section
        adm1_days_missing = [
            ("2020-03-10", "Lombardia"),
            ("2020-03-11", "Abruzzo"),
            ("2020-03-16", "P.A. Trento"),
            ("2020-03-16", "Puglia"),
            ("2020-03-18", "Campania"),
        ]

        adm2_days_missing = [("2020-03-17", "Rimini"), ("2020-03-18", "Parma")]

        # Replace missing values in `adm_cases` to null. These missing values are tabulated in the source data
        # as the value of that variable on the previous non-missing day, which can skew analysis of growth rates
        def fill_missing_as_null(adm_cases, date, adm_name, adm_col):

            # Get all cumulative columns
            cum_cols = [
                col for col in adm_cases.columns if col.startswith(cumulative_prefix)
            ]

            # Replace values known to be missing with np.nan
            for col in cum_cols:
                adm_cases.loc[
                    ((adm_cases["date"] == date) & (adm_cases[adm_col] == adm_name)),
                    col,
                ] = np.nan

            return adm_cases

        # Fill in nulls for missing adm1 data, in the adm1 dataset
        for date, adm1 in adm1_days_missing:
            adm1_cases = fill_missing_as_null(adm1_cases, date, adm1, "adm1_name")

        # Fill in nulls for missing adm1 data, in the adm2 dataset
        for date, adm1 in adm1_days_missing:
            adm2_cases = fill_missing_as_null(adm2_cases, date, adm1, "adm1_name")

        # Fill in nulls for missing adm2 data, in the adm2 dataset
        for date, adm2 in adm2_days_missing:
            adm2_cases = fill_missing_as_null(adm2_cases, date, adm2, "adm2_name")

        return adm1_cases, adm2_cases

    adm2_cases = impute_day1_adm2_cases(adm1_cases, adm2_cases)
    adm1_cases, adm2_cases = code_as_null_where_missing(adm1_cases, adm2_cases)

    def impute_each_cumulative_column(adm_cases, adm_id_col):
        # Impute any cumulative totals in adm1
        adm_cases_cum_cols = [
            col for col in adm_cases.columns if col.startswith(cumulative_prefix)
        ]
        for src_col in adm_cases_cum_cols:
            dst_col = src_col + imputed_suffix
            adm_cases = cimpute.impute_cumulative_df(
                adm_cases, src_col, dst_col, adm_id_col
            )

        return adm_cases

    # #### Impute all cumulative totals in imputed column, fill as null where cumulative totals fall in source column
    adm1_cases = impute_each_cumulative_column(adm1_cases, "adm1_name")
    adm2_cases = impute_each_cumulative_column(adm2_cases, "adm2_id")

    # #### Save processed health data to `interim` folder
    path_italy_interim_province.parent.mkdir(parents=True, exist_ok=True)
    adm1_cases.to_csv(path_italy_interim_region, index=False)
    adm2_cases.to_csv(path_italy_interim_province, index=False)

    return adm1_cases, adm2_cases


def read_policies():
    policies = pd.read_csv(path_italy_policies)

    # Map some regions/provinces in policy dataset to corresponding names in health data
    replace_dict = {
        "Lombardy": "Lombardia",
        "Piedmont": "Piemonte",
        "Emilia-Romagna": "Emilia Romagna",
        "Padua": "Padova",
        "Venice": "Venezia",
        "Pesaro and Urbino": "Pesaro e Urbino",
        "Apulia": "Puglia",
        "Vo'Eugane": "Vò",
    }

    # Standardize naming between policy and health data
    policies["adm1_name"] = policies["adm1_name"].replace(replace_dict)
    policies["adm2_name"] = policies["adm2_name"].replace(replace_dict)
    policies["adm3_name"] = policies["adm3_name"].replace(replace_dict)

    # Clean data
    policies["date_start"] = pd.to_datetime(policies["date_start"])
    policies["date_end"] = pd.to_datetime(policies["date_end"])
    policies["policy"] = policies["policy"].str.strip()

    # Set default values for null fields
    policies["adm0_name"] = policies["adm0_name"].fillna("Italy")
    policies["adm1_name"] = policies["adm1_name"].fillna("All")
    policies["adm2_name"] = policies["adm2_name"].fillna("All")
    policies["adm3_name"] = policies["adm3_name"].fillna("All")

    # Remove any duplicates, grouping on relevant columns
    policies = policies[
        [
            "adm3_name",
            "adm2_name",
            "adm1_name",
            "adm0_name",
            "date_start",
            "date_end",
            "policy",
            "policy_intensity",
            "optional",
        ]
    ].drop_duplicates()

    # If this fails, have to implement `testing_regime` as categorical variable
    # This works right now because only one change in "testing_regime", a categorical variable
    assert policies.groupby("policy")["policy"].count()["testing_regime"] == 1

    # Replace optional policies with `policy_name` to `policy_name_opt`
    # policies.loc[policies['optional'] == 1, 'policy'] = policies.loc[policies['optional'] == 1, 'policy'] + optional_suffix

    return policies


def merge_health_and_policies(adm1_cases, adm2_cases, policies):

    # Filter out rows where adm1 is known but adm2 is unknown
    adm2_cases = adm2_cases[adm2_cases["adm2_name"] != "Unknown"]

    def check_adms_match(policies, adm1_cases, adm2_cases):
        # Ensure all policies listed have corresponding adm-units in health data
        adm1_not_found = (
            set(policies["adm1_name"].unique())
            - set(adm1_cases["adm1_name"].unique())
            - set(["All"])
        )
        adm2_not_found = (
            set(policies["adm2_name"].unique())
            - set(adm2_cases["adm2_name"].unique())
            - set(["All"])
        )
        assert len(adm1_not_found) == 0
        assert len(adm2_not_found) == 0

    # Check nothing's missing in template
    def check_against_template(*adm_cases_list):
        template = pd.read_csv(path_template)
        for adm_cases in adm_cases_list:
            missing_from_template = set(adm_cases.columns) - set(template.columns)
            if print_stuff:
                print(missing_from_template)
            assert len(missing_from_template) == 0

    check_adms_match(policies, adm1_cases, adm2_cases)

    # Assign policy indicators
    adm1_cases = cmerge.assign_policies_to_panel(
        adm1_cases, policies, 1, get_latlons=False
    )
    adm2_cases = cmerge.assign_policies_to_panel(
        adm2_cases, policies, 2, get_latlons=False
    )

    adm1_cases["no_gathering_size"] = 0
    adm2_cases["no_gathering_size"] = 0

    check_against_template(adm1_cases, adm2_cases)

    adm1_cases = adm1_cases.sort_values(["date", "adm1_name"], ascending=True)
    adm2_cases = adm2_cases.sort_values(["date", "adm2_name"], ascending=True)

    return adm1_cases, adm2_cases, policies


def save_processed(adm1_cases, adm2_cases):
    # Save to `ITA_processed.csv`'s
    adm1_cases.to_csv(path_processed_region, index=False)
    adm2_cases.to_csv(path_processed_province, index=False)


def load_interim_cases(path_interim):
    adm_cases = pd.read_csv(path_interim, parse_dates=["date"])
    for col in adm_cases:
        if adm_cases[col].dtype == float:
            adm_cases[col] = np.round(adm_cases[col], 10)

    return adm_cases


def get_interim_cases():
    if reload_raw:
        return process_raw_and_interim_health()
    else:
        return (
            load_interim_cases(path_italy_interim_region),
            load_interim_cases(path_italy_interim_province),
        )


def main():
    adm1_cases, adm2_cases = get_interim_cases()
    policies = read_policies()
    adm1_cases, adm2_cases, policies = merge_health_and_policies(
        adm1_cases, adm2_cases, policies
    )
    save_processed(adm1_cases, adm2_cases)


if __name__ == "__main__":
    main()
