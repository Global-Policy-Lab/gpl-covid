suppressPackageStartupMessages(library(tidyverse))
suppressPackageStartupMessages(library(magrittr))

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

county_adm_data <- read_csv("data/interim/usa/adm2_pop_fips.csv",
                            col_types = cols(
                              adm1_name = col_character(),
                              adm2_name = col_character(),
                              fips = col_character(),
                              population = col_double(),
                              area_km2 = col_double(),
                              capital = col_character()
                            ))

usa_state_adm_data <- state_adm_data %>% 
  filter(adm0_name %in% c("USA"))

usa_county_adm_data <- county_adm_data %>% 
  mutate(adm0_name  = "USA")
stopifnot(all(nchar(usa_county_adm_data$fips[!is.na(usa_county_adm_data$fips)]) == 5))

usa_county_adm_data <- usa_county_adm_data %>% 
  filter(!is.na(fips))
suppressWarnings(usa_data <- get_usafacts_data())

# trim off trailing NAs
usa_data <- usa_data %>% 
  arrange(adm1_name, adm2_name, date) %>% 
  group_by(adm1_name, adm2_name) %>% 
  filter(rev(cumsum(rev(!is.na(cum_confirmed_cases)))) > 0)

usa_county_data <- usa_data %>% 
  filter(!(str_detect(adm2_name, "Statewide Unallocated"))) %>% 
  filter(!(str_detect(adm2_name, "Cruise Ship")))

usa_county_data <- usa_county_data %>% 
  select(-matches("X[0-9]+"))

usa_state_data <- usa_data %>% 
  filter(!(str_detect(adm2_name, "Cruise Ship"))) %>% 
  # has missing deaths - assume 0. They have low case numbers as of Apr 08
  mutate(cum_deaths = if_else(adm1_name == "OH" & adm2_name == "Fairfield County" & is.na(cum_deaths),
                              0 , cum_deaths)) %>%
  mutate(cum_deaths = if_else(adm1_name == "WY" & adm2_name == "Weston County" & is.na(cum_deaths) & cum_confirmed_cases == 0,
                              0 , cum_deaths)) %>%
  group_by(state_fips, adm1_name, date) %>%
  select(-county_fips, -adm2_name) %>% 
  summarise_all(sum) %>% 
  ungroup()

usa_county_data <- usa_county_data %>% 
  mutate(cum_recoveries = NA_real_) %>% 
  unite(tmp_id, county_fips, state_fips, adm1_name, adm2_name, remove = FALSE) 

# Remove today as it can get updated slowly
usa_county_data <- usa_county_data %>% 
  filter(date < max(date)) %>% 
  filter(!str_detect(tmp_id, "Unallocated"))
usa_state_data <- usa_state_data %>% 
  filter(date < max(date))

suppressWarnings({
  # Some fiddly manual edits to downwards data revisions 
  usa_county_data <- usa_county_data %>%
    ungroup %>% 
    mutate(cum_confirmed_cases_imputed = if_else(
      tmp_id %in% c("06041_06_CA_Marin County", "06079_06_CA_San Luis Obispo County") & 
        date %in% lubridate::as_date(c("2020-03-11", "2020-03-12")) & cum_confirmed_cases == 16, 
      0, cum_confirmed_cases
    )) %>% 
    mutate(cum_confirmed_cases = if_else(
      tmp_id %in% c("06041_06_CA_Marin County", "06079_06_CA_San Luis Obispo County") & 
        date %in% lubridate::as_date(c("2020-03-11", "2020-03-12")) & cum_confirmed_cases == 16, 
      NA_real_, cum_confirmed_cases
    )) %>% 
    mutate(cum_confirmed_cases_imputed = if_else(
      tmp_id %in% c("08097_08_CO_Pitkin County") & 
        date %in% lubridate::as_date(c("2020-03-15", "2020-03-16")) & cum_confirmed_cases == 12, 
      11, cum_confirmed_cases_imputed
    )) %>% 
    mutate(cum_confirmed_cases = if_else(
      tmp_id %in% c("08097_08_CO_Pitkin County") & 
        date %in% lubridate::as_date(c("2020-03-15", "2020-03-16")) & cum_confirmed_cases == 12, 
      NA_real_, cum_confirmed_cases
    )) %>% 
    mutate(cum_confirmed_cases_imputed = if_else(
      tmp_id %in% c("06025_06_CA_Imperial County") & 
        date %in% lubridate::as_date(c("2020-03-11", "2020-03-12")) & cum_confirmed_cases == 16, 
      0, cum_confirmed_cases_imputed
    )) %>% 
    mutate(cum_confirmed_cases = if_else(
      tmp_id %in% c("06025_06_CA_Imperial County") & 
        date %in% lubridate::as_date(c("2020-03-11", "2020-03-12")) & cum_confirmed_cases == 16, 
      NA_real_, cum_confirmed_cases
    )) %>% 
    mutate(cum_confirmed_cases_imputed = if_else(
      tmp_id %in% c("05125_05_AR_Saline County") & 
        date %in% lubridate::as_date(c("2020-04-06", "2020-04-07")) & cum_confirmed_cases == 33, 
      30, cum_confirmed_cases_imputed
    )) %>% 
    mutate(cum_confirmed_cases = if_else(
      tmp_id %in% c("05125_05_AR_Saline County") & 
        date %in% lubridate::as_date(c("2020-04-06", "2020-04-07")) & cum_confirmed_cases == 33, 
      NA_real_, cum_confirmed_cases
    ))
})


suppressWarnings({
  usa_state_data <- usa_state_data %>% 
    mutate(cum_recoveries = NA_real_) %>% 
    unite(tmp_id, state_fips, adm1_name, remove = FALSE) %>%
    fix_issues()
})

usa_state_data <- usa_state_data %>% 
  mutate(active_cases = cum_confirmed_cases - cum_deaths - cum_recoveries,
         active_cases_imputed = cum_confirmed_cases_imputed - cum_deaths_imputed - cum_recoveries_imputed)
usa_county_data <- usa_county_data %>% 
  mutate(active_cases = cum_confirmed_cases - cum_deaths - cum_recoveries)

names_order <- read_csv("data/processed/[country]_processed.csv", 
                        col_types = cols(.default = col_character())) %>% names()

# merge kusilvak and west hampton AK
usa_county_data <- usa_county_data %>% 
  mutate(adm2_name = adm2_name %>% 
           str_replace("Wade Hampton Census Area", "Kusilvak Census Area"),
         county_fips = county_fips %>% 
           str_replace("02270", "02158")
  )
counties_missed <- usa_county_data %>%
  anti_join(usa_county_adm_data, by = c("county_fips" = "fips")) %>% 
  select(county_fips, adm1_name, adm2_name) %>% distinct()
if(nrow(counties_missed) > 0){
  cat("Counties unmatched in adm dataset in usafacts cleaning:\n")
  print(counties_missed)
}

suppressWarnings({
  usa_county_data_standardised <- usa_county_data %>%
    select(-adm2_name, -adm1_name, -state_fips) %>% 
    inner_join(usa_county_adm_data, by = c("county_fips" = "fips")) %>% 
    mutate(adm0_name = "USA") %>%
    select(one_of(names_order)) %>% 
    arrange(adm1_name, adm2_name, date)
})

suppressWarnings({
  usa_state_data_standardised <- usa_state_data %>% 
    mutate(adm0_name = "USA") %>% 
    select(one_of(names_order)) %>% 
    arrange(adm1_name, date)
})

usa_county_data_standardised2 <- usa_county_data_standardised %>% 
  complete(date, nesting(adm0_name, adm1_name, adm2_name))

usa_state_data_standardised2 <- usa_state_data_standardised %>% 
  complete(date, nesting(adm0_name, adm1_name))

stopifnot(nrow(usa_state_data_standardised2) == nrow(usa_state_data_standardised))
stopifnot(nrow(usa_county_data_standardised2) == nrow(usa_county_data_standardised2))

stopifnot(!anyNA(usa_county_data_standardised$cum_confirmed_cases_imputed))
stopifnot(!anyNA(usa_state_data_standardised$cum_confirmed_cases_imputed))

usa_state_data_standardised <- usa_state_data_standardised %>% 
  left_join(tibble(state.abb = c(state.abb, "DC"),
                   state.name = c(state.name, "District of Columbia")), by = c("adm1_name" = "state.abb")) %>% 
  mutate(adm1_name = state.name) %>% 
  select(-state.name)

# These have been causing problems so I drop them here. We do not currently use them.
usa_state_data_standardised <- usa_state_data_standardised %>% 
  select(-cum_deaths, -cum_deaths_imputed, -active_cases, -active_cases_imputed, -cum_recoveries, -cum_recoveries_imputed)
write_csv(usa_county_data_standardised, path = "data/interim/usa/usa_usafacts_county.csv")
write_csv(usa_state_data_standardised, path = "data/interim/usa/usa_usafacts_state.csv")
