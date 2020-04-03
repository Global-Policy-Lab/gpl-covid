#ITA
# setwd("E:/GPL_covid/")
library(tidyverse)
library(lfe)
source("codes/models/predict_felm.R")
source("codes/models/projection_helper_functions.R")
underreporting <- read_rds("data/interim/multi_country/under_reporting.rds")

italy_data <- read_csv("models/reg_data/ITA_reg_data.csv",
                   col_types = cols(
                     .default = col_double(),
                     adm0_name = col_character(),
                     adm1_name = col_character(),
                     adm2_name = col_character(),
                     date = col_date(format = ""),
                     adm1_id = col_character(),
                     adm2_id = col_character(),
                     t = col_character()
                   )) %>% 
  arrange(adm1_name, adm2_name, date) %>%
  mutate(tmp_id = factor(adm2_id),
         day_of_week = factor(dow))

changed = TRUE
while(changed){
  new <- italy_data %>% 
    group_by(tmp_id) %>% 
    filter(!(is.na(cum_confirmed_cases) & date == min(date)))  
  if(nrow(new) == nrow(italy_data)){
    changed <- FALSE
  }
  italy_data <- new
}

italy_policy_variables_to_use <- 
  c(
    'p_1', 'p_2', 'p_3', 'p_4'
  )  

italy_other_control_variables <- 
  c(
    names(italy_data) %>% str_subset('testing_regime_'),
    'day_of_week'
  )

formula <- as.formula(
  paste("D_l_cum_confirmed_cases ~ tmp_id +", 
        paste(italy_policy_variables_to_use, collapse = " + "), ' + ',
        paste(italy_other_control_variables, collapse = " + "),
        " - 1 | 0 | 0 | date "
  ))

suppressWarnings({
  italy_model <- felm(data = italy_data,
                     formula = formula,
                     cmethod = 'reghdfe'); #summary(italy_model)
})
main_projection <- compute_predicted_cum_cases(full_data = italy_data, model = italy_model,
                                               lhs = "D_l_cum_confirmed_cases",
                                               policy_variables_used = italy_policy_variables_to_use,
                                               other_control_variables = italy_other_control_variables,
                                               gamma = gamma,
                                               proportion_confirmed = underreporting %>% 
                                                 filter(country == "Italy") %>% 
                                                 pull(underreporting_estimate))
