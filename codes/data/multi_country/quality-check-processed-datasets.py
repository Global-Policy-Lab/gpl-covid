import pandas as pd
import numpy as np
from codes import utils as cutil
import os

#### Settings

use_cutoff = cutil.PROCESSED_DATA_DATE_CUTOFF
country_list = cutil.ISOS
default_error_behavior = cutil.PROCESSED_DATA_ERROR_HANDLING

path_cutoff_dates = cutil.CODES / 'data' / 'cutoff_dates.csv'
path_template = cutil.DATA_PROCESSED / '[country]_processed.csv'


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

def check_columns_are_in_template(df, country, adm, template):
    # Check that all columns are in template
    missing_from_template = set(df.columns) - set(template.columns)
    template_matches = len(missing_from_template) == 0
    message = "Columns missing from template ([country]_processed.csv): " + str(sorted(missing_from_template))
    test_condition(template_matches, country, adm, message)

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
        max_adm = max([int(d[3:]) for d in os.listdir(cutil.DATA_PROCESSED) if d[:3] == 'adm'])
        for adm in range(0, max_adm):
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

if __name__=="__main__":
    main()