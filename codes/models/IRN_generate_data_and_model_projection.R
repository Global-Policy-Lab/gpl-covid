# setwd("E:/GPL_covid/")
library(tidyverse)
library(lfe)
source("codes/models/predict_felm.R")
source("codes/models/projection_helper_functions.R")
underreporting <- read_rds("data/interim/multi_country/under_reporting.rds")

iran_data <- read_csv("models/reg_data/IRN_reg_data.csv",
                   col_types = cols(
                     .default = col_double(),
                     adm0_name = col_character(),
                     adm1_name = col_character(),
                     date = col_date(format = ""),
                     adm1_id = col_character(),
                     t = col_character()
                   )) %>% 
  arrange(adm1_name, date) %>%
  mutate(adm1_id = factor(adm1_id),
         day_of_week = factor(dow),
         tmp_id = factor(adm1_id))

iran_data <- iran_data %>% 
  mutate_at(vars(matches("testing_regime")),
            ~if_else(is.na(.x), 0, .x))

changed = TRUE
while(changed){
  new <- iran_data %>% 
    group_by(tmp_id) %>% 
    filter(!(is.na(cum_confirmed_cases) & date == min(date)))  
  if(nrow(new) == nrow(iran_data)){
    changed <- FALSE
  }
  iran_data <- new
}

iran_policy_variables_to_use <- 
  c(
    names(iran_data) %>% str_subset('p_1'),
    names(iran_data) %>% str_subset('p_2')
  )  

iran_other_control_variables <- 
  c(names(iran_data) %>% str_subset("testing_regime_"),
    'day_of_week')

formula <- as.formula(
  paste("D_l_cum_confirmed_cases ~ tmp_id +", 
        paste(iran_policy_variables_to_use, collapse = " + "), ' + ',
        paste(iran_other_control_variables, collapse = " + "),
        " - 1 | 0 | 0 | date "
  ))

suppressWarnings({
  iran_model <- felm(data = iran_data,
                     formula = formula,
                     cmethod = 'reghdfe'); #summary(iran_model)
})
# debug(compute_predicted_cum_cases)
main_projection <- compute_predicted_cum_cases(full_data = iran_data, model = iran_model,
                                               lhs = "D_l_cum_confirmed_cases",
                                               policy_variables_used = iran_policy_variables_to_use,
                                               other_control_variables = iran_other_control_variables,
                                               gamma = gamma,
                                               proportion_confirmed = underreporting %>% 
                                                 filter(country == "Iran") %>% 
                                                 pull(underreporting_estimate))
