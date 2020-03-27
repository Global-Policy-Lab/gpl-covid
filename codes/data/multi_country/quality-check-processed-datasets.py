import pandas as pd
import numpy as np
from codes import utils as cutil
import os

#### Settings

path_cutoff_dates = cutil.HOME / 'codes' / 'data' / 'cutoff_dates.csv'
cutoff_dates = pd.read_csv(path_cutoff_dates)
cutoff = pd.to_datetime(
    str(cutoff_dates.set_index('tag').loc['default', 'end_date'])
)
use_cutoff = cutil.PROCESSED_DATA_DATE_CUTOFF

path_template = cutil.DATA_PROCESSED / '[country]_processed.csv'

template = pd.read_csv(path_template)

country_codes = {
    'CHN':2, 
    'FRA':1, 
    'IRN':1, 
    'ITA':2, 
    'KOR':1, 
    'USA':1,
}

# Read each country's processed datasets into `processed`
processed = dict()
for country in country_codes:
    processed[country] = dict()
    max_adm = max([int(d[3:]) for d in os.listdir(cutil.DATA_PROCESSED) if d[:3] == 'adm'])
    for adm in range(0, max_adm):
        path_processed = cutil.DATA_PROCESSED / f'adm{adm}' / f'{country}_processed.csv'
        if path_processed.exists():
            df = pd.read_csv(path_processed)
            df = df.sort_values(['date', f'adm{adm}_name'])
            processed[country][str(adm)] = df

def test_condition(condition, country, adm, message, errors=cutil.PROCESSED_DATA_ERROR_HANDLING):
    if condition or errors == "ignore":
        return
    
    full_message = f"{country} - adm{adm}: {message}"
    if errors == "warn":
        print("WARNING: " + full_message)
    elif errors == "raise":
        raise ValueError(full_message)
    else:
        raise ValueError("Choice of value for ``errors'' is not valid.")

def check_cutoff_date(df, country, adm):
    if use_cutoff:
        past_cutoff_date = pd.to_datetime(df['date']).max() <= cutoff
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

def check_columns_are_in_template(df, country, adm):
    # Check that all columns are in template
    missing_from_template = set(df.columns) - set(template.columns)
    template_matches = len(missing_from_template) == 0
    message = "Columns missing from template ([country]_processed.csv): " + str(sorted(missing_from_template))
    test_condition(template_matches, country, adm, message)


# Run a series of checks on each country
for country in processed:
    for adm in processed[country]:
        df = processed[country][adm]

        check_cutoff_date(df, country, adm)
        check_balanced_panel(df, country, adm)
        check_latlons(df, country, adm)
        check_cumulativity(df, country, adm)
        check_popweights_in_bounds(df, country, adm)
        check_columns_are_not_null(df, country, adm)
        check_columns_are_in_template(df, country, adm)
