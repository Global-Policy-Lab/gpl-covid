# setwd("E:/GPL_covid/")
library(tidyverse)
library(lfe)
source("codes/models/predict_felm.R")
source("codes/models/projection_helper_functions.R")
underreporting <- read_rds("data/interim/multi_country/under_reporting.rds")

mydata <- read_csv("models/reg_data/USA_reg_data.csv",
                   col_types = cols(
                     .default = col_double(),
                     adm0_name = col_character(),
                     adm1_name = col_character(),
                     date = col_date(format = ""),
                     adm1_id = col_character(),
                     t = col_character()
                   )) %>% 
  arrange(adm1_name, date) %>%
  mutate(tmp_id = factor(adm1_id),
         day_of_week = factor(dow))

mydata <- mydata %>% 
  mutate_at(vars(matches("testing_regime")),
            ~if_else(is.na(.x), 0, .x))

changed = TRUE
while(changed){
  new <- mydata %>% 
    group_by(tmp_id) %>% 
    filter(!(is.na(cum_confirmed_cases) & date == min(date)))  
  if(nrow(new) == nrow(mydata)){
    changed <- FALSE
  }
  mydata <- new
}

policy_variables_to_use <- 
  c(
    names(mydata) %>% str_subset('^p_')
  )  

other_control_variables <-
  c(
    names(mydata) %>% str_subset('testing_regime_'),
    'day_of_week'
  )  

formula <- as.formula(
  paste("D_l_cum_confirmed_cases ~ tmp_id +", 
        paste(policy_variables_to_use, collapse = " + "), ' + ',
        paste(other_control_variables, collapse = " + "),
        " - 1 | 0 | 0 | date "
  ))

suppressWarnings({
  main_model <- felm(data = mydata,
                     formula = formula,
                     cmethod = 'reghdfe'); #summary(main_model)
})

main_projection <- compute_predicted_cum_cases(full_data = mydata, model = main_model,
                                               lhs = "D_l_cum_confirmed_cases",
                                               policy_variables_used = policy_variables_to_use,
                                               other_control_variables = other_control_variables,
                                               gamma = gamma,
                                               proportion_confirmed = underreporting %>% 
                                                 filter(country == "United States of America") %>% 
                                                 pull(underreporting_estimate))
