library(tidyverse)
source("codes/data/multi_country/get_JHU_country_data.R")
iran_data <- get_jhu_data("Iran") %>% 
  select(-province_state)

names_order <- read_csv("data/processed/[country]_processed.csv", 
                        col_types = cols(.default = col_character())) %>% names()
suppressWarnings({
  iran_data_standardised <- iran_data %>% 
  mutate(adm0_name = "Iran") %>% 
  select(one_of(names_order))
})
write_csv(iran_data_standardised, path = "data/interim/iran/iran_jhu_cases.csv")
