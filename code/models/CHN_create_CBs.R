source("code/models/CHN_generate_data_and_model_projection.R")
out <- compute_bootstrap_replications(full_data = china_data,
                                      policy_variables_to_use = china_policy_variables_to_use,
                                      lhs = "D_l_active_cases",
                                      other_control_variables = china_other_control_variables,
                                      times = times,
                                      time_steps_per_day = 6,
                                      gamma = gamma,
                                      proportion_confirmed = underreporting %>% 
                                        filter(country == "China") %>% 
                                        pull(underreporting_estimate))


if(times > 2){
  write_csv(out, path = "models/projections/china_bootstrap_projection.csv")
}
write_csv(main_projection, path = "models/projections/china_model_projection.csv")
