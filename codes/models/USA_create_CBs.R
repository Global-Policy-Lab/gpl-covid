source("codes/models/USA_generate_data_and_model_projection.R")
#projection
out <- compute_bootstrap_replications(full_data = usa_data,
                                      policy_variables_to_use = usa_policy_variables_to_use,
                                      lhs = "D_l_cum_confirmed_cases",
                                      other_control_variables = usa_other_control_variables,
                                      times = times,
                                      gamma = gamma,
                                      proportion_confirmed = underreporting %>% 
                                        filter(country == "United States of America") %>% 
                                        pull(underreporting_estimate))

write_csv(out, path = "data/post_processing/usa_bootstrap_projection.csv")
write_csv(main_projection, path = "data/post_processing/usa_model_projection.csv")