source("code/models/IRN_generate_data_and_model_projection.R")
#projection
out <- compute_bootstrap_replications(full_data = iran_data,
                                      policy_variables_to_use = iran_policy_variables_to_use,
                                      lhs = "D_l_cum_confirmed_cases",
                                      other_control_variables = iran_other_control_variables,
                                      times = times,
                                      gamma = gamma,
                                      proportion_confirmed = underreporting %>% 
                                        filter(country == "Iran") %>% 
                                        pull(underreporting_estimate))

if(times > 2){
  write_csv(out, path = "models/projections/iran_bootstrap_projection.csv")
}
write_csv(main_projection, path = "models/projections/iran_model_projection.csv")
