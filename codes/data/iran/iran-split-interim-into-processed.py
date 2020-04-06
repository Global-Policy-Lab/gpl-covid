#!/usr/bin/env python
# coding: utf-8

# # Process Iran health (epi) and policy data
# - Open interim Iran dataset
# - Clean, standardize, and impute health data
# - Merge populations
# - Save outputs at `data/processed/adm0/IRN_processed.csv` and `data/processed/adm2/IRN_processed.csv`

import pandas as pd
import numpy as np
from codes import utils as cutil

# Define paths

# Project directory
dir_data_interim = cutil.DATA_INTERIM / 'iran'
dir_adm_pop = cutil.DATA_INTERIM / 'adm'

# Input
path_iran_interim_adm0 = dir_data_interim / 'adm0' / 'IRN_interim.csv'
path_iran_interim_adm1 = dir_data_interim / 'IRN_interim.csv'
path_pop_adm1 = dir_adm_pop / 'adm1' / 'adm1.csv'
path_template = cutil.DATA_PROCESSED / '[country]_processed.csv'

# Outputs
path_iran_processed_adm0 = cutil.DATA_PROCESSED / 'adm0' / 'IRN_processed.csv'
path_iran_processed_adm1 = cutil.DATA_PROCESSED / 'adm1' / 'IRN_processed.csv'


# Read interim datasets
adm0_df = pd.read_csv(path_iran_interim_adm0, parse_dates=['date'])
adm1_df = pd.read_csv(path_iran_interim_adm1, parse_dates=['date'])

# Population data
adm1_pop_df = pd.read_csv(path_pop_adm1)


# #### Clean `adm1_df` and `adm0_df`

# Rename `adm2` to `adm1` (correct previous coding error), remove old `adm1`
adm1_df = adm1_df.drop(columns=['adm1_name'])
adm1_df = adm1_df.rename(columns={'adm2_name':'adm1_name'})


# Drop unnecessary columns (these totals are accounted for in `cum_` columns
adm0_df = adm0_df.drop(columns=['new_confirmed_cases', 'new_deaths_national'])
adm1_df = adm1_df.drop(columns=['new_confirmed_cases', 'new_confirmed_cases_imputed'])
adm1_df = adm1_df.sort_values(['date', 'adm1_name'])


# Merge in population
adm1_pop_iran = adm1_pop_df.loc[adm1_pop_df['adm0_name'] == 'IRN'].copy()

# Standardize province names to `adm1.csv`
replace_dict = {
    'Alburz': 'Alborz',
    'Chaharmahal.and.Bakhtiari': 'Chahar Mahall and Bakhtiari',
    'East.Azerbaijan': 'East Azarbaijan',
    'Hamedan': 'Hamadan',
    'Khuzistan': 'Khuzestan',
    'Kohgiluyeh.and.Boyer_Ahmad': 'Kohgiluyeh and Buyer Ahmad',
    'Kurdistan': 'Kordestan',
    'North.Khorasan': 'North Khorasan',
    'Razavi.Khorasan': 'Razavi Khorasan',
    'Sistan.and.Baluchestan': 'Sistan and Baluchestan',
    'South.Khorasan': 'South Khorasan',
    'West.Azerbaijan': 'West Azarbaijan'
}

# Create adm1 population Series
adm1_pops = adm1_pop_iran.set_index('adm1_name')['population']

# Replace province names with standardized versions
adm1_df['adm1_name'] = adm1_df['adm1_name'].replace(replace_dict)

# Assign population data
adm1_df['population'] = adm1_df['adm1_name'].apply(
    lambda adm1: adm1_pops.loc[adm1] if adm1 in adm1_pops else np.nan
)

# Make sure no population tallies are missing
assert adm1_df['population'].isnull().sum() == 0


# Define imputation functions
def convert_non_monotonic_to_nan(array):
    """Converts a numpy array to a monotonically increasing one.
    Args:
        array (numpy.ndarray [N,]): input array
    Returns:
        numpy.ndarray [N,]: some values marked as missing, all non-missing
            values should be monotonically increasing
    Usage:
        >>> convert_non_monotonic_to_nan(np.array([0, 0, 5, 3, 4, 6, 3, 7, 6, 7, 8]))
        np.array([ 0.,  0., np.nan,  3., np.nan, np.nan,  3., np.nan,  6.,  7.,  8.])
    """
    keep = np.arange(0, len(array))
    is_monotonic = False
    while not is_monotonic:
        is_monotonic_array = np.hstack((
            array[keep][1:] >= array[keep][:-1], np.array(True)))
        is_monotonic = is_monotonic_array.all()
        keep = keep[is_monotonic_array]
    out_array = np.full_like(array.astype(np.float), np.nan)
    out_array[keep] = array[keep]
    return out_array

def log_interpolate(array):
    """Interpolates assuming log growth.
    Args:
        array (numpy.ndarray [N,]): input array with missing values
    Returns:
        numpy.ndarray [N,]: all missing values will be filled
    Usage:
        >>> log_interpolate(np.array([0, np.nan, 2, np.nan, 4, 6, np.nan, 7, 8]))
        np.array([0, 0, 2, 3, 4, 6, 7, 7, 8])
    """
    idx = np.arange(0, len(array))
    log_array = np.log(array.astype(np.float32) + 1e-1)
    interp_array = np.interp(
        x=idx, xp=idx[~np.isnan(array)], fp=log_array[~np.isnan(array)])
    return np.round(np.exp(interp_array)).astype(np.int32)

def impute_cumulative_array(array):
    """Ensures array is cumulative, imputing where necessary
    Args:
        array-like (numpy.ndarray [N,], pandas.Series, etc.): input array with missing values
    Returns:
        numpy.ndarray [N,]: all non-monotonic values will be filled by logarithmic interpolation
    Usage:
        >>> impute_cumulative_array(np.array([0, 0, 5, 3, 4, 6, 3, 7, 6, 7, 8]))
        np.array([0, 0, 2, 3, 4, 6, 7, 7, 8])
    """
    array = np.array(array).copy()
    array = convert_non_monotonic_to_nan(array)
    array = log_interpolate(array)
    return array

def impute_cumulative_df(df, src_col, dst_col, groupby_col):
    """Calculates imputed columns and returns 
    Args:
        df (pandas.DataFrame): input DataFrame with a cumulative column
        src_col (str): name of cumulative column to impute
        dst_col (str): name of imputed cumulative column
        groupby_col (str): name of column containing names of administrative units,
            values should correspond to groups whose values should be accumulating
    Returns:
        pandas.DataFrame: a copy of `df` with a newly imputed column specified by `dst_col`
    Usage:
        >>> impute_cumulative_df(pandas.DataFrame([[0, 'a'], [5, 'b'], [3, 'a'], [2, 'a'], [6, 'b']]), 0, 1)
        pandas.DataFrame([[0, 'a', 0], [5, 'b', 5], [3, 'a', 0], [2, 'a', 2], [6, 'b', 6]], columns=[0, 1, 'imputed'])
    """
    if src_col not in df.columns:
        raise ValueError(f"'{src_col}' not found")
    
    if dst_col not in df.columns:
        df[dst_col] = -1
        
    for adm_name in df[groupby_col].unique():
        sub = df.loc[df[groupby_col] == adm_name].copy()
        sub[dst_col] = impute_cumulative_array(sub[src_col])
        
        # Replace non-monotonic values in original `cum_confirmed_cases` column with nulls
        raw_cum_col = 'cum_confirmed_cases'
        sub.loc[sub[raw_cum_col].notnull(), raw_cum_col] = convert_non_monotonic_to_nan(
            np.array(sub.loc[sub[raw_cum_col].notnull(), raw_cum_col])
        )
        
        df.loc[df[groupby_col] == adm_name] = sub
        
    return df


# Impute cumulative confirmed cases
imputed_suffix = "_imputed"
cumulative_prefix = "cum_"

src_col = cumulative_prefix + 'confirmed_cases' + imputed_suffix
dst_col = src_col
adm1_df = impute_cumulative_df(adm1_df, src_col, dst_col, 'adm1_name')


# Check that all columns are in template

template = pd.read_csv(path_template)
assert len(set(adm0_df.columns) - set(template.columns)) == 0
assert len(set(adm1_df.columns) - set(template.columns)) == 0


# Output to `IRN_processed.csv` datasets

path_iran_processed_adm0.parent.mkdir(parents=True, exist_ok=True)
path_iran_processed_adm1.parent.mkdir(parents=True, exist_ok=True)
adm0_df.to_csv(path_iran_processed_adm0, index=False)
adm1_df.to_csv(path_iran_processed_adm1, index=False)

