suppressPackageStartupMessages(library(tidyverse))
suppressPackageStartupMessages(library(magrittr))

# Brings in the fix issues code
source("codes/data/multi_country/get_JHU_country_data.R")

source("codes/data/usa/get_usafacts_data.R")
state_adm_data <- read_csv("data/interim/adm/adm1/adm1.csv",
                     col_types = cols(
                       adm0_name = col_character(),
                       adm1_name = col_character(),
                       latitude = col_double(),
                       longitude = col_double(),
                       pop_density_km2 = col_double(),
                       area_km2 = col_double(),
                       population = col_double()
                     ))

county_adm_data <- read_csv("data/interim/adm/adm2/adm2.csv",
                            col_types = cols(
                              adm0_name = col_character(),
                              adm1_name = col_character(),
                              adm2_name = col_character(),
                              latitude = col_double(),
                              longitude = col_double(),
                              pop_density_km2 = col_double(),
                              area_km2 = col_double(),
                              population = col_double()
                            ))

usa_state_adm_data <- state_adm_data %>% 
  filter(adm0_name %in% c("USA"))

usa_county_adm_data <- county_adm_data %>% 
  filter(adm0_name %in% c("USA"))

usa_data <- get_usafacts_data()

usa_county_data <- usa_data %>% 
  filter(!(str_detect(adm2_name, "Statewide Unallocated"))) %>% 
  filter(!(str_detect(adm2_name, "Cruise Ship")))

usa_state_data <- usa_data %>% 
  filter(!(str_detect(adm2_name, "Cruise Ship"))) %>% 
  group_by(state_fips, adm1_name, date) %>%
  select(-county_fips, -adm2_name) %>% 
  summarise_all(sum) %>% 
  ungroup()

tmp <- usa_county_data %>% 
  mutate(cum_recoveries = NA_real_) %>% 
  unite(tmp_id, county_fips, state_fips, adm1_name, adm2_name, remove = FALSE) 

# Some fiddly manual edits to downwards data revisions 
usa_county_data <- tmp %>% 
  mutate(cum_confirmed_cases_imputed = if_else(
    tmp_id %in% c("6041_6_CA_Marin County", "6079_6_CA_San Luis Obispo County") & 
      date %in% lubridate::as_date(c("2020-03-11", "2020-03-12")) & cum_confirmed_cases == 16, 
    0, cum_confirmed_cases
  )) %>% 
  mutate(cum_confirmed_cases = if_else(
    tmp_id %in% c("6041_6_CA_Marin County", "6079_6_CA_San Luis Obispo County") & 
      date %in% lubridate::as_date(c("2020-03-11", "2020-03-12")) & cum_confirmed_cases == 16, 
    NA_real_, cum_confirmed_cases
  )) %>% 
  mutate(cum_confirmed_cases_imputed = if_else(
    tmp_id %in% c("8097_8_CO_Pitkin County") & 
      date %in% lubridate::as_date(c("2020-03-15", "2020-03-16")) & cum_confirmed_cases == 12, 
    0, cum_confirmed_cases_imputed
  )) %>% 
  mutate(cum_confirmed_cases = if_else(
    tmp_id %in% c("8097_8_CO_Pitkin County") & 
      date %in% lubridate::as_date(c("2020-03-15", "2020-03-16")) & cum_confirmed_cases == 12, 
    NA_real_, cum_confirmed_cases
  )) %>% 
  fix_issues()

# usa_state_data %>% 
#   unite(tmp_id, state_fips, adm1_name, remove = FALSE) %>% 
#   examine_issues(cum_confirmed_cases)

tmp <- usa_state_data %>% 
  unite(tmp_id, state_fips, adm1_name, remove = FALSE) %>% 
  mutate(cum_recoveries = NA_real_) %>% 
  mutate(cum_confirmed_cases_imputed = cum_confirmed_cases)
# Virginia is the most trouble here
# tmp %>% filter(tmp_id == "51_VA", date >= "2020-03-07", date <= "2020-03-17") 
# A tibble: 11 x 7
#   tmp_id state_fips adm1_name date       cum_confirmed_cases cum_deaths cum_recoveries
#   <chr>  <chr>      <chr>     <date>                   <dbl>      <dbl>          <dbl>
# 1 51_VA  51         VA        2020-03-07                   0          0             NA
# 2 51_VA  51         VA        2020-03-08                   2          0             NA
# 3 51_VA  51         VA        2020-03-09                  48          0             NA
# 4 51_VA  51         VA        2020-03-10                  48          0             NA
# 5 51_VA  51         VA        2020-03-11                  48          0             NA
# 6 51_VA  51         VA        2020-03-12                  48          0             NA
# 7 51_VA  51         VA        2020-03-13                  38          0             NA
# 8 51_VA  51         VA        2020-03-14                  37          1             NA
# 9 51_VA  51         VA        2020-03-15                  40          1             NA
#10 51_VA  51         VA        2020-03-16                  45          2             NA
#11 51_VA  51         VA        2020-03-17                  60          2             NA
# Assume the 2 and the 37 are right then impute/set to missing. Yuck.
to_replace <- tmp$cum_confirmed_cases[tmp$tmp_id == "51_VA" & 
                                        tmp$date <= lubridate::as_date("2020-03-14") & 
                                        tmp$date >= lubridate::as_date("2020-03-08")]
if(identical(to_replace, c(2,48,48,48,48,38,37))){
  tmp$cum_confirmed_cases_imputed[tmp$tmp_id == "51_VA" & 
                                    tmp$date <= lubridate::as_date("2020-03-14") & 
                                    tmp$date >= lubridate::as_date("2020-03-08")] <- 
    round(exp(log(to_replace[1])*(6:0)/6 + log(to_replace[7])*(0:6)/6))
  tmp$cum_confirmed_cases[tmp$tmp_id == "51_VA" & 
                            tmp$date <= lubridate::as_date("2020-03-14") & 
                            tmp$date >= lubridate::as_date("2020-03-08")] <- NA_real_
}
usa_state_data <- tmp %>% 
  fix_issues()

usa_state_data <- usa_state_data %>% 
  mutate(active_cases = cum_confirmed_cases - cum_deaths - cum_recoveries,
         active_cases_imputed = cum_confirmed_cases_imputed - cum_deaths_imputed - cum_recoveries_imputed)
usa_county_data <- usa_county_data %>% 
  mutate(active_cases = cum_confirmed_cases - cum_deaths - cum_recoveries,
         active_cases_imputed = cum_confirmed_cases_imputed - cum_deaths_imputed - cum_recoveries_imputed)
