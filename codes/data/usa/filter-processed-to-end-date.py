#!/usr/bin/env python
# coding: utf-8

# ## Filter `USA_processed.csv` to end of analysis (3/18/2020)
import pandas as pd
import codes.utils as cutil

end_of_analysis = pd.to_datetime('2020-03-18')


# Define paths
dir_adm1 = cutil.DATA_PROCESSED / 'adm1'
path_usa = dir_adm1 / 'USA_processed.csv'


# Filter to 3/18 and before
usa = pd.read_csv(path_usa)
usa = usa[pd.to_datetime(usa['date']) <= end_of_analysis]
usa.to_csv(path_usa, index=False)

