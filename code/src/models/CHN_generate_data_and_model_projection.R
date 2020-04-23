# setwd("E:/GPL_covid/")
suppressPackageStartupMessages(library(tidyverse))
suppressPackageStartupMessages(library(lfe))
source("code/src/models/predict_felm.R")
source("code/src/models/projection_helper_functions.R")
source("code/data/multi_country/get_JHU_country_data.R")
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

if(!(exists("gamma") & class(gamma) != "function")){
  gamma = 0.052
}
china_data <- read_csv('models/reg_data/CHN_reg_data.csv',                   
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
  new <- china_data %>% 
    group_by(tmp_id) %>% 
    filter(!(is.na(cum_confirmed_cases) & date == min(date)))  
  if(nrow(new) == nrow(china_data)){
    changed <- FALSE
  }
  china_data <- new
}

china_policy_variables_to_use <- 
  c(
    names(china_data) %>% str_subset('home_isolation_'),
    names(china_data) %>% str_subset('travel_ban_local_')
  )  

china_other_control_variables <- 
  c(names(china_data) %>% str_subset("testing_regime_change_"))


formula <- as.formula(
  paste("D_l_active_cases ~ tmp_id +", 
        paste(china_policy_variables_to_use, collapse = " + "), ' + ',
        paste(china_other_control_variables, collapse = " + "),
        " - 1 | 0 | 0 | date "
  ))
suppressWarnings({
  china_model <- felm(data = china_data,
                     formula = formula,
                     cmethod = 'reghdfe'); #summary(china_model)
})
#projection

main_projection <- compute_predicted_cum_cases(full_data = china_data, model = china_model,
                                               lhs = "D_l_active_cases",
                                               policy_variables_used = china_policy_variables_to_use,
                                               other_control_variables = china_other_control_variables,
                                               time_steps_per_day = 6,
                                               gamma = gamma,
                                               proportion_confirmed = underreporting %>% 
                                                 filter(country == "China") %>% 
                                                 pull(underreporting_estimate))
