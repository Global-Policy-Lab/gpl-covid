suppressPackageStartupMessages(library(tidyverse))
list.files("code/models", full.names = TRUE) %>% 
  str_subset("data_and_model_projection") %>% 
  walk(source)

loop_df <- crossing(
  tibble(country =   c("china", "iran", "korea", "italy", "france", "usa"),
         urcountry = c("China", "Iran", "South Korea", "Italy", "France", "United States of America"),
         full_data = list(china_data, iran_data, korea_data, italy_data, france_data, usa_data),
         policy_variables_to_use = list(china_policy_variables_to_use, iran_policy_variables_to_use, 
                                        korea_policy_variables_to_use, italy_policy_variables_to_use, 
                                        france_policy_variables_to_use, usa_policy_variables_to_use),
         other_control_variables = list(china_other_control_variables, iran_other_control_variables, 
                                        korea_other_control_variables, italy_other_control_variables, 
                                        france_other_control_variables, usa_other_control_variables),
         lhs = c("D_l_active_cases", "D_l_cum_confirmed_cases", "D_l_active_cases", 
                 "D_l_cum_confirmed_cases", "D_l_cum_confirmed_cases", "D_l_cum_confirmed_cases"),
         model = list(china_model, iran_model, korea_model, italy_model, france_model, usa_model)
  )
) %>% 
  left_join(underreporting, by = c("urcountry" = "country"))

loop_df <- loop_df %>% 
  mutate(projection = list(full_data, model, 
                           lhs, policy_variables_to_use, 
                           other_control_variables,
                           underreporting_estimate) %>% 
           pmap(~{
             out <- compute_predicted_cum_cases(full_data = ..1, model = ..2,
                                                lhs = ..3,
                                                policy_variables_used = ..4,
                                                other_control_variables = ..5,
                                                gamma = gamma,
                                                proportion_confirmed = ..6,
                                                return_no_policy_projection_output = TRUE)
             out
           }))

out <- loop_df %>% 
  select(country, 
         projection) %>% 
  unnest(projection)

write_csv(out, "models/projections/raw_projection_output.csv")