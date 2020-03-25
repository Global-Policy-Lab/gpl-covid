#!/usr/bin/env python
# coding: utf-8

# ### Process `KOR_interim.csv` -> `KOR_processed.csv`, renaming columns and filtering to length of analysis
import pandas as pd
from codes import utils as cutil

end_of_analysis_date = "2020-03-18"


# Define paths
template = pd.read_csv(cutil.DATA_PROCESSED / '[country]_processed.csv')
path_kor_interim = cutil.DATA_INTERIM / 'korea' / 'KOR_interim.csv'
path_kor_processed = cutil.DATA_PROCESSED / 'adm1' / 'KOR_processed.csv'


# Read interim file
kor = pd.read_csv(path_kor_interim)


# Drop deprecated column
kor = kor.drop(columns='travel_advisory_outbound_optional')
replace_columns = {
    'shutdown_religious_places':'religious_closure',
    'business_closure_optional':'business_closure_opt',
    'cumulative_confirmed_cases':'cum_confirmed_cases',
    'cumulative_deaths':'cum_deaths',
    'cumulative_recoveries':'cum_recoveries',
    'social_distance_optional':'social_distance_opt',
    'work_from_home_optional':'work_from_home_opt',
}

kor = kor.rename(columns=replace_columns)

# Check that all columns are in template
assert len(set(kor.columns) - set(template.columns)) == 0


# Filter to 3/18 and before
kor = kor[pd.to_datetime(kor['date']) <= pd.to_datetime(end_of_analysis_date)]


# Output
kor.to_csv(path_kor_processed, index=False)

