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
                                                return_raw_projection_output = TRUE)
             out
           }),
         projection_extended = list(full_data, model, 
                           lhs, policy_variables_to_use, 
                           other_control_variables,
                           underreporting_estimate) %>% 
           pmap(~{
             dta <- ..1
             policy_vars <- ..4
             tr_vars <- ..5 %>% str_subset("testing_regime")
             dow_vars <- ..5 %>% str_subset("day_of_week")
             fill_nas_vars <- c(..3, "cum_confirmed_cases")
             dta_new <- list(.vars = lst(fill_nas_vars, "date", policy_vars, tr_vars, dow_vars),
                  .funs = lst(~{
                    list(c(.x, rep(NA_real_,
                                   as.double(lubridate::today(tzone = "US/Pacific") - 
                                               date[length(date)]))))
                  },
                  ~{
                    list(seq.Date(date[1], lubridate::today(tzone = "US/Pacific"), by = "days"))
                  },
                  ~{
                    list(c(.x, rep(.x[length(.x)],
                                   as.double(lubridate::today(tzone = "US/Pacific") - 
                                               date[length(date)]))))
                  }, 
                  ~{
                    list(c(.x, rep(0,
                                   as.double(lubridate::today(tzone = "US/Pacific") - 
                                               date[length(date)]))))
                  },
                  ~{
                    to_keep <- as.double(lubridate::today(tzone = "US/Pacific") - 
                                           date[length(date)])
                    full_cycle <- factor(levels(.x), levels(.x))
                    # index to start filling from
                    start_index <- which(full_cycle == .x[length(.x)]) + 1
                    to_repeat <- forcats::fct_c(full_cycle[start_index:length(full_cycle)],
                                                full_cycle[seq_len(start_index - 1)])
                    list(forcats::fct_c(.x, rep(to_repeat,
                                                times = ceiling(as.double(
                                                  lubridate::today(tzone = "US/Pacific") - 
                                                    date[length(date)])/7))[1:to_keep]))
                  })) %>% 
               pmap(~ dta %>% group_by(tmp_id) %>% summarise_at(.x, .y)) %>% 
               reduce(inner_join, by = "tmp_id")
             ids <- dta %>% 
               select(tmp_id, matches("^adm[0-3]_name$"), population) %>% 
               ungroup() %>% 
               distinct()
             final_df <- dta_new %>% 
               unnest(c(date, all_of(fill_nas_vars), all_of(policy_vars), all_of(tr_vars), all_of(dow_vars))) %>% 
               left_join(ids, by = "tmp_id")
             out <- compute_predicted_cum_cases(full_data = final_df, model = ..2,
                                                lhs = ..3,
                                                policy_variables_used = ..4,
                                                other_control_variables = ..5,
                                                gamma = gamma,
                                                proportion_confirmed = ..6,
                                                return_raw_projection_output = TRUE)
             out
           }))

out_sample <- loop_df %>% 
  select(country, 
         projection) %>% 
  unnest(projection)

out_extended <- loop_df %>% 
  select(country, 
         projection_extended) %>% 
  unnest(projection_extended)

write_csv(out_sample, "models/projections/raw/raw_projection_output.csv")
write_csv(out_extended, "models/projections/raw/raw_projection_output_extended.csv")

write_csv(out_sample %>% 
            filter(timestep == max(timestep)) %>% 
            select(-timestep), "models/projections/raw/projection_output_daily.csv")
write_csv(out_extended %>% 
            filter(timestep == max(timestep)) %>% 
            select(-timestep), "models/projections/raw/projection_output_extended_daily.csv") 
