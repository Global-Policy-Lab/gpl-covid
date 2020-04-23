#!/usr/bin/env python
# coding: utf-8

# # Tabulate policies by country and adm-level
# - Save Google Sheet of policies as Excel file
# - Calculate number of policies for each country / adm-level

import code.utils as cutil
import pandas as pd

path_data_sources = cutil.HOME / "references" / "data_sources.xlsx"

path_out_csv = (
    cutil.HOME / "results" / "tables" / "table_a1" / "policy_counts_table_raw.csv"
)
path_out_csv.parent.mkdir(parents=True, exist_ok=True)

countries = ["china", "france", "iran", "italy", "korea", "usa"]

# Read in policies for each country, into dict of DataFrames
policies = dict()
for country in countries:
    policies[country] = pd.read_excel(path_data_sources, sheet_name="policy_" + country)
    policies[country] = policies[country].rename(columns={"date": "date_start"})


def get_policy_level(row):
    """Assign row to a policy level by choosing the highest level of specificity of the policy within the row"""
    for level in ["adm3", "adm2", "adm1"]:
        level_name = level + "_name"
        if level_name in row and row[level_name] not in ["All", "all"]:
            return level

    return "adm0"


def get_adm_counts(policies_df):
    """Get adm-level policy counts for a country policy sheet"""

    # List all adm-levels in this policy sheet
    adm_levels = set(["adm0_name", "adm1_name", "adm2_name", "adm3_name"]) & set(
        policies_df.columns
    )

    # Group by all existing adm-levels, along with date and policy category
    groupby_cols = sorted(list(adm_levels) + ["date_start", "policy"])

    # Check for missing values
    for col in groupby_cols:
        assert policies_df[col].isnull().sum() == 0

    # Drop duplicates over groupby_cols
    policies_df = policies_df[groupby_cols].drop_duplicates()

    # Replace 'all' with 'All' to work with `get_policy_level()`
    for adm_level in adm_levels:
        policies_df[adm_level] = policies_df[adm_level].replace({"all": "All"})

    # Don't count testing regime changes
    policies_df = policies_df[policies_df["policy"] != "testing_regime"]

    # Determine adm-level of each policy in `policies_df`
    policies_df["policy_level"] = policies_df.apply(get_policy_level, axis=1)

    # Return adm-level counts for this country
    return policies_df.groupby("policy_level")["policy_level"].count().to_dict()


country_counts = dict()
for country in policies:
    country_counts[country] = get_adm_counts(policies[country])


# Turn country-adm-level dict into table
country_counts_df = pd.DataFrame.from_dict(country_counts).transpose()[
    ["adm0", "adm1", "adm2", "adm3"]
]
country_counts_df = country_counts_df.fillna(0).sort_index()

# Add total row and column
country_counts_df["total"] = country_counts_df.sum(axis=1)
country_counts_df = country_counts_df.append(
    country_counts_df.sum(axis=0).rename("total")
).astype(int)
country_counts_df.to_csv(path_out_csv, index=True)
