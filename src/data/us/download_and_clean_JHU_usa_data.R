library(tidyverse)
source("src/data/multi_country/get_JHU_country_data.R")
adm_data <- read_csv("data/interim/adm/adm.csv",
                     col_types = cols(
                       adm0_name = col_character(),
                       adm1_name = col_character(),
                       adm2_name = col_character(),
                       adm3_name = col_character(),
                       latitude = col_double(),
                       longitude = col_double(),
                       capital = col_character(),
                       pop_density_km2 = col_double(),
                       area_km2 = col_double(),
                       population = col_double()
                     ))
usa_adm_data <- adm_data %>% 
  filter(adm0_name %in% c("USA", "GUM"))

usa_data <- get_jhu_data("US")
# usa_data_county <- usa_data %>% 
#   filter(!province_state %in% c("Diamond Princess", "Grand Princess")) %>% 
#   # filter(province_state %>% str_detect(paste0(", ", state.abb))) %>%
#   filter(!province_state %in% state.name)
# 
# usa_data_county <- usa_data_county %>%
#   mutate(county_state = province_state %>% 
#            map(~{
#              if(.x %>% str_detect(", ")){
#                tmp = str_split(.x, ", ")[[1]]
#                out <- tibble(county = tmp[1],
#                              state_abb = tmp[2])
#              } else {
#                out <- tibble(county = .x,
#                              state_abb = NA_character_)
#              }
#              out
#            })) %>% 
#   unnest(county_state) %>% 
#   left_join(tibble(
#     state_abb = state.abb,
#     state_name = state.name,
#   ), by = "state_abb")
# 
# usa_data_county <- usa_data_county %>% 
#   fix_issues()
# 
# usa_data_county <- usa_data_county %>% 
#   select(county, state_abb, state_name, date, 
#          cum_confirmed_cases, cum_deaths,
#          cum_recoveries, active_cases, 
#          cum_confirmed_cases_imputed, cum_deaths_imputed,
#          cum_recoveries_imputed, active_cases_imputed) %>% 
#   mutate(state_abb = if_else(county == "District of Columbia",
#                              "DC", state_abb),
#          state_name = if_else(county == "District of Columbia",
#                               "District of Columbia", state_name))
# 
# # JHU stopped tracking county-level on 03/10
# usa_data_county <- usa_data_county %>% 
#   filter(date <= "2020-03-09")

usa_data_state <- usa_data %>% 
  filter(!province_state %in% c("Diamond Princess", "Grand Princess")) %>% 
  # filter(province_state %>% str_detect(paste0(", ", state.abb))) %>%
  filter(province_state %in% state.name | province_state == "District of Columbia") 

usa_data_state <- usa_data_state %>% 
  fix_issues()

usa_data_state <- usa_data_state %>% 
  rename(state_name = province_state) %>% 
  left_join(tibble(
    state_abb = state.abb,
    state_name = state.name,
  ), by = "state_name") %>% 
  select(state_abb, state_name, date, cum_confirmed_cases, cum_deaths, cum_recoveries, active_cases,
         cum_confirmed_cases_imputed, cum_deaths_imputed, 
         cum_recoveries_imputed, active_cases_imputed)

# usa_data_county_state_collapsed <- usa_data_county %>% 
#   group_by(state_name) %>% 
#   arrange(state_name) %>% 
#   summarise_at(.vars = vars(cum_confirmed_cases, cum_deaths, cum_recoveries, active_cases), sum)
# 
# usa_data_state_state_collapsed <- usa_data_state %>% 
#   group_by(state_name) %>% 
#   arrange(state_name) %>% 
#   summarise_at(.vars = vars(cum_confirmed_cases, cum_deaths, cum_recoveries, active_cases), sum)
# 
# compare the time-collapsed state totals
# usa_data_state_state_collapsed %>% 
#   filter(state_name %in% usa_data_county_state_collapsed$state_name); usa_data_county_state_collapsed

names_order <- read_csv("data/processed/[country]_processed.csv", 
                        col_types = cols(.default = col_character())) %>% names()
# usa_data_county_standardised <- usa_data_county %>% 
#   # DC + Washington DC are both in there. Just a couple cases on two days so dropping.
#   filter(!county %in% c("Guam", "Puerto Rico", "Virgin Islands", "District of Columbia")) %>% 
#   filter(!(county == "Washington" & is.na(state_name))) %>% 
#   mutate(adm2_name = str_replace(county, " Parish| County", "") %>% 
#            str_replace(fixed("St. Joseph"), "Saint Joseph") %>% 
#            str_replace(fixed("St. Louis"), "Saint Louis"),
#          adm1_name = state_name) %>% 
#   mutate(adm0_name = "USA") %>% 
#   select(one_of(names_order))
  
usa_data_state_standardised <- usa_data_state %>% 
  rename(adm1_name = state_name) %>% 
  mutate(adm2_name = NA_character_,
         adm0_name = "USA") %>% 
  select(one_of(names_order))  %>% 
  arrange(adm1_name, date)

# Check if there are any unmatched
# usa_data_state_standardised %>%
#   anti_join(usa_adm_data %>% group_by(adm1_name) %>% slice(1) %>% mutate(adm2_name = NA_character_), by = c("adm1_name"))

usa_data_state_standardised <- usa_data_state_standardised %>% 
  arrange(adm1_name, date)
# write_csv(usa_data_county_standardised, path = "data/interim/usa/usa_jhu_cases_county.csv")
write_csv(usa_data_state_standardised, path = "data/interim/usa/usa_jhu_cases_state.csv")
