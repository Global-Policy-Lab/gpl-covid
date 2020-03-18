library(tidyverse)
source("src/data/multi_country/get_JHU_country_data.R")
china_data <- get_jhu_data("China")
# no nesting of provinces looks like and no country total
# china_data$province_state %>%
#   unique

names_order <- read_csv("data/processed/[country]_processed.csv") %>% names()
china_data <- china_data %>% 
  rename(adm_name = province_state) %>% 
  mutate(adm_level = 1,
         adm0_name = "China") %>% 
  select(one_of(names_order))
  

write_csv(china_data, path = "data/interim/china/china_jhu_cases.csv")
