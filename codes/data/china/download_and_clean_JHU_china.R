suppressPackageStartupMessages(library(tidyverse))
source("codes/data/multi_country/get_JHU_country_data.R")
china_data <- get_jhu_data("China")
# no nesting of provinces looks like and no country total
# china_data$province_state %>%
#   unique

names_order <- read_csv("data/processed/[country]_processed.csv", 
                        col_types = cols(.default = col_character())) %>% names()
suppressWarnings({
  china_data <- china_data %>% 
    mutate(adm0_name = "China",
           adm1_name = province_state) %>% 
    select(one_of(names_order))
})
  
write_csv(china_data, path = "data/interim/china/china_jhu_cases.csv")