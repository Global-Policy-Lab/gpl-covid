#KOR
# setwd("E:/GPL_covid/")
library(tidyverse)
library(lfe)
source("codes/models/predict_felm.R")
source("codes/models/projection_helper_functions.R")
underreporting <- read_rds("data/interim/multi_country/under_reporting.rds")

korea_data <- read_csv("models/reg_data/KOR_reg_data.csv",
                   col_types = cols(
                     .default = col_double(),
                     adm0_name = col_character(),
                     adm1_name = col_character(),
                     date = col_date(format = ""),
                     adm1_id = col_character(),
                     t = col_character(),
                     travel_ban_intl_in_opt_country_l = col_character(),
                     travel_ban_intl_out_opt_country_ = col_character()
                   )) %>% 
  arrange(adm1_name, date) %>%
  mutate(tmp_id = factor(adm1_id),
         day_of_week = factor(dow))

changed = TRUE
while(changed){
  new <- korea_data %>% 
    group_by(tmp_id) %>% 
    filter(!(is.na(cum_confirmed_cases) & date == min(date)))  
  if(nrow(new) == nrow(korea_data)){
    changed <- FALSE
  }
  korea_data <- new
}

korea_policy_variables_to_use <- 
  c(
    names(korea_data) %>% str_subset('^p_[0-4]$')
  )  

korea_other_control_variables <- 
  c(names(korea_data) %>% str_subset("testing_regime_change_"),
    'day_of_week')

formula <- as.formula(
  paste("D_l_active_cases ~ tmp_id +", 
        paste(korea_policy_variables_to_use, collapse = " + "), ' + ',
        paste(korea_other_control_variables, collapse = " + "),
        " - 1 | 0 | 0 | date "
  ))

suppressWarnings({
  korea_model <- felm(data = korea_data,
                     formula = formula,
                     cmethod = 'reghdfe'); #summary(korea_model)
})
main_projection <- compute_predicted_cum_cases(full_data = korea_data, model = korea_model,
                                               lhs = "D_l_active_cases",
                                               policy_variables_used = korea_policy_variables_to_use,
                                               other_control_variables = korea_other_control_variables,
                                               gamma = gamma,
                                               proportion_confirmed = underreporting %>% 
                                                 filter(country == "South Korea") %>% 
                                                 pull(underreporting_estimate))
