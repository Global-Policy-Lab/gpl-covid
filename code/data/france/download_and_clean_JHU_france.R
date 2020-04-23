suppressPackageStartupMessages(library(tidyverse))
source("code/data/multi_country/get_JHU_country_data.R")
france_data <- get_jhu_data("France") %>% 
  filter(is.na(province_state))

names_order <- read_csv("data/processed/[country]_processed.csv", 
                        col_types = cols(.default = col_character())) %>% names()
suppressWarnings({
  france_data_standardised <- france_data %>% 
  mutate(adm0_name = "France") %>% 
  select(one_of(names_order))
})
write_csv(france_data_standardised, path = "data/interim/france/france_jhu_cases.csv")
