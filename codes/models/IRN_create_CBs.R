source("codes/models/IRN_generate_data_and_model_projection.R")
#projection
out <- compute_bootstrap_replications(full_data = mydata,
                                      policy_variables_to_use = policy_variables_to_use,
                                      lhs = "D_l_cum_confirmed_cases",
                                      other_control_variables = other_control_variables,
                                      times = times,
                                      gamma = gamma,
                                      proportion_confirmed = underreporting %>% 
                                        filter(country == "Iran") %>% 
                                        pull(underreporting_estimate))

write_csv(out, path = "data/post_processing/iran_bootstrap_projection.csv")
write_csv(main_projection, path = "data/post_processing/iran_model_projection.csv")