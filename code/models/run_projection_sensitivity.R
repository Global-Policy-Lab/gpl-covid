suppressPackageStartupMessages(library(tidyverse))
suppressPackageStartupMessages(library(gt))
suppressPackageStartupMessages(library(ggsci))
suppressPackageStartupMessages(library(patchwork))

dir.create("results/figures/fig4", recursive=TRUE, showWarnings=FALSE)

list.files("code/models", full.names = TRUE) %>% 
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

underreporting <- read_csv("data/interim/multi_country/under_reporting.csv",
                           col_types = cols(
                             country = col_character(),
                             underreporting_estimate = col_double()
                           ))

paper_gamma = gamma
paper_ifr = 0.0075

loop_df <- crossing(
  tibble(country =   c("china", "iran", "korea", "italy", "france", "usa"),
         display_country = c("China", "Iran", "South Korea", "Italy", "France", "United States"),
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
  gamma = unique(c(0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4, paper_gamma)),
  sigma = c(0.2, 0.33, 0.5, Inf),
  time_steps_per_day = c(6)
) %>% 
  left_join(underreporting, by = c("urcountry" = "country")) %>% 
  filter(ifr == paper_ifr | (gamma == paper_gamma & sigma == Inf))

pb <- dplyr::progress_estimated(nrow(loop_df))

loop_df <- loop_df %>% 
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

gamma_df <- loop_df %>% 
  filter(ifr == paper_ifr, gamma %in% c(0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4)) %>% 
  select(country, gamma, sigma, time_steps_per_day, projection, underreporting_estimate) %>% 
  unnest(projection) %>% 
  group_by(country, gamma, sigma, time_steps_per_day) %>% 
  filter(date == max(date)) %>%
  mutate(cases_saved = predicted_cum_confirmed_cases_no_policy - predicted_cum_confirmed_cases_true,
         infections_saved = cases_saved / underreporting_estimate) %>% 
  group_by(gamma, sigma, time_steps_per_day) %>% 
  summarise(predicted_cum_confirmed_cases_true = sum(predicted_cum_confirmed_cases_true),
            predicted_cum_confirmed_cases_no_policy = sum(predicted_cum_confirmed_cases_no_policy),
            cases_saved = sum(cases_saved),
            infections_saved = sum(infections_saved)) %>% 
  mutate(cases_saved = predicted_cum_confirmed_cases_no_policy - predicted_cum_confirmed_cases_true) %>% 
  arrange(time_steps_per_day, gamma, sigma) %>%
  ungroup() %>% 
  mutate(sigma = as.character(sigma))

out_scale_down_to_zero <- gamma_df %>%
  ggplot() + 
  aes(x = gamma, y = cases_saved, color = factor(sigma), shape = factor(sigma)) + 
  geom_point() + 
  theme_classic() + 
  theme(axis.text = element_text(color = "black")) + 
  xlab(expression(gamma)) + 
  ggtitle("Cases delayed (log scale)")

out_scale_down_to_zero <- out_scale_down_to_zero + 
  scale_y_log10("Confirmed cases delayed\n(log scale)",
                breaks = scales::trans_breaks("log10", function(x) 10^x),
                labels = scales::trans_format("log10", scales::math_format(10^.x)),
                limits = c(10, 10^8), 
                expand = c(0, 0))

out_scale_trimmed <- gamma_df %>% 
  ggplot() + 
  aes(x = gamma, y = cases_saved, color = factor(sigma), shape = factor(sigma)) + 
  geom_point() + 
  theme_classic() + 
  theme(axis.text = element_text(color = "black")) + 
  xlab(expression(gamma)) + 
  ggtitle("Cases delayed (linear scale)") 

yr_2 <- ggplot_build(out_scale_trimmed)$layout$panel_params[[1]]$y.range
out_scale_trimmed <- out_scale_trimmed + 
  scale_y_continuous("Confirmed cases delayed\n(linear scale trimmed)", labels = scales::comma, 
                     limits = yr_2, expand = c(0, 0))

out_scale_trimmed_true <- gamma_df %>% 
  ggplot() + 
  aes(x = gamma, y = predicted_cum_confirmed_cases_true, color = factor(sigma), shape = factor(sigma)) + 
  geom_point() + 
  theme_classic() + 
  theme(axis.text = element_text(color = "black")) + 
  xlab(expression(gamma)) + 
  ggtitle("Estimated with-policy cases")


yr_3 <- ggplot_build(out_scale_trimmed_true)$layout$panel_params[[1]]$y.range
suppressWarnings({
  # expand scale is deprecated but our conda has an old ggplot
  out_scale_trimmed_true <- out_scale_trimmed_true + 
    scale_y_continuous("Estimated with-policy confirmed cases\n(linear scale trimmed)", labels = scales::comma,
                       limits = yr_3, expand = expand_scale(c(0, 0)))
})

out_scale_trimmed_no_policy <- gamma_df %>% 
  ggplot() + 
  aes(x = gamma, y = predicted_cum_confirmed_cases_no_policy, color = factor(sigma), shape = factor(sigma)) + 
  geom_point() + 
  theme_classic() + 
  theme(axis.text = element_text(color = "black")) + 
  xlab(expression(gamma)) + 
  ggtitle("Estimated no-policy cases")

yr_4 <- ggplot_build(out_scale_trimmed_no_policy)$layout$panel_params[[1]]$y.range
out_scale_trimmed_no_policy <- out_scale_trimmed_no_policy + 
  scale_y_continuous("Estimated no-policy confirmed cases\n(linear scale trimmed)", labels = scales::comma,
                     limits = yr_4, expand = c(0, 0),
                     breaks = seq(round(yr_4[1], -6), round(yr_4[2], -6), by = 3000000))

suppressWarnings({
  e <- expression(sigma*" = "*phantom(2)*"0.2"*" (SEIR)",sigma*" = 0.33"*" (SEIR)",sigma*" = "*phantom(2)*"0.5"*" (SEIR)",sigma*" = "*phantom(",,,,")*infinity*phantom(",,,,")*"(SIR)")

  final <- (out_scale_trimmed_no_policy + theme(legend.position = "none")) + 
    (out_scale_trimmed_true + theme(legend.position = "none")) + 
    (out_scale_trimmed + theme(legend.position = "none")) + 
    (out_scale_down_to_zero + theme(legend.position = c(0.7, 0.3))) + 
    patchwork::plot_layout(ncol = 2) +
    plot_annotation(tag_levels = "a") &
    theme(plot.tag = element_text(face = "bold"),
          legend.text.align = 0,
          legend.text = element_text(size = 12),
          legend.title = element_blank()) &
    scale_color_npg(labels = e) & 
    scale_shape(labels = e)
  
  
  cowplot::save_plot(plot = final, filename = "results/figures/fig4/fig4_total_sensitivity_to_gamma.pdf",
                     scale = 1.1, dpi = 300,
                     base_width = 183/25.3,
                     base_height = 183/25.3/1.2)
  cowplot::save_plot(plot = final, filename = "results/figures/fig4/fig4_total_sensitivity_to_gamma.jpg",
                     scale = 1.1, dpi = 300,
                     base_width = 183/25.3,
                     base_height = 183/25.3/1.2)
  write_csv(gamma_df %>% dplyr::select(-time_steps_per_day), path = "results/source_data/ExtendedDataFigure7.csv")
  if(file.exists("Rplots.pdf")){
    invisible(file.remove("Rplots.pdf"))
  }
})

ifr_df <- loop_df %>%
  filter(gamma == paper_gamma, sigma == Inf) %>% 
  select(ifr, display_country, projection, underreporting_estimate) %>% 
  unnest(projection) %>% 
  group_by(ifr, display_country) %>% 
  filter(date == max(date)) %>% 
  ungroup() %>% 
  mutate(cases_saved = predicted_cum_confirmed_cases_no_policy - 
           predicted_cum_confirmed_cases_true) %>% 
  mutate(infections_saved = cases_saved / underreporting_estimate) %>% 
  arrange(ifr, display_country) %>%
  select(ifr, display_country, cases_saved, infections_saved) %>% 
  mutate(cases_saved = round(cases_saved, -3)) %>% 
  mutate(infections_saved = round(infections_saved, -3))
  
ifr_table <- ifr_df %>% 
  pivot_wider(names_from = ifr,
              values_from = c(cases_saved, infections_saved)) %>% 
  gt(rowname_col = "display_country") %>% 
  tab_header(title = html("Supplementary Table 6 | Sensitivity of cases and infections<br>delayed/avoided to assumed infection fatality rate")) %>% 
  tab_spanner(label = c("IFR = 0.5%"),
              columns = vars(cases_saved_0.005, infections_saved_0.005)) %>% 
  tab_spanner(label = c("IFR = 0.75% (Main results)"),
              columns = vars(cases_saved_0.0075, infections_saved_0.0075)) %>% 
  tab_spanner(label = c("IFR = 1.0%"),
              columns = vars(cases_saved_0.01, infections_saved_0.01)) %>% 
  cols_label(cases_saved_0.005 = html("Confirmed cases<br>avoided/delayed"),
             infections_saved_0.005 = html("Infections<br>avoided/delayed"),
             cases_saved_0.0075 = html("Confirmed cases<br>avoided/delayed"),
             infections_saved_0.0075 = html("Infections<br>avoided/delayed"),
             cases_saved_0.01 = html("Confirmed cases<br>avoided/delayed"),
             infections_saved_0.01 = html("Infections<br>avoided/delayed")) %>%  
  cols_align("right") %>% 
  grand_summary_rows(
    fns = list(
      Total = ~sum(., na.rm = TRUE)
    ),
    decimals = 0
  ) %>% 
  fmt_number(columns = everything(),
             decimals = 0) %>% 
  tab_options(table.border.top.width = 0,
              column_labels.border.top.width = 0,
              heading.border.bottom.color = "black",
              column_labels.border.bottom.color = "black",
              stub.border.width = 0,
              table_body.hlines.width = 0,
              table_body.border.bottom.color = "black",
              grand_summary_row.border.color = "black",
              grand_summary_row.border.style = "single",
              grand_summary_row.border.width = 2,
              ) %>% 
  tab_style(style = cell_text(color = "black", font = "Arial"),
            locations = list(cells_column_labels(everything()),
                             cells_column_spanners(everything()),
                             cells_body(),
                             cells_stub(),
                             cells_grand_summary(),
                             cells_title("title"))) %>% 
  tab_style(style = cell_text(weight = "bold", size = px(11/0.75), color = "black",
                              align = "left"), 
            locations = cells_title("title"))

# Check these for the ranges quoted in the discussion
# The ranges quoted are the outer range from 
# the union of ifr_table and the numbers below
gamma_df %>% 
  filter(cases_saved == min(cases_saved))

gamma_df %>% 
  filter(cases_saved == max(cases_saved))

gamma_df %>% 
  filter(infections_saved == min(infections_saved))

gamma_df %>% 
  filter(infections_saved == max(infections_saved))
