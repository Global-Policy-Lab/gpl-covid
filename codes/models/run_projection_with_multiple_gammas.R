library(tidyverse)
library(patchwork)
list.files("codes/models", full.names = TRUE) %>% 
  str_subset("data_and_model_projection") %>% 
  walk(source)

gamma_loop_df <- crossing(
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
       ),
  gamma = c(0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4) 
    )%>% 
  left_join(underreporting, by = c("urcountry" = "country")) 
pb <- dplyr::progress_estimated(nrow(gamma_loop_df))
gamma_loop_df <- gamma_loop_df %>% 
  mutate(projection = list(full_data, model, 
                           lhs, policy_variables_to_use, 
                           other_control_variables,
                           underreporting_estimate,
                           gamma) %>% 
           pmap(~{
             out <- compute_predicted_cum_cases(full_data = ..1, model = ..2,
                                                lhs = ..3,
                                                policy_variables_used = ..4,
                                                other_control_variables = ..5,
                                                time_steps_per_day = 6,
                                                gamma = ..7,
                                                proportion_confirmed = ..6)
             pb$tick()$print()
             out
           }))

final_df <- gamma_loop_df %>% 
  select(country, gamma, projection) %>% 
  unnest(projection) %>% 
  group_by(country, gamma) %>% 
  filter(date == max(date)) %>% 
  group_by(gamma) %>% 
  summarise(predicted_cum_confirmed_cases_true = sum(predicted_cum_confirmed_cases_true),
            predicted_cum_confirmed_cases_no_policy = sum(predicted_cum_confirmed_cases_no_policy)) %>% 
  mutate(cases_saved = predicted_cum_confirmed_cases_no_policy - predicted_cum_confirmed_cases_true) 
out_scale_down_to_zero <- final_df %>% 
  ggplot() + 
  aes(x = gamma, y = cases_saved) + 
  scale_y_log10("Confirmed cases delayed",
                breaks = scales::trans_breaks("log10", function(x) 10^x),
                labels = scales::trans_format("log10", scales::math_format(10^.x)),
                limits = c(1, max(final_df$cases_saved)*1.1)) +
  geom_point() + 
  theme_classic() + 
  theme(axis.text = element_text(color = "black")) + 
  xlab(expression(gamma)) + 
  ggtitle("Cases delayed (log scale down to 0)")

out_scale_trimmed <- final_df %>% 
  ggplot() + 
  aes(x = gamma, y = cases_saved) + 
  scale_y_continuous("Confirmed cases delayed", labels = scales::comma) +
  geom_point() + 
  theme_classic() + 
  theme(axis.text = element_text(color = "black")) + 
  xlab(expression(gamma)) + 
  ggtitle("Cases delayed (linear scale trimmed)")

out_scale_trimmed_true <- final_df %>% 
  ggplot() + 
  aes(x = gamma, y = predicted_cum_confirmed_cases_true) + 
  scale_y_continuous("Estimate with-policy confirmed cases", labels = scales::comma) +
  geom_point() + 
  theme_classic() + 
  theme(axis.text = element_text(color = "black")) + 
  xlab(expression(gamma)) + 
  ggtitle("Estimated with-policy cases")

out_scale_trimmed_no_policy <- final_df %>% 
  ggplot() + 
  aes(x = gamma, y = predicted_cum_confirmed_cases_no_policy) + 
  scale_y_continuous("Estimate no-policy confirmed cases", labels = scales::comma) +
  geom_point() + 
  theme_classic() + 
  theme(axis.text = element_text(color = "black")) + 
  xlab(expression(gamma)) + 
  ggtitle("Estimated no-policy cases")

final <- (out_scale_down_to_zero | out_scale_trimmed) / 
 (out_scale_trimmed_true | out_scale_trimmed_no_policy)  

cowplot::save_plot(plot = final, filename = "results/figures/fig4/fig4_total_sensitivity_to_gamma.pdf",
                   scale = 2, base_asp = 1.2)
