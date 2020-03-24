# Emma Krasovich, ekrasovich@berkeley.edu
# Date: 3/15/20 | updated: 3/22/20
# description: population weighting the policy data with population data from the different administrative units
# before doing so, first merge school closure data with the raw US policy data - 
# note the policy data was manually collected. the school closure data is cleaned in another function.


# load libraries
library(tidyverse)
library(dplyr)
library(stringr)
library(purrr)
library(readxl) # use to open/read excel files
library(downloader)

# set up the working directory as the github environment


#read in the raw policy data pre- school closures:

us_policy_data <- readxl::read_xlsx("data/raw/usa/US_covid_policies_pre_school_closure_data.xlsx") %>% 
  rename(adm1_id = "adm1_name")


# read in the school closure data:

school_closure_data <- read_csv("data/interim/usa/US_school_closures_clean.csv") %>% 
  mutate(access_date = as.POSIXct.Date(access_date, format = "%Y-%m-%d")) %>% 
  rename(date = 'date_closed') %>% 
  mutate(date = as.POSIXct.Date(date, format = "%Y-%m-%d"))


# GET POPULATION DATA FOR WEIGHTING -----------------------------------------
# read in the administrative data containing population information:
# read in the adm_pop1 level dataset

adm1_population_data <- read_csv("data/interim/adm/adm1/adm1.csv") %>% 
  filter(adm0_name == 'USA') %>% 
  dplyr::select(adm0_name, adm1_name, population) %>% 
  rename(adm1_pop = 'population')

#read in the adm2_pop level dataset

adm2_population_data <- read_csv("data/interim/adm/adm2/adm2.csv") %>% 
  filter(adm0_name == 'USA') %>% 
  dplyr::select(adm0_name, adm1_name, adm2_name, population) %>% 
  rename(adm2_pop = 'population')


# download & read in the additional adm3_dataset:
download("https://simplemaps.com/static/data/us-cities/1.6/basic/simplemaps_uscities_basicv1.6.zip", 
                                 dest="data/raw/usa/us_cities_population.zip", mode="wb") 

# list of files inside master.zip
master_list <- as.character(unzip("data/raw/usa/us_cities_population.zip", list = TRUE)$Name)

# load the first file "uscities.csv"
adm3_population_data <- read.csv(unz("data/raw/usa/us_cities_population.zip", "uscities.csv"), header = TRUE,
                 sep = ",") %>% 
  dplyr::select(city, state_id, state_name, county_name, population) %>% 
  rename(adm3_pop = 'population',
         adm2_name =  'county_name',
         adm1_name =  'state_name',
         adm1_id = 'state_id',
         adm3_name = 'city') %>% 
  mutate(adm0_name = "USA")

# MERGE ALL POPULATION DATA
us_population_data <- left_join(adm1_population_data, adm2_population_data, by = c("adm0_name", "adm1_name")) %>%
  left_join(adm3_population_data, by = c("adm0_name", "adm1_name", "adm2_name")) %>%
  dplyr::select(adm0_name, adm1_id, adm1_name, adm1_pop, adm2_name, adm2_pop, adm3_name, adm3_pop)

# get state_xwalk
us_state_xwalk <- adm3_population_data %>% 
  dplyr::select(adm1_id, adm1_name) %>% 
  distinct()


# NOW MERGE STATE XWALK US POLICY DATA --------------------------------------------------
us_policy_w_state_names <- us_policy_data %>% 
  left_join(us_state_xwalk, by = "adm1_id")

school_data_w_state_ids <- school_closure_data %>% 
  left_join(us_state_xwalk, by = "adm1_name")


# MERGE POLICY DATA W SCHOOL CLOSURES --------------------------------------------------
all_policy_data <- bind_rows(us_policy_w_state_names, school_data_w_state_ids) %>% 
  mutate(adm0_name = "USA") %>% 
  distinct()
# ----------------------------------------------------------------------------------


# merge the school closure data w/ the policy data, do this join multiple times, to join by 
# 1) city, county, and state
# 2) county and state
# 3) state

# add in state population data and create weights
us_policy_w_adm1_pop <- left_join(all_policy_data, adm1_population_data, by =c("adm0_name", "adm1_name")) %>%
  mutate(adm1_name = ifelse(adm1_id == "all", "all", adm1_name)) %>% 
  mutate(pop_weight = case_when(
    adm1_name == "all" & adm2_name == "all" & adm3_name == "all" ~ 1,
    adm2_name == "all" & adm3_name == "all" ~ 1,
    adm1_name == "all" & adm2_name == "all" ~ 1,
    adm1_name == "all" ~ 1)) %>% 
  mutate(adm0_name = "USA")
    
# add in county population data and create weights
us_policy_w_adm2_pop <- left_join(us_policy_w_adm1_pop, adm2_population_data, 
                                  by =c("adm0_name", "adm1_name", "adm2_name")) %>%
  mutate(pop_weight2 = case_when(
    !is.na(adm2_pop) ~ adm2_pop/adm1_pop)) 

# add in city populations, but need to get rid of counrty data first
adm3_population_data_cleaned <- adm3_population_data %>%
  dplyr::select(adm1_id, adm1_name, adm3_name, adm3_pop)


us_policy_w_adm3_pop <- left_join(us_policy_w_adm2_pop, adm3_population_data_cleaned, 
                                  by =c("adm1_name", "adm3_name", "adm1_id")) %>% 
  mutate(pop_weight3 = case_when(
    !is.na(adm3_pop) ~ adm3_pop/adm1_pop)) 
  

# CONDENSE ALL THE WEIGHTS
pop_weighted_policy_data <- us_policy_w_adm3_pop %>% 
  mutate(adm1_pop_weight = case_when(
    pop_weight == 1 ~ 1,
    is.na(pop_weight3) & is.na(pop_weight) ~ pop_weight2,
    is.na(pop_weight) & is.na(pop_weight2) ~ pop_weight3,
    is.na(pop_weight) & !is.na(pop_weight2) ~ pop_weight2,
  )) %>% 
  filter(!is.na(adm1_pop_weight)) %>% 
  dplyr::select(adm0_name, adm1_id, adm1_name, adm1_pop_weight, 
                adm2_name, adm3_name, date, policy,
                travel_ban_country_list, no_gathering_size, Optional,
                Notes, source, access_date) %>% 
  filter(date > "2020-01-01")

#save csv
write.csv(pop_weighted_policy_data, "data/interim/usa/US_COVID-19_policies.csv")



