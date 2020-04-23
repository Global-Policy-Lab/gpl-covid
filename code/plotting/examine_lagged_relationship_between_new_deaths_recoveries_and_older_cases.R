library(tidyverse)
china <- read_csv("data/interim/china/china_jhu_cases.csv")

china <- china %>% 
  group_by(adm_name) %>% 
  arrange(adm_name, date) %>% 
  mutate(new_deaths = 
           cumulative_deaths - lag(cumulative_deaths),
         new_recoveries = 
           cumulative_recoveries - lag(cumulative_recoveries),
         new_deaths_recoveries = 
           new_deaths + 
           new_recoveries,
         new_cases_lag5_10 = lag(cumulative_confirmed_cases, 5) - lag(cumulative_confirmed_cases, 10),
         new_cases_lag10_15 = lag(cumulative_confirmed_cases, 10) - lag(cumulative_confirmed_cases, 15),
         new_cases_lag15_20 = lag(cumulative_confirmed_cases, 15) - lag(cumulative_confirmed_cases, 20),
         new_cases_lag20_25 = lag(cumulative_confirmed_cases, 20) - lag(cumulative_confirmed_cases, 25),
         new_cases_lag25_30 = lag(cumulative_confirmed_cases, 25) - lag(cumulative_confirmed_cases, 30),
         new_cases_lag30_35 = lag(cumulative_confirmed_cases, 30) - lag(cumulative_confirmed_cases, 35),
         new_cases_lag35_40 = lag(cumulative_confirmed_cases, 35) - lag(cumulative_confirmed_cases, 40))

results1 <- lm(data = china %>% 
                 filter(cumulative_recoveries + cumulative_deaths > 5), 
               formula = new_deaths_recoveries ~ 
                 new_cases_lag5_10 +
                 new_cases_lag10_15 +
                 new_cases_lag15_20 +
                 new_cases_lag20_25 +
                 new_cases_lag25_30 +
                 new_cases_lag30_35 +
                 new_cases_lag35_40 + 
                 factor(adm_name)) %>% 
  broom::tidy()

results1 %>% 
  filter(term %>% str_detect("new_cases")) %>%  
  mutate(days_since_cases_observed = str_replace(term, "new_cases_lag", "") %>% str_split("_") %>% map_dbl(~mean(as.double(.x)))) %>%
  ggplot() + aes(x = days_since_cases_observed, y = estimate) + geom_line() + 
  geom_errorbar(aes(ymin = estimate - 1.96*std.error, ymax = estimate + 1.96*std.error)) + 
  theme_classic() + 
  xlab("Days since new case") + 
  ylab("Number of additional deaths and recoveries")

results2 <- lm(data = china %>% 
                 filter(cumulative_recoveries + cumulative_deaths > 5), 
               formula = new_deaths ~ 
                 new_cases_lag5_10 +
                 new_cases_lag10_15 +
                 new_cases_lag15_20 +
                 new_cases_lag20_25 +
                 new_cases_lag25_30 +
                 new_cases_lag30_35 +
                 new_cases_lag35_40 + 
                 factor(adm_name)) %>% 
  broom::tidy()

results2 %>% 
  filter(term %>% str_detect("new_cases")) %>%  
  mutate(days_since_cases_observed = str_replace(term, "new_cases_lag", "") %>% str_split("_") %>% map_dbl(~mean(as.double(.x)))) %>%
  ggplot() + aes(x = days_since_cases_observed, y = estimate) + geom_line() + 
  geom_errorbar(aes(ymin = estimate - 1.96*std.error, ymax = estimate + 1.96*std.error)) + 
  theme_classic() + 
  xlab("Days since new case") + 
  ylab("Number of additional deaths")

results3 <- lm(data = china %>% 
                 filter(cumulative_recoveries + cumulative_deaths > 5), 
               formula = new_recoveries ~ 
                 new_cases_lag5_10 +
                 new_cases_lag10_15 +
                 new_cases_lag15_20 +
                 new_cases_lag20_25 +
                 new_cases_lag25_30 +
                 new_cases_lag30_35 +
                 new_cases_lag35_40 + 
                 factor(adm_name)) %>% 
  broom::tidy()

results3 %>% 
  filter(term %>% str_detect("new_cases")) %>%  
  mutate(days_since_cases_observed = str_replace(term, "new_cases_lag", "") %>% str_split("_") %>% map_dbl(~mean(as.double(.x)))) %>%
  ggplot() + aes(x = days_since_cases_observed, y = estimate) + geom_line() + 
  geom_errorbar(aes(ymin = estimate - 1.96*std.error, ymax = estimate + 1.96*std.error)) + 
  theme_classic() + 
  xlab("Days since new case") + 
  ylab("Number of additional recoveries")
