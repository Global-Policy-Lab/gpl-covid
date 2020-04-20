# setwd("E:/GPL_covid/")
suppressPackageStartupMessages(library(tidyverse))
suppressPackageStartupMessages(library(lfe))
source("codes/models/predict_felm.R")
source("codes/models/projection_helper_functions.R")
underreporting <- read_csv("data/interim/multi_country/under_reporting.csv",
                           col_types = cols(
                             country = col_character(),
                             total_cases = col_double(),
                             total_deaths = col_double(),
                             underreporting_estimate = col_double(),
                             lower = col_double(),
                             upper = col_double(),
                             underreporting_estimate_clean = col_character()
                           ))

usa_data <- read_csv("models/reg_data/USA_reg_data.csv",
                   col_types = cols(
                     .default = col_double(),
                     adm0_name = col_character(),
                     adm1_name = col_character(),
                     date = col_date(format = ""),
                     adm1_id = col_character(),
                     adm1_abb = col_character(),
                     t = col_character()
                   )) %>% 
  arrange(adm1_name, date) %>%
  mutate(tmp_id = factor(adm1_id),
         day_of_week = factor(dow))

usa_data <- usa_data %>% 
  mutate_at(vars(matches("testing_regime")),
            ~if_else(is.na(.x), 0, .x))

changed = TRUE
while(changed){
  new <- usa_data %>% 
    group_by(tmp_id) %>% 
    filter(!(is.na(cum_confirmed_cases) & date == min(date)))  
  if(nrow(new) == nrow(usa_data)){
    changed <- FALSE
  }
  usa_data <- new
}

usa_policy_variables_to_use <- 
  c(
    names(usa_data) %>% str_subset('^p_')
  )  

usa_other_control_variables <-
  c(
    names(usa_data) %>% str_subset('testing_regime_'),
    'day_of_week'
  )  

formula <- as.formula(
  paste("D_l_cum_confirmed_cases ~ tmp_id +", 
        paste(usa_policy_variables_to_use, collapse = " + "), ' + ',
        paste(usa_other_control_variables, collapse = " + "),
        " - 1 | 0 | 0 | date "
  ))

suppressWarnings({
  usa_model <- felm(data = usa_data,
                     formula = formula,
                     cmethod = 'reghdfe'); #summary(usa_model)
})

main_projection <- compute_predicted_cum_cases(full_data = usa_data, model = usa_model,
                                               lhs = "D_l_cum_confirmed_cases",
                                               policy_variables_used = usa_policy_variables_to_use,
                                               other_control_variables = usa_other_control_variables,
                                               gamma = gamma,
                                               proportion_confirmed = underreporting %>% 
                                                 filter(country == "United States of America") %>% 
                                                 pull(underreporting_estimate))
