# setwd("E:/GPL_covid/")
library(tidyverse)
library(lfe)
source("codes/models/predict_felm.R")
source("codes/models/projection_helper_functions.R")
source("codes/data/multi_country/get_JHU_country_data.R")
underreporting <- read_rds("data/interim/multi_country/under_reporting.rds")

if(!(exists("gamma") & class(gamma) != "function")){
  gamma = 0.052
}
mydata <- read_csv('models/reg_data/CHN_reg_data.csv',                   
                   col_types = cols(
                     .default = col_double(),
                     adm0_name = col_character(),
                     adm1_name = col_character(),
                     adm2_name = col_character(),
                     date = col_date(format = ""),
                     t = col_character(),
                     adm2_id = col_character(),
                     adm1_id = col_character(),
                     adm1_adm2_name = col_character(),
                     day_avg = col_double()
                   )) %>% 
  arrange(adm1_name, adm2_name, date) %>%
  mutate(tmp_id = factor(adm1_adm2_name))

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
    names(mydata) %>% str_subset('home_isolation_'),
    names(mydata) %>% str_subset('travel_ban_local_')
  )  

other_control_variables <- 
  c(names(mydata) %>% str_subset("testing_regime_change_"))


formula <- as.formula(
  paste("D_l_active_cases ~ tmp_id +", 
        paste(policy_variables_to_use, collapse = " + "), ' + ',
        paste(other_control_variables, collapse = " + "),
        " - 1 | 0 | 0 | date "
  ))
suppressWarnings({
  main_model <- felm(data = mydata,
                     formula = formula,
                     cmethod = 'reghdfe'); #summary(main_model)
})
#projection

main_projection <- compute_predicted_cum_cases(full_data = mydata, model = main_model,
                                               lhs = "D_l_active_cases",
                                               policy_variables_used = policy_variables_to_use,
                                               other_control_variables = other_control_variables,
                                               time_steps_per_day = 6,
                                               gamma = gamma,
                                               proportion_confirmed = underreporting %>% 
                                                 filter(country == "China") %>% 
                                                 pull(underreporting_estimate))
