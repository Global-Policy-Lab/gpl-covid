library(tidyverse)
source("codes/data/multi_country/get_JHU_country_data.R")
italy_data <- get_jhu_data("Italy") %>% 
  select(-province_state)

names_order <- read_csv("data/processed/[country]_processed.csv", 
                        col_types = cols(.default = col_character())) %>% names()
italy_data_standardised <- italy_data %>% 
  mutate(adm0_name = "Italy") %>% 
  select(one_of(names_order))

write_csv(italy_data_standardised, path = "data/interim/italy/italy_jhu_cases.csv")
