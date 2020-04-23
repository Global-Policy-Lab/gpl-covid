library(dplyr)
library(data.table)

# Loading JHU file
j = fread('data/interim/korea/korea_jhu_cases.csv')

# Loading the processef file
p = fread('data/processed/adm1/KOR_processed.csv')

# Merging
j = j %>% 
  rename(cum_confirmed_cases_JHU = cum_confirmed_cases) %>% 
  dplyr::select(date, cum_confirmed_cases_JHU)

p = p %>%
  dplyr::select(adm1_name, date, cum_confirmed_cases) %>% 
  ungroup() %>% group_by(date) %>% summarise(cum_confirmed_cases_data = sum(cum_confirmed_cases))

final = merge(p, j, by = 'date', all.x = T)

# Filtering out NAs
final = final[complete.cases(final), ]

# Save
fwrite(final, 'data/interim/korea/KOR_JHU_data_comparison.csv')
