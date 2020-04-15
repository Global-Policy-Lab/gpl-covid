suppressPackageStartupMessages(library(tidyverse))
suppressPackageStartupMessages(library(ggsci))
suppressPackageStartupMessages(library(patchwork))
list.files("codes/models", full.names = TRUE) %>% 
  str_subset("data_and_model_projection") %>% 
  walk(source)

gamma_estimates <- read_csv("models/gamma_est.csv",
                            col_types = cols(
                              adm0_name = col_character(),
                              recovery_delay = col_double(),
                              gamma = col_double()
                            ))
gamma_estimates <- gamma_estimates %>% 
  filter(adm0_name %in% c("CHN", "KOR")) %>% 
  group_by(recovery_delay) %>% 
  summarise(gamma = mean(gamma))

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
  gamma = c(0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4),
  sigma = c(0.2, 0.33, 0.5, Inf),
  time_steps_per_day = c(6)
) %>% 
  left_join(underreporting, by = c("urcountry" = "country"))
pb <- dplyr::progress_estimated(nrow(gamma_loop_df))
gamma_loop_df <- gamma_loop_df %>% 
  mutate(projection = list(full_data, model, 
                           lhs, policy_variables_to_use, 
                           other_control_variables,
                           underreporting_estimate,
                           gamma,
                           sigma,
                           time_steps_per_day) %>% 
           pmap(~{
             out <- compute_predicted_cum_cases(full_data = ..1, model = ..2,
                                                lhs = ..3,
                                                policy_variables_used = ..4,
                                                other_control_variables = ..5,
                                                time_steps_per_day = ..9,
                                                gamma = ..7,
                                                sigma = ..8,
                                                proportion_confirmed = ..6)
             pb$tick()$print()
             out
           }))

final_df <- gamma_loop_df %>% 
  select(country, gamma, sigma, time_steps_per_day, projection) %>% 
  unnest(projection) %>% 
  group_by(country, gamma, sigma, time_steps_per_day) %>% 
  filter(date == max(date)) %>% 
  group_by(gamma, sigma, time_steps_per_day) %>% 
  summarise(predicted_cum_confirmed_cases_true = sum(predicted_cum_confirmed_cases_true),
            predicted_cum_confirmed_cases_no_policy = sum(predicted_cum_confirmed_cases_no_policy)) %>% 
  mutate(cases_saved = predicted_cum_confirmed_cases_no_policy - predicted_cum_confirmed_cases_true) %>% 
  arrange(time_steps_per_day, gamma, sigma) %>%
  ungroup() %>% 
  mutate(sigma = as.character(sigma))



out_scale_down_to_zero <- final_df %>%
  ggplot() + 
  aes(x = gamma, y = cases_saved, color = factor(sigma), shape = factor(sigma)) + 
  geom_point() + 
  theme_classic() + 
  theme(axis.text = element_text(color = "black")) + 
  xlab(expression(gamma)) + 
  ggtitle("Cases delayed (log scale)") + 
  labs(color = expression(sigma), shape = expression(sigma))

xpos_1_1 <- (gamma_estimates %>% 
           filter(recovery_delay == 0) %>% 
           pull(gamma))
xpos_1_2 <- (gamma_estimates %>% 
            filter(recovery_delay == 14) %>% 
            pull(gamma))
ypos_1_1 = 1
ypos_1_2 = 50
ypos_1_3 = 9
xshift_1_1 = 0.02
xshift_1_2 = 0.04
out_scale_down_to_zero <- out_scale_down_to_zero + 
  geom_curve(
    aes(xend = xpos_1_1, 
        yend = ypos_1_1, 
        x = xpos_1_1 + xshift_1_1,
        y = ypos_1_2),
    arrow = arrow(length = unit(0.03, "npc")),
    curvature = 0.3,
    color = "black"
  ) + 
  geom_curve(
    aes(xend = xpos_1_2, 
        yend = ypos_1_1, 
        x = xpos_1_2 + xshift_1_2,
        y = ypos_1_3),
    arrow = arrow(length = unit(0.03, "npc")),
    curvature = 0.3,
    color = "black"
  ) + 
  scale_y_log10("Confirmed cases delayed",
                breaks = scales::trans_breaks("log10", function(x) 10^x),
                labels = scales::trans_format("log10", scales::math_format(10^.x)),
                limits = c(1, max(final_df$cases_saved)*1.5), 
                expand = c(0, 0)) +
  annotate(geom = "text", x = xpos_1_1 + xshift_1_1, y = ypos_1_2,
           label = expression("Simulation "*gamma),
           hjust = 0) + 
  annotate(geom = "text", x = xpos_1_2 + xshift_1_2, y = ypos_1_3,
           label = expression("Est. "*gamma*" assuming"),
           hjust = 0, vjust = -0.6) + 
  annotate(geom = "text", x = xpos_1_2 + xshift_1_2, y = ypos_1_3,
           label = expression("14-day delay in"),
           hjust = 0, vjust = 0.5) + 
  annotate(geom = "text", x = xpos_1_2 + xshift_1_2, y = ypos_1_3,
           label = expression("recording recovery."),
           hjust = 0, vjust = 1.6)

out_scale_trimmed <- final_df %>% 
  ggplot() + 
  aes(x = gamma, y = cases_saved, color = factor(sigma), shape = factor(sigma)) + 
  geom_point() + 
  theme_classic() + 
  theme(axis.text = element_text(color = "black")) + 
  xlab(expression(gamma)) + 
  ggtitle("Cases delayed (linear scale trimmed)") 

yr_2 <- ggplot_build(out_scale_trimmed)$layout$panel_params[[1]]$y.range
xpos_2_1 <- xpos_1_1
xpos_2_2 <- xpos_1_2
ypos_2_1 = yr_2[1]
ypos_2_2 = yr_2[1] + 0.3*(diff(yr_2))
ypos_2_3 = yr_2[1] + 0.13*(diff(yr_2))
xshift_2_1 = xshift_1_1
xshift_2_2 = 0.03
out_scale_trimmed <- out_scale_trimmed + 
  # geom_curve(
  #   aes(xend = xpos_2_1, 
  #       yend = ypos_2_1, 
  #       x = xpos_2_1 + xshift_2_1,
  #       y = ypos_2_2),
  #   arrow = arrow(length = unit(0.03, "npc")),
  #   curvature = 0.3
  # ) + 
  # geom_curve(
  #   aes(xend = xpos_2_2, 
  #       yend = ypos_2_1, 
  #       x = xpos_2_2 + xshift_2_2,
  #       y = ypos_2_3),
  #   arrow = arrow(length = unit(0.03, "npc")),
  #   curvature = 0.3
  # ) + 
  scale_y_continuous("Confirmed cases delayed", labels = scales::comma, 
                     limits = yr_2, expand = c(0, 0)) #+
  # annotate(geom = "text", x = xpos_2_1 + xshift_2_1, y = ypos_2_2,
  #          label = expression("Simulation "*gamma),
  #          hjust = 0) + 
  # annotate(geom = "text", x = xpos_2_2 + xshift_2_2, y = ypos_2_3,
  #          label = expression("Est. "*gamma*" assuming"),
  #          hjust = 0, vjust = -0.6) + 
  # annotate(geom = "text", x = xpos_2_2 + xshift_2_2, y = ypos_2_3,
  #          label = expression("14-day delay in"),
  #          hjust = 0, vjust = 0.5) + 
  # annotate(geom = "text", x = xpos_2_2 + xshift_2_2, y = ypos_2_3,
  #          label = expression("recording recovery."),
  #          hjust = 0, vjust = 1.6)

out_scale_trimmed_true <- final_df %>% 
  ggplot() + 
  aes(x = gamma, y = predicted_cum_confirmed_cases_true, color = factor(sigma), shape = factor(sigma)) + 
  geom_point() + 
  theme_classic() + 
  theme(axis.text = element_text(color = "black")) + 
  xlab(expression(gamma)) + 
  ggtitle("Estimated with-policy cases")


yr_3 <- ggplot_build(out_scale_trimmed_true)$layout$panel_params[[1]]$y.range
xpos_3_1 <- xpos_1_1
xpos_3_2 <- xpos_1_2
ypos_3_1 = yr_3[1]
ypos_3_2 = yr_3[1] + 0.15*(diff(yr_3))
ypos_3_3 = yr_3[1] + 0.1*(diff(yr_3))
xshift_3_1 = 0.03
xshift_3_2 = 0.06
out_scale_trimmed_true <- out_scale_trimmed_true + 
  # geom_curve(
  #   aes(xend = xpos_3_1, 
  #       yend = ypos_3_1, 
  #       x = xpos_3_1 + xshift_3_1,
  #       y = ypos_3_2),
  #   arrow = arrow(length = unit(0.03, "npc")),
  #   curvature = 0.3
  # ) + 
  # geom_curve(
  #   aes(xend = xpos_3_2, 
  #       yend = ypos_3_1, 
  #       x = xpos_3_2 + xshift_3_2,
  #       y = ypos_3_3),
  #   arrow = arrow(length = unit(0.03, "npc")),
  #   curvature = 0.3
  # ) + 
  scale_y_continuous("Estimated with-policy confirmed cases", labels = scales::comma,
                     limits = yr_3, expand = expansion(c(0, 0)))# +
  # annotate(geom = "text", x = xpos_3_1 + xshift_3_1, y = ypos_3_2,
  #          label = expression("Simulation "*gamma),
  #          hjust = 0) + 
  # annotate(geom = "text", x = xpos_3_2 + xshift_3_2, y = ypos_3_3,
  #          label = expression("Est. "*gamma*" assuming"),
  #          hjust = 0, vjust = -0.6) + 
  # annotate(geom = "text", x = xpos_3_2 + xshift_3_2, y = ypos_3_3,
  #          label = expression("14-day delay in"),
  #          hjust = 0, vjust = 0.5) + 
  # annotate(geom = "text", x = xpos_3_2 + xshift_3_2, y = ypos_3_3,
  #          label = expression("recording recovery."),
  #          hjust = 0, vjust = 1.6)

out_scale_trimmed_no_policy <- final_df %>% 
  ggplot() + 
  aes(x = gamma, y = predicted_cum_confirmed_cases_no_policy, color = factor(sigma), shape = factor(sigma)) + 
  geom_point() + 
  theme_classic() + 
  theme(axis.text = element_text(color = "black")) + 
  xlab(expression(gamma)) + 
  ggtitle("Estimated no-policy cases")

yr_4 <- ggplot_build(out_scale_trimmed_no_policy)$layout$panel_params[[1]]$y.range
xpos_4_1 <- xpos_1_1
xpos_4_2 <- xpos_1_2
ypos_4_1 = yr_4[1]
ypos_4_2 = yr_4[1] + 0.3*(diff(yr_4))
ypos_4_3 = yr_4[1] + 0.13*(diff(yr_4))
xshift_4_1 = xshift_1_1
xshift_4_2 = 0.03
out_scale_trimmed_no_policy <- out_scale_trimmed_no_policy + 
  # geom_curve(
  #   aes(xend = xpos_4_1, 
  #       yend = ypos_4_1, 
  #       x = xpos_4_1 + xshift_4_1,
  #       y = ypos_4_2),
  #   arrow = arrow(length = unit(0.03, "npc")),
  #   curvature = 0.3
  # ) + 
  # geom_curve(
  #   aes(xend = xpos_4_2, 
  #       yend = ypos_4_1, 
  #       x = xpos_4_2 + xshift_4_2,
  #       y = ypos_4_3),
  #   arrow = arrow(length = unit(0.03, "npc")),
  #   curvature = 0.3
  # ) + 
  scale_y_continuous("Estimate no-policy confirmed cases", labels = scales::comma,
                     limits = yr_4, expand = c(0, 0)) #+
  # annotate(geom = "text", x = xpos_4_1 + xshift_4_1, y = ypos_4_2,
  #          label = expression("Simulation "*gamma),
  #          hjust = 0) + 
  # annotate(geom = "text", x = xpos_4_2 + xshift_4_2, y = ypos_4_3,
  #          label = expression("Est. "*gamma*" assuming"),
  #          hjust = 0, vjust = -0.6) + 
  # annotate(geom = "text", x = xpos_4_2 + xshift_4_2, y = ypos_4_3,
  #          label = expression("14-day delay in"),
  #          hjust = 0, vjust = 0.5) + 
  # annotate(geom = "text", x = xpos_4_2 + xshift_4_2, y = ypos_4_3,
  #          label = expression("recording recovery."),
  #          hjust = 0, vjust = 1.6)

suppressWarnings({
  final <- (out_scale_down_to_zero + theme(legend.position = c(0.8, 0.55)) | out_scale_trimmed + theme(legend.position = "none")) / 
    (out_scale_trimmed_true + theme(legend.position = "none") | out_scale_trimmed_no_policy + theme(legend.position = "none")) +
    plot_annotation(tag_levels = "a") &
    theme(plot.tag = element_text(face = "bold"),
          legend.text.align = 0,
          legend.title.align = 0.5) &
    scale_color_npg(labels = expression(0.2,0.33,0.5,infinity*" (SIR)")) & 
    scale_shape(labels = expression(0.2,0.33,0.5,infinity*" (SIR)"))
  
  
  cowplot::save_plot(plot = final, filename = "results/figures/fig4/fig4_total_sensitivity_to_gamma.pdf",
                     scale = 2, base_asp = 1.2)
  cowplot::save_plot(plot = final, filename = "results/figures/fig4/fig4_total_sensitivity_to_gamma.jpg",
                     scale = 2, base_asp = 1.2, dpi = 600)
})
