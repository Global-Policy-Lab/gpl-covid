import pandas as pd
import numpy as np
from codes import utils as cutil
import os
import argparse

parser = argparse.ArgumentParser(
    description='Check for issues in [country]_processed.csv datasets. '
        'Defaults to checking all of datasets.'
    )

max_adm = max([int(d[3:]) for d in os.listdir(cutil.DATA_PROCESSED) if d[:3] == 'adm'])
all_adm = list(range(0, max_adm + 1))

parser.add_argument("--a", choices=all_adm, default=None, type=int, help=f"Adm-level")
parser.add_argument("--c", choices=sorted(cutil.ISOS), default=None, type=str.upper, help=f"Country ISO code")
parser.add_argument("--e", choices=["raise", "warn"], default="raise", type=str, help=f"Error behavior")
args = parser.parse_args()

def get_adm_list(adm_input):
    if adm_input != None:
        return [adm_input]    
    return all_adm

def get_country_list(country_input):
    if country_input != None:
        return [country_input]
    return cutil.ISOS

def get_default_error_behavior(error_input):
    if error_input != None:
        return error_input
    return cutil.PROCESSED_DATA_ERROR_HANDLING


#### Settings

adm_list = get_adm_list(args.a)
country_list = get_country_list(args.c)
default_error_behavior = get_default_error_behavior(args.e)

use_cutoff = cutil.PROCESSED_DATA_DATE_CUTOFF    

path_cutoff_dates = cutil.CODES / 'data' / 'cutoff_dates.csv'
path_template = cutil.DATA_PROCESSED / '[country]_processed.csv'
path_data_dictionary = cutil.HOME / 'references' / 'data_dictionary.xlsx'

def test_condition(condition, country, adm, message, errors=default_error_behavior):
    if condition or errors == "ignore":
        return
    
    full_message = f"{country} - adm{adm}: {message}"
    if errors == "warn":
        print("WARNING: " + full_message)
    elif errors == "raise":
        raise ValueError(full_message)
    else:
        raise ValueError("Choice of value for ``errors'' is not valid.")

def check_cutoff_date(df, country, adm, cutoff_date):
    if use_cutoff:
        past_cutoff_date = pd.to_datetime(df['date']).max() <= cutoff_date
        test_condition(past_cutoff_date, country, adm, "Dates exceed cutoff date")

def check_balanced_panel(df, country, adm):
    # Check that panel is balanced
    for adm_field in ['adm0_name', 'adm1_name', 'adm1_id', 'adm2_name', 'adm2_id']:
        if adm_field in df.columns:
            panel_balanced = len(df.groupby('date')[adm_field].count().unique()) == 1
            test_condition(panel_balanced, country, adm, "Panel not balanced")

def check_latlons(df, country, adm):
    latlon_cols_exist = 'lat' in df.columns and 'lon' in df.columns
    test_condition(latlon_cols_exist, country, adm, "missing lat-lon fields")

    if latlon_cols_exist:
        no_missing_vals = df['lat'].isnull().sum() == 0 and df['lon'].isnull().sum() == 0
        test_condition(no_missing_vals, country, adm, "missing some lat-lon coordinates")

        # Check that lats and lons are valid
        coords_in_bounds = df[
            (df['lat'] < -90) |
            (df['lat'] > 90) |
            (df['lon'] < -180) |
            (df['lon'] > 180)
        ].count().sum() == 0
        
        test_condition(coords_in_bounds, country, adm, "invalid lat-lon coordinates")

def check_cumulativity(df, country, adm):
    # Check that all cumulative fields (including imputed) have cumulative values. Ignore cumulative fields where there is an imputed version
    for field in df.columns:
        if 'cum_' not in field:
            continue
        if '_imputed' not in field and field + '_imputed' in df.columns:
            continue
            
        adm_name = f"adm{adm}_name"
        
        column_is_cumulative = df.groupby([adm_name])[field].apply(
            lambda x: np.all(np.diff(np.array(x)) < 0)
        ).sum() == 0

        test_condition(column_is_cumulative, country, adm, f"Column is not cumulative: {field}")

def check_popweights_in_bounds(df, country, adm):
    # Check that pop-weighted columns are in [0,1] range
    popwt_cols = [col for col in df.columns if 'popwt' in col]
    for col in popwt_cols:
        popwt_in_bounds = df[(df[col] > 1) | (df[col] < 0)].count().sum() == 0
        test_condition(popwt_in_bounds, country, adm, f"Column out of [0, 1]: {col}")

def check_columns_are_not_null(df, country, adm):
    # Check that no column has null values, except KOR country list and pre-imputed cumulative columns
    for col in df:
        if 'country_list' in col:
            continue
        if col + '_imputed' in df.columns:
            continue
        nulls_not_found = df[col].isnull().sum() == 0
        test_condition(nulls_not_found, country, adm, f"Column contains nulls: {col}")

def _check_columns_are_in_list(df, country, adm, list_items, list_name):
    missing_from_list = set(df.columns) - set(list_items)
    list_matches = len(missing_from_list) == 0
    list_mismatches = str(sorted(missing_from_list))
    message = f"Columns missing from {list_name}: {list_mismatches}" 
    test_condition(list_matches, country, adm, message)

def check_columns_are_in_template(df, country, adm, template):
    # Check that all columns are in template
    _check_columns_are_in_list(df, country, adm, template.columns, "template")

def check_columns_are_in_data_dictionary(df, country, adm):
    country_processed = pd.read_excel(path_data_dictionary, sheet_name='country_processed')
    policy_categories = pd.read_excel(path_data_dictionary, sheet_name='policy_categories')
    health_cols = set(country_processed['Variable Name'])

    add_health_cols = set()
    if 'adm[1,2]_id' in health_cols:
        add_health_cols.add('adm1_id')
        add_health_cols.add('adm2_id')
    for col in health_cols:
        if col[:4] == "cum_" or col[:7] == "active_":
            add_health_cols.add(col + "_imputed")

    health_cols = health_cols.union(add_health_cols)

    policy_cols = set(policy_categories['Category Name'])
    add_policy_cols = set()
    if "no_gathering" in policy_cols:
        add_policy_cols.add("no_gathering_size")

    for col in policy_cols:
        for opt in ["", "_opt"]:
            for popwt in ["", "_popwt"]:
                varname = col + opt + popwt
                add_policy_cols.add(varname)
                if "travel_ban" in col:
                    add_policy_cols.add(varname + "_country_list")

    policy_cols = policy_cols.union(add_policy_cols)
    all_cols = policy_cols.union(health_cols)
    _check_columns_are_in_list(df, country, adm, all_cols, "data dictionary")

def check_opt_and_non_opt_align(df, country, adm):
    for col in df.columns:
        if "_opt" in col and col.replace("_opt", "") in df.columns:
            nonopt_col = col.replace("_opt", "")
            row_mismatch_len = len(df[df[nonopt_col] + df[col] > 1])
            cols_add_to_one_or_below = row_mismatch_len == 0
            message = f"Sum of fields > 1 in cols {nonopt_col} and {col}, in {row_mismatch_len} cases"
            test_condition(cols_add_to_one_or_below, country, adm, message)

def get_cutoff_date(path_cutoff_dates):
    cutoff_table = pd.read_csv(path_cutoff_dates)
    cutoff_date = pd.to_datetime(
        str(cutoff_table.set_index('tag').loc['default', 'end_date'])
    )

    return cutoff_date

def get_processed_datasets():
    # Read each country's processed datasets into `processed`
    processed = dict()

    for country in country_list:
        processed[country] = dict()
        for adm in adm_list:
            path_processed = cutil.DATA_PROCESSED / f'adm{adm}' / f'{country}_processed.csv'
            if path_processed.exists():
                df = pd.read_csv(path_processed)
                df = df.sort_values(['date', f'adm{adm}_name'])
                processed[country][str(adm)] = df

    return processed

def main():
    cutoff_date = get_cutoff_date(path_cutoff_dates)
    template = pd.read_csv(path_template)
    processed = get_processed_datasets()

    # Run a series of checks on each country
    for country in processed:
        for adm in processed[country]:
            df = processed[country][adm]

            check_cutoff_date(df, country, adm, cutoff_date)
            check_balanced_panel(df, country, adm)
            check_latlons(df, country, adm)
            check_cumulativity(df, country, adm)
            check_popweights_in_bounds(df, country, adm)
            check_columns_are_not_null(df, country, adm)
            check_columns_are_in_template(df, country, adm, template)
            check_opt_and_non_opt_align(df, country, adm)
            check_columns_are_in_data_dictionary(df, country, adm)

if __name__=="__main__":
    main()