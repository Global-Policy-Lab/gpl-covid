#!/usr/bin/env python
# coding: utf-8

# ## Filter `USA_processed.csv` to end of analysis (3/18/2020)

# In[ ]:


from pathlib import Path
import os
import pandas as pd

end_of_analysis = pd.to_datetime('2020-03-18')


# Define paths

# In[ ]:


dir_gpl_covid = Path(os.getcwd()).parent.parent.parent

dir_processed = dir_gpl_covid / 'data' / 'processed'
dir_adm1 = dir_processed / 'adm1'

path_usa = dir_adm1 / 'USA_processed.csv'


# Filter to 3/18 and before

# In[ ]:


usa = pd.read_csv(path_usa)
usa.shape


# In[ ]:


usa = usa[pd.to_datetime(usa['date']) <= end_of_analysis]
usa.shape


# Output

# In[ ]:


usa.to_csv(path_usa, index=False)

