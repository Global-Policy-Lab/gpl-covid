# setwd("E:/GPL_covid/")
library(tidyverse)
library(lfe)
source("codes/models/predict_felm.R")
source("codes/models/projection_helper_functions.R")
underreporting <- read_rds("data/interim/multi_country/under_reporting.rds")

mydata <- read_csv("models/reg_data/FRA_reg_data.csv",
                   col_types = cols(
                     .default = col_double(),
                     adm0_name = col_character(),
                     adm1_name = col_character(),
                     date = col_date(format = "")
                   )) %>% 
  arrange(adm1_name, date) %>%
  mutate(tmp_id = factor(adm1_name),
         day_of_week = factor(dow))
if(exists("gamma")){
  if(class(gamma) == "function"){
    gamma <- 0.052
  }
}
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
    "testing_regime",
    'pck_social_distance',
    'school_closure',
    'national_lockdown'
  )  

other_control_variables <- 'day_of_week'

# reghdfe D_l_cum_confirmed_cases testing national_lockdown school_closure ///
#   social_distance pck_no_gathering , absorb(i.adm1_id i.dow, savefe) cluster(t) resid 

formula <- as.formula(
  paste("D_l_cum_confirmed_cases ~ tmp_id +", 
        paste(policy_variables_to_use, collapse = " + "), ' + ',
        paste(other_control_variables, collapse = " + "),
        " - 1 | 0 | 0 | date "
  ))


main_model <- suppressWarnings({
  felm(data = mydata,
       formula = formula,
       cmethod = 'reghdfe'); #summary(main_model)
})

main_projection <- compute_predicted_cum_cases(full_data = mydata, model = main_model,
                                               lhs = "D_l_cum_confirmed_cases",
                                               policy_variables_used = policy_variables_to_use,
                                               other_control_variables = other_control_variables,
                                               gamma = gamma,
                                               proportion_confirmed = underreporting %>% 
                                                 filter(country == "France") %>% 
                                                 pull(underreporting_estimate))
