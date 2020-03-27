import pandas as pd
from codes import utils as cutil

import numpy as np

#### Settings

path_cutoff_dates = cutil.HOME / 'codes' / 'data' / 'cutoff_dates.csv'
cutoff_dates = pd.read_csv(path_cutoff_dates)
cutoff = pd.to_datetime(
    str(cutoff_dates.set_index('tag').loc['default', ' end_date'])
)
use_cutoff = True

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

processed = dict()
full = dict()
for country in country_codes:
    adm = country_codes[country]
    path_processed = cutil.DATA_PROCESSED / f'adm{adm}' / (country + '_processed.csv')
    df = pd.read_csv(path_processed)
    full[country] = df

def test_condition(condition, country, message="", handle_setting="warning"):
    if condition:
        return
    
    if handle_setting == "warning":
        print("WARNING --- " + country + ": " + message)
    elif handle_setting == "error":
        raise ValueError("ERROR --- " + country + ": " + message)

for country in full:
    df = full[country]
    print(country)
    adm = country_codes[country]
    adm_name = f'adm{adm}_name'
    df = df.sort_values(['date', adm_name])
    
    if use_cutoff:
        past_cutoff_date = pd.to_datetime(df['date']).max() <= cutoff
        test_condition(past_cutoff_date, country, "Dates exceed cutoff date in processed data")

    # Check that panel is balanced
    if country != 'USA':
        for adm_field in ['adm0_name', 'adm1_name', 'adm1_id', 'adm2_name', 'adm2_id']:
            if adm_field in df.columns:
                panel_balanced = len(df.groupby('date')[adm_field].count().unique()) == 1
                test_condition(panel_balanced, country, message="Panel not balanced in processed data")

    if 'lat' in df.columns:
        # Check that lats and lons are valid
        condition = df[
            (df['lat'] < -90) |
            (df['lat'] > 90) |
            (df['lon'] < -180) |
            (df['lon'] > 180)
        ].count().sum() == 0
        
        test_condition(condition, country, "invalid lat-lon information", "error")
        
        
    # Check that all cumulative fields (including imputed) have cumulative values. Ignore cumulative fields where there is an imputed version
    for field in df.columns:
        if 'cum_' not in field:
            continue
        if '_imputed' not in field and field + '_imputed' in df.columns:
            continue
        column_is_cumulative = df.groupby([adm_name])[field].apply(
            lambda x: np.all(np.diff(np.array(x)) < 0)
        ).sum() == 0
        message = "Column is not cumulative: " + field
        test_condition(column_is_cumulative, country, message)
        
    # Check that pop-weighted columns are in [0,1] range
    popwt_cols = [col for col in df.columns if 'popwt' in col]
    for col in popwt_cols:
        popwt_in_bounds = df[(df[col] > 1) | (df[col] < 0)].count().sum() == 0
        message = "Column out of [0, 1]: " + col
        test_condition(popwt_in_bounds, country, message)
        
    # Check that no column has null values, except KOR country list
    for col in df:
        if 'country_list' in col:
            continue
        if col + '_imputed' in df.columns:
            continue
        nulls_not_found = df[col].isnull().sum() == 0
        message = "Column contains nulls: " + col
        test_condition(nulls_not_found, country, message)
    
    # Check that all columns are in template
    missing_from_template = set(df.columns) - set(template.columns)
    template_mismatch = len(missing_from_template) == 0
    message = "Columns missing from template ([country]_processed.csv): " + str(sorted(missing_from_template))
    test_condition(template_mismatch, country, message)
