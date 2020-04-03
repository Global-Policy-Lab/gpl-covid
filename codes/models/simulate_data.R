library(tidyverse)
library(lfe)
source("codes/models/projection_helper_functions.R")
p1_effect = 0.1
p2_effect = 0.2
p3_effect = 0.05

no_policy_growth_rate = 0.4
sigma = 0.08

sim_data <- crossing(tibble(unit = 1:20,
                p_1_turns_on = sample(x = 1:15, size = 20, replace = TRUE),
                p_2_turns_on = sample(x = 1:15, size = 20, replace = TRUE),
                p_3_turns_on = sample(x = 1:15, size = 20, replace = TRUE)),
         date = 1:30,
         simulation_id = 1:600) %>% 
  group_by(simulation_id, unit) %>%
  mutate(p_1 = as.double(date >= p_1_turns_on),
         p_2 = as.double(date >= p_2_turns_on),
         p_3 = as.double(date >= p_3_turns_on)) %>%
  mutate(beta_minus_gamma = {
    out <- no_policy_growth_rate - 
      p1_effect*p_1 - 
      p2_effect*p_2 - 
      p3_effect*p_3 + 
      rnorm(n = length(p_1),
            mean = 0,
            sd = 0.08)
    out[1] <- NA_real_
    out
  }) %>% 
  group_by(simulation_id, unit) %>%
  arrange(simulation_id, unit) %>%
  mutate(cum_confirmed_cases = calculate_projection_for_one_unit(
    cum_confirmed_cases_first = 15,
    prediction_logdiff = beta_minus_gamma,
    time_steps_per_day = 6,
    daily_gamma = 0.052,
    unit_population = 800000,
    proportion_confirmed = 0.33
    ),
    D_l_cum_confirmed_cases = c(NA_real_, diff(log(cum_confirmed_cases)))
  )

sim_data <- sim_data %>%
  group_by(simulation_id) %>% 
  nest()
  
pb <- dplyr::progress_estimated(nrow(sim_data))
sim_data <- sim_data %>% 
  mutate(model = data %>% 
           map(~{
             out <- felm(data = .x,
                          formula = D_l_cum_confirmed_cases ~ p_1 + p_2 + p_3)
             pb$tick()$print()
             broom::tidy(out)
           }))

sim_data %>% 
  select(-data) %>%
  unnest(model) %>% 
  filter(term == "p_1") %>%
  ggplot() + 
  aes(x = estimate) %>%
  geom_histogram() + 
  geom_vline(xintercept = -p1_effect)

sim_data %>% 
  select(-data) %>%
  unnest(model) %>% 
  filter(term == "p_2") %>%
  ggplot() + 
  aes(x = estimate) %>%
  geom_histogram() + 
  geom_vline(xintercept = -p2_effect)

sim_data %>% 
  select(-data) %>%
  unnest(model) %>% 
  filter(term == "p_3") %>%
  ggplot() + 
  aes(x = estimate) %>%
  geom_histogram() + 
  geom_vline(xintercept = -p3_effect)
