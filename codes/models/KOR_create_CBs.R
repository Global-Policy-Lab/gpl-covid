source("codes/models/KOR_generate_data_and_model_projection.R")
#projection
out <- compute_bootstrap_replications(full_data = korea_data,
                                      policy_variables_to_use = korea_policy_variables_to_use,
                                      lhs = "D_l_active_cases",
                                      other_control_variables = korea_other_control_variables,
                                      times = times,
                                      gamma = gamma,
                                      proportion_confirmed = underreporting %>% 
                                        filter(country == "South Korea") %>% 
                                        pull(underreporting_estimate))


write_csv(out, path = "models/projections/korea_bootstrap_projection.csv")
write_csv(main_projection, path = "models/projections/korea_model_projection.csv")