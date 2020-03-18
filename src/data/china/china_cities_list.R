# Jeanette Tseng
# Created: 2020-03-17
# Description: pull list of all Chinese cities, 
# flag which have policies recorded, and sort by max # of cumulative cases

library(tidyverse)

chn_processed <- read_csv("data/processed/adm2/CHN_processed.csv")

chn_cities <- chn_processed %>% 
  mutate(any_policy = home_isolation + travel_ban_local,
         any_policy = as.numeric(any_policy>0)) %>% 
  group_by(adm1_name, adm2_name) %>% 
  summarise_at(vars(cumulative_confirmed_cases, any_policy), max, na.rm = TRUE) %>% 
  arrange(any_policy, desc(cumulative_confirmed_cases)) %>% 
  rename(max_cases = cumulative_confirmed_cases)

write.csv(chn_cities, "data/interim/china/china_cities_list.csv", row.names = FALSE)
