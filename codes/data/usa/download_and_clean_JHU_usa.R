suppressPackageStartupMessages(library(tidyverse))
suppressPackageStartupMessages(library(magrittr))
source("codes/data/multi_country/get_JHU_country_data.R")

usa_data <- get_jhu_data("US")

names_order <- read_csv("data/processed/[country]_processed.csv", 
                        col_types = cols(.default = col_character())) %>% names()

suppressWarnings({
  usa_data <- usa_data %>% 
    rename(adm1_name = province_state) %>% 
    mutate(adm0_name = "USA") %>% 
    mutate(cum_confirmed_cases_imputed = cum_confirmed_cases,
           cum_deaths_imputed = cum_deaths,
           cum_recoveries_imputed = cum_recoveries) %>% 
    select(one_of(names_order))
})

write_csv(usa_data, path = "data/interim/usa/usa_jhu_cases_national.csv")
