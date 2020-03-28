#!/usr/bin/env python
# coding: utf-8

# # Process Italy health (epi) and policy data
# - Download and process health data from GitHub at the regional (`adm1`) and provincial (`adm2`) levels
# - Clean, standardize, and impute health data
# - Merge population data
# - Merge collected policies
# - Save outputs at `data/processed/adm1/ITA_processed.csv` and `data/processed/adm2/ITA_processed.csv`

import pandas as pd
import numpy as np
from codes import utils as cutil
from codes import pop as cpop
from codes import merge as cmerge

# #### Define paths

# Template for processed dataset (output of this notebook)
path_template = cutil.DATA_PROCESSED / '[country]_processed.csv'
dir_italy_raw = cutil.DATA_RAW / 'italy'
dir_italy_interim = cutil.DATA_INTERIM / 'italy'

# Inputs
# CSV form of policies Google sheet
path_italy_policies = dir_italy_raw / 'ITA_policy_data_sources.csv'
url_adm2_cases = "https://raw.githubusercontent.com/pcm-dpc/COVID-19/master/dati-province/dpc-covid19-ita-province.csv"
url_adm1_cases = "https://raw.githubusercontent.com/pcm-dpc/COVID-19/master/dati-regioni/dpc-covid19-ita-regioni.csv"

# Outputs
## Intermediate outputs
path_italy_raw_province = dir_italy_raw / 'italy-cases-by-province.csv'
path_italy_raw_region = dir_italy_raw / 'italy-cases-by-region.csv'
path_italy_interim_province = dir_italy_interim / 'italy-cases-by-province.csv'
path_italy_interim_region = dir_italy_interim / 'italy-cases-by-region.csv'

## Final outputs
path_processed_region = cutil.DATA_PROCESSED / 'adm1' / 'ITA_processed.csv'
path_processed_province = cutil.DATA_PROCESSED / 'adm2' / 'ITA_processed.csv'

# ## Download and read raw data from Github

# #### Read inputs
# Columns in template (i.e. columns allowed in output)
template_cols = set(pd.read_csv(path_template).columns)

# Italy-specific data
adm2_cases = pd.read_csv(url_adm2_cases)
adm1_cases = pd.read_csv(url_adm1_cases)

policies_full = pd.read_csv(path_italy_policies)


# ##### Save raw case data from URL to project folder
adm2_cases.to_csv(path_italy_raw_province, index=False)
adm1_cases.to_csv(path_italy_raw_region, index=False)

# ## Translate and clean health data

# ###### Settings
# Affixes defined in `data_dictionary.gsheet`
cumulative_prefix = 'cum_'
imputed_suffix = '_imputed'
popweighted_suffix = '_popwt'
optional_suffix = '_opt'


# ### Translate field names from Italian to project naming scheme
# Column names based on table descriptions here: https://github.com/pcm-dpc/COVID-19
replace_dict = {
    'data':'date',
    'lat':'lat',
    'long':'lon',
    'stato':'adm0_name',
    'denominazione_regione':'adm1_name',
    'denominazione_provincia':'adm2_name',
    'codice_regione':'adm1_id',
    'codice_provincia':'adm2_id',
    'totale_attualmente_positivi':'active_cases',
    'nuovi_attualmente_positivi':'active_cases_new',
    'totale_casi':cumulative_prefix + 'confirmed_cases',
    'ricoverati_con_sintomi':cumulative_prefix + 'hospitalized_symptom',
    'terapia_intensiva':cumulative_prefix + 'intensive_care',
    'totale_ospedalizzati':cumulative_prefix + 'hospitalized',
    'isolamento_domiciliare':cumulative_prefix + 'home_confinement',
    'dimessi_guariti': cumulative_prefix + 'recoveries',
    'deceduti': cumulative_prefix + 'deaths',
    'totale_casi': cumulative_prefix + 'confirmed_cases',
    'tamponi':cumulative_prefix + 'tests',
}

adm2_cases = adm2_cases.rename(columns=replace_dict)
adm1_cases = adm1_cases.rename(columns=replace_dict)

# Clean date column
def extract_date_from_datetime(dates):
    return pd.to_datetime(dates.str[:10])

adm2_cases['date'] = extract_date_from_datetime(adm2_cases['date'])
adm1_cases['date'] = extract_date_from_datetime(adm1_cases['date'])

# Clean lat-lon coordinates
adm2_cases.loc[:,['lat','lon']] = adm2_cases.loc[:,['lat','lon']].replace(0, np.nan)
assert adm1_cases['lat'].isnull().sum() == 0
assert adm1_cases['lon'].isnull().sum() == 0

# Clean unknown province names
# "In fase di definizione/aggiornamento" translates to "Being defined / updated". These observations are dropped from the final output
adm2_cases['adm2_name'] = adm2_cases['adm2_name'].replace('In fase di definizione/aggiornamento', 'Unknown')

# Drop extraneous columns
adm1_cases = adm1_cases.drop(columns=[col for col in adm1_cases.columns if col not in replace_dict.values()])
adm2_cases = adm2_cases.drop(columns=[col for col in adm2_cases.columns if col not in replace_dict.values()])

# Impute cumulative confirmed cases at `adm2` level on the first day of the dataset (2/24/2020) from `adm1`
def impute_day1_adm2_cases(adm1_cases, adm2_cases):
	# Adm1 totals computed by grouping on Adm1 in the Adm2 dataset
	adm1_cases_from_provinces = adm2_cases.groupby(['date', 'adm1_name'])['cum_confirmed_cases'].sum()

	# Compute cumulative cases in the Adm1 dataset by mapping to totals from Adm2 dataset
	def get_province_total(region_row):
	    return adm1_cases_from_provinces.loc[region_row['date'], region_row['adm1_name']]

	# This sum should match each adm1-level total for each day, except the first day in the dataset
	adm1_province_totals = adm1_cases.apply(get_province_total, axis=1)

	# Compute DataFrame mapping adm1 names to first-day case totals that are missing in `adm2_cases`
	day1_cases = adm1_cases[adm1_province_totals != adm1_cases['cum_confirmed_cases']][['adm1_name', 'cum_confirmed_cases']].set_index('adm1_name')

	# Mask to fill in adm2 rows with missing day 1 cum_confirmed_cases
	replace_day1_mask = (
	    (adm2_cases['adm1_name'].isin(day1_cases.index)) & 
	    (adm2_cases['date'] == '2020-02-24') & 
	    (adm2_cases['adm2_name'] == 'Unknown')
	)

	# Set cum_confirmed_cases of "Unknown" adm2 rows to each corresponding adm1 total on day 1
	adm2_cases.loc[replace_day1_mask, 'cum_confirmed_cases'] = adm2_cases.loc[replace_day1_mask, 'adm1_name'].apply(lambda x: day1_cases.loc[x])

	# Check that all regions with positive cases on day 1 are accounted for
	adm2_cases[(adm2_cases['adm1_name'].isin(day1_cases.index)) & (adm2_cases['date'] == '2020-02-24') & (adm2_cases['adm2_name'] == 'Unknown')]

	return adm2_cases

adm2_cases = impute_day1_adm2_cases(adm1_cases, adm2_cases)

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

adm2_days_missing = [
    ("2020-03-17", "Rimini"),
    ("2020-03-18", "Parma")
]

# Replace missing values in `adm_cases` to null. These missing values are tabulated in the source data
# as the value of that variable on the previous non-missing day, which can skew analysis of growth rates
def fill_missing_as_null(adm_cases, date, adm_name, adm_col):
    
    # Get all cumulative columns
    cum_cols = [col for col in adm_cases.columns if 'cum_' in col]
    
    # Replace values known to be missing with np.nan
    for col in cum_cols:
        adm_cases.loc[(
            (adm_cases['date'] == date) & (adm_cases[adm_col] == adm_name)
        ), col] = np.nan
        
    return adm_cases

# Fill in nulls for missing adm1 data, in the adm1 dataset
for date, adm1 in adm1_days_missing:
    adm1_cases = fill_missing_as_null(adm1_cases, date, adm1, 'adm1_name')
        
# Fill in nulls for missing adm1 data, in the adm2 dataset
for date, adm1 in adm1_days_missing:
    adm2_cases = fill_missing_as_null(adm2_cases, date, adm1, 'adm1_name')

# Fill in nulls for missing adm2 data, in the adm2 dataset
for date, adm2 in adm2_days_missing:
    adm2_cases = fill_missing_as_null(adm2_cases, date, adm2, 'adm2_name')


adm2_cases[adm2_cases['cum_confirmed_cases'].isnull()].sample(5)


# ### Impute values in cases where cumulative counts rise and then fall
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
    array = np.array(array)
    
    # Hold onto original array to retrieve null values later
    array_orig = array.copy()
    
    # Convert array to re-impute nulls as filled by previous day
    array = np.array(pd.Series(array_orig).fillna(method='ffill'))
    
    # Replace cumulative totals that rise and then fall with nulls, assuming latest information is most correct
    array = convert_non_monotonic_to_nan(array)
    
    # Keep nulls from original array and nulls from checking for monotonicity
    array = np.where(np.isnan(array_orig), np.nan, array)
    
    # Interpolate all nulls
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
    if dst_col not in df.columns:
        df[dst_col] = -1

    for adm_name in df[groupby_col].unique():
        sub = df.loc[df[groupby_col] == adm_name].copy()
        sub[dst_col] = impute_cumulative_array(sub[src_col])
        
        # Set rising-then-falling cumulative counts to null in the original column
        sub.loc[sub[src_col].notnull(), src_col] = convert_non_monotonic_to_nan(
            np.array(sub.loc[sub[src_col].notnull(), src_col])
        )
        
        df.loc[df[groupby_col] == adm_name] = sub
        
    return df


def impute_each_cumulative_column(adm_cases, adm_id_col):
	# Impute any cumulative totals in adm1
	adm_cases_cum_cols = [col for col in adm_cases.columns if col.startswith(cumulative_prefix)]
	for src_col in adm_cases_cum_cols:
	    dst_col = src_col + imputed_suffix
	    adm_cases = impute_cumulative_df(adm_cases, src_col, dst_col, adm_id_col)

	return adm_cases

# #### Impute all cumulative totals in imputed column, fill as null where cumulative totals fall in source column
adm1_cases = impute_each_cumulative_column(adm1_cases, 'adm1_name')
adm2_cases = impute_each_cumulative_column(adm2_cases, 'adm2_id')

# #### Save processed health data to `interim` folder
path_italy_interim_province.parent.mkdir(parents=True, exist_ok=True)
adm2_cases.to_csv(path_italy_interim_province, index=False)
adm1_cases.to_csv(path_italy_interim_region, index=False)

# Filter out rows where adm1 is known but adm2 is unknown

# In[ ]:


adm2_cases = adm2_cases[adm2_cases['adm2_name'] != 'Unknown']


# ## Merge Health with Policies

# Clean data
policies_full['date_start'] = pd.to_datetime(policies_full['date_start'])
policies_full['date_end'] = pd.to_datetime(policies_full['date_end'])
policies_full['date_end'] = policies_full['date_end'].fillna(pd.to_datetime('2099-12-31'))
policies_full['policy'] = policies_full['policy'].str.strip()

# Convert 'optional' to indicator variable
policies_full['optional'] = policies_full['optional'].replace({"Y":1, "N":0})
policies_full['optional'] = policies_full['optional'].fillna(0)

# Set default values for null fields
policies_full['adm0_name'] = policies_full['adm0_name'].fillna('Italy')
policies_full['adm1_name'] = policies_full['adm1_name'].fillna('All')
policies_full['adm2_name'] = policies_full['adm2_name'].fillna('All')
policies_full['adm3_name'] = policies_full['adm3_name'].fillna('All')

# Map some regions/provinces in policy dataset to corresponding names in health data
replace_dict = {
    'Lombardy':'Lombardia',
    'Piedmont':'Piemonte',
    'Emilia-Romagna':'Emilia Romagna',
    'Padua':'Padova',
    'Venice':'Venezia',
    'Pesaro and Urbino':'Pesaro e Urbino',
    'Apulia':'Puglia', 
    "Vo'Eugane":'Vò',
}

# Standardize naming between policy and health data
policies_full['adm1_name'] = policies_full['adm1_name'].replace(replace_dict)
policies_full['adm2_name'] = policies_full['adm2_name'].replace(replace_dict)
policies_full['adm3_name'] = policies_full['adm3_name'].replace(replace_dict)

# Remove any duplicates, grouping on relevant columns
policies = policies_full[
    ['adm3_name','adm2_name','adm1_name','adm0_name',
     'date_start', 'date_end', 'policy','policy_intensity', 'optional']
].drop_duplicates()

# If this fails, have to implement `testing_regime` as categorical variable
# This works right now because only one change in "testing_regime", a categorical variable
assert policies.groupby('policy')['policy'].count()['testing_regime'] == 1

# Replace optional policies with `policy_name` to `policy_name_opt`
policies.loc[policies['optional'] == 1, 'policy'] = policies.loc[policies['optional'] == 1, 'policy'] + optional_suffix

# Ensure all policies listed have corresponding adm-units in health data
adm1_not_found = set(policies['adm1_name'].unique()) - set(adm1_cases['adm1_name'].unique()) - set(['All'])
adm2_not_found = set(policies['adm2_name'].unique()) - set(adm2_cases['adm2_name'].unique()) - set(['All'])
assert len(adm1_not_found) == 0
assert len(adm2_not_found) == 0

## Merge Policies and Cases with Population, calculate pop-weights

country_code = 'ITA'
max_adm_level = 3

# Assign "population" column to each DataFrame that has a corresponding `_processed.csv` file
adm1_cases = cpop.merge_cases_with_population_on_level(adm1_cases, 1, country_code)
adm2_cases = cpop.merge_cases_with_population_on_level(adm2_cases, 2, country_code)

policies = cpop.merge_policies_with_population(policies, country_code, max_adm_level)
policies = cpop.calculate_policy_popweights_each_row(policies, 2)
policies = cpop.aggregate_policy_popweights(policies, 1, country_code)
policies = cpop.aggregate_policy_popweights(policies, 2, country_code)
# End of population assignment

# Check that population weights are all there
assert len(policies[policies['adm1_pop_intensity_weight'].isnull()]) == 0
assert len(policies[policies['adm2_pop_intensity_weight'].isnull()]) == 0
assert len(policies[policies['adm3_pop'].isnull()]['adm3_name'].unique()) == 1
assert len(policies[policies['adm2_pop'].isnull()]['adm2_name'].unique()) == 1
assert len(policies[policies['adm1_pop'].isnull()]['adm1_name'].unique()) == 1
assert adm1_cases['population'].isnull().sum() == 0
assert adm2_cases['population'].isnull().sum() == 0

# Assign policy indicators
adm1_cases = cmerge.assign_adm_policy_variables(adm1_cases, policies, 1)
adm2_cases = cmerge.assign_adm_policy_variables(adm2_cases, policies, 2)

adm1_cases['no_gathering_size'] = 0
adm2_cases['no_gathering_size'] = 0

# Check nothing's missing in template
def check_against_template(*adm_cases_list):
	template = pd.read_csv(path_template)
	for adm_cases in adm_cases_list:
		missing_from_template = set(adm1_cases.columns) - set(template.columns)
		assert len(missing_from_template) == 0

check_against_template(adm1_cases, adm2_cases)

# Save to `ITA_processed.csv`'s
adm1_cases = adm1_cases.sort_values(['date', 'adm1_name'], ascending=True)
adm2_cases = adm2_cases.sort_values(['date', 'adm2_name'], ascending=True)

adm1_cases.to_csv(path_processed_region, index=False)
adm2_cases.to_csv(path_processed_province, index=False)
