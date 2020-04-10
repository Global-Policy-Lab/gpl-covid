source("codes/models/FRA_generate_data_and_model_projection.R")

#projection
out <- compute_bootstrap_replications(full_data = france_data,
                                      policy_variables_to_use = france_policy_variables_to_use,
                                      lhs = "D_l_cum_confirmed_cases",
                                      other_control_variables = france_other_control_variables,
                                      times = times,
                                      gamma = gamma,
                                      proportion_confirmed = underreporting %>% 
                                        filter(country == "France") %>% 
                                        pull(underreporting_estimate))


write_csv(out, path = "data/post_processing/france_bootstrap_projection.csv")
write_csv(main_projection, path = "data/post_processing/france_model_projection.csv")