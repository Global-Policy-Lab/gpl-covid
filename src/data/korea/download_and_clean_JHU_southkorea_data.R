library(tidyverse)
source("src/data/multi_country/get_JHU_country_data.R")
south_korea_data <- get_jhu_data("Korea, South") %>% 
  select(-province_state)

names_order <- read_csv("data/processed/[country]_processed.csv", 
                        col_types = cols(.default = col_character())) %>% names()
south_korea_data_standardised <- south_korea_data %>% 
  mutate(adm_name = "South Korea") %>% 
  mutate(adm_level = 0,
         adm0_name = "South Korea") %>% 
  select(one_of(names_order))

write_csv(south_korea_data_standardised, path = "data/interim/korea/korea_jhu_cases.csv")
