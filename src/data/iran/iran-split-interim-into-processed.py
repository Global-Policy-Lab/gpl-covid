#!/usr/bin/env python
# coding: utf-8

# In[81]:


import pandas as pd
from pathlib import Path
import os


# Define paths

# In[96]:


gpl_covid_path = Path(os.getcwd()).parent.parent.parent

dir_data_interim = gpl_covid_path / 'data' / 'interim' / 'iran'
dir_data_processed = gpl_covid_path / 'data' / 'processed'

# Input
path_iran_interim = dir_data_interim / 'IRN_interim.csv'

# Outputs
path_iran_processed_adm0 = dir_data_processed / 'adm0' / 'IRN_processed.csv'
path_iran_processed_adm2 = dir_data_processed / 'adm2' / 'IRN_processed.csv'


# In[97]:


interim = pd.read_csv(path_iran_interim)

interim = interim.drop(columns=['Unnamed: 0'])


# In[98]:


interim['date'] = pd.to_datetime(interim['date'])


# In[99]:


interim = interim.rename(columns={
    'adm0':'adm0_name',
    'adm1':'adm1_name',
    'adm2':'adm2_name',
})


# Drop rows where cumulative cases are very small (often noisy)

# In[100]:


# interim = interim[interim['cumulative_confirmed_cases'] >= 10]


# Split `interim` into two output datasets

# In[101]:


adm2_df = interim[interim['adm2_name'].notnull()].copy()
adm0_df = interim[interim['adm2_name'].isnull()].copy()


# Clean `adm0_df` (national level)

# In[102]:


adm2_df['adm1_name'] = adm2_df['adm1_name'].astype(int)

adm2_df = adm2_df.drop(columns=['new_deaths_national', 'cumulative_deaths'])


# In[103]:


adm2_df['adm2_name'].unique()


# In[106]:


adm2_df.loc[2, 'cumulative_confirmed_cases'] = 20


# In[108]:


sub = adm2_df[adm2_df['adm2_name'] == 'Qom']


# In[115]:


(sub['cumulative_confirmed_cases'].diff() >= 0) | (sub['cumulative_confirmed_cases'].diff().isnull())


# In[ ]:


sub['value2'] = np.round(
    sub['cumulative_confirmed_cases']


# Clean`adm2_df`

# In[75]:


# We only need `cumulative` columns
adm0_df = adm0_df.drop(columns=['new_confirmed_cases', 'new_deaths_national'])


# In[77]:


adm0_df['cumulative_deaths'] = adm0_df['cumulative_deaths'].astype(int)

