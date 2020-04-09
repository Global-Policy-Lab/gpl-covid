source("codes/models/CHN_generate_data_and_model_projection.R")
out <- compute_bootstrap_replications(full_data = mydata,
                                      policy_variables_to_use = policy_variables_to_use,
                                      lhs = "D_l_active_cases",
                                      other_control_variables = other_control_variables,
                                      times = times,
                                      time_steps_per_day = 6,
                                      gamma = gamma,
                                      proportion_confirmed = underreporting %>% 
                                        filter(country == "China") %>% 
                                        pull(underreporting_estimate))


write_csv(out, path = "data/post_processing/china_bootstrap_projection.csv")
write_csv(main_projection, path = "data/post_processing/china_model_projection.csv")