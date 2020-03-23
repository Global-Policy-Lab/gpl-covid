# Emma Krasovich
# Date: 3/15/20
# description: COVID-19 data cleaning for school closures

# load libraries
library(tidyverse)
library(dplyr)
library(lubridate)
library(magrittr)
library(stringr)
library(purrr)
library(stringr)
library(gdata)
library(readxl) #read_xlsx()
library(sf) #st_read
library(openxlsx) # use to open/read excel files
library(readxl) # use to open/read excel files


# set wd
setwd("/Users/ekrasovich/GPL NZ Project Dropbox/Emma Krasovich/GPL_covid")

# # read in the files
city_state_xwalk <- read_csv("/Users/ekrasovich/GPL NZ Project Dropbox/Emma Krasovich/GPL_covid/data/raw/usa/sources/uscities.csv") %>%
  rename(state = `state_id`,
         city_pop = 'population') %>%
  dplyr::select(-zips, -ranking, -timezone, -incorporated, -id,
                -military, -lat, -lng, -density, -source, -county_name_all,
                -county_fips_all, -city_ascii, -county_fips)


state_xwalk <- city_state_xwalk %>% 
  dplyr::select(state, state_name) %>% 
  mutate(state_name = tolower(state_name)) %>% 
  distinct()

# read in the adm_pop3 level dataset
adm3_pop <- read_csv("/Users/ekrasovich/GPL NZ Project Dropbox/Emma Krasovich/GPL_covid/data/interim/usa/adm3_pop.csv") 
 
# to fill in any blanks
adm3_population <- adm3_pop %>% 
# get rid of the city/towm/CDP/village
  mutate(adm3_name = str_split(adm3_name, " CDP") %>% map(1) %>% unlist()) %>% 
  mutate(city_name = str_split(adm3_name, " village") %>% map(1) %>% unlist()) %>% 
  mutate(city_name = str_split(city_name, " town") %>% map(1) %>% unlist()) %>% 
  mutate(city_name = str_split(city_name, " city") %>% map(1) %>% unlist()) %>% 
  mutate(city_name = str_split(city_name, " municipality") %>% map(1) %>% unlist()) %>% 
  mutate(city_name = str_split(city_name, " borough") %>% map(1) %>% unlist()) %>% 
  mutate(state_name = tolower(adm_1_name)) %>% 
  dplyr::select(-adm3_name, -adm_1_name, -state) %>% 
  left_join(state_xwalk, by = "state_name")

# clean up school closures data
school_closures <- readxl::read_xlsx("/Users/ekrasovich/GPL NZ Project Dropbox/Emma Krasovich/GPL_covid/data/raw/usa/sources/coronavirus-school-closures-data.xlsx") %>% 
  rename(district_name = `District Name`,
         state = 'State',
         city_name = 'City',
         dates_closed = `Dates Closed`,
         ) %>% 
  dplyr::select(state, city_name, dates_closed) %>% 
  filter(!is.na(city_name))



# merge these files together
US_schools_merged <- left_join(school_closures, adm3_population, by = c('city_name', 'state')) %>% 
  distinct()

US_schools_intermediate <- US_schools_merged %>% 
  mutate(date_closed = str_split(dates_closed, " ") %>% map(1) %>% unlist()) %>%
  mutate(date_closed = ifelse(date_closed == 'Closed', NA, date_closed)) %>% 
  mutate(date_closed2 = str_split(dates_closed, " ", simplify = TRUE)[,2]) %>% 
  mutate(date_closed = ifelse(is.na(date_closed), date_closed2, date_closed)) %>% 
  mutate(date_closed3 = str_split(dates_closed, " ", simplify = TRUE)[,3]) %>% 
  mutate(date_closed = ifelse(date_closed == 'starting', NA, date_closed)) %>% 
  mutate(date_closed = ifelse(is.na(date_closed), date_closed3, date_closed)) %>% 
  mutate(date_closed = as.Date(date_closed, format = "%m/%d/%Y")) %>% 
  dplyr::select(-date_closed2, -date_closed3, -dates_closed) %>% 
  rename(city_pop = `pop`) %>% 
  dplyr::select(-place)

# save population file
write_csv(US_schools_intermediate, "/Users/ekrasovich/GPL NZ Project Dropbox/Emma Krasovich/GPL_covid/data/raw/usa/US_schools_intermediate.csv")



# now get the county and state population
state_population_data <- read_csv("src/data/us/population_data.csv") %>%
  rename(state_name = 'State',
         state_pop = 'Pop') %>% 
  dplyr::select(state_name, state_pop) %>% 
  mutate(state_name = tolower(state_name))


county_population_data <- read_csv("data/raw/usa/sources/co-est2018-alldata.csv") %>% 
  dplyr::select(STATE, STNAME, COUNTY, CTYNAME, POPESTIMATE2018) %>% 
  rename(state = 'STATE',
         state_name = 'STNAME',
         county = 'COUNTY', 
         county_name_long = 'CTYNAME',
         county_pop = 'POPESTIMATE2018') %>% 
  mutate(state_name = tolower(state_name)) %>% 
  mutate(county_name = str_split(county_name_long, " County") %>% map(1) %>% unlist()) %>% 
  filter(county != '000')


population_data <- left_join(state_population_data, county_population_data, by = "state_name") %>% 
  rename(st_code ='state') %>% 
  left_join(state_xwalk, by = "state_name")

# save population file
write_csv(population_data, "/Users/ekrasovich/GPL NZ Project Dropbox/Emma Krasovich/GPL_covid/data/raw/usa/US_population_data.csv")



#aggregrate schools at the state level
US_school_closures <- US_schools_intermediate %>% 
  left_join(st_pop, by = "state") %>% 
  mutate(adm3_pop_weight = city_pop/state_pop) %>% 
  distinct() %>% 
  dplyr::select(state, date_closed, adm3_pop_weight, city_name) %>% 
  rename(date = 'date_closed') 
  
  
  
  # 
  # dplyr::select(-state_name.x, -place, -st_code, -county) %>% 
  # rename(state_name = `state_name.y`) %>% 
  # distinct() %>% 
  # # add new weighted column, divide city by state pop
  # mutate(adm3_pop_weight = round(as.numeric(city_pop/state_pop), digit = 2)) %>% 
  # dplyr::select(date_closed, adm3_pop_weight, state, state_name) %>% 
  # group_by(state, state_name, date_closed, adm3_pop_weight) %>% 
  # summarize() %>% 
  # ungroup() %>% 
  # group_by(state, state_name, date_closed) %>% 
  # summarize(adm3_pop_weight = sum(adm3_pop_weight)) %>% 
  # filter(!is.na(adm3_pop_weight)) %>% 
  # filter(adm3_pop_weight != 0)
  # 
mutate(adm1_pop_weight = ifelse(county_name == 'all', 1, adm1_pop_weight))

# save file
write_csv(US_school_closures, "/Users/ekrasovich/GPL NZ Project Dropbox/Emma Krasovich/GPL_covid/data/raw/usa/CLEAN_US_school_closures.csv")

# read in the policy file and do tha same thing
# clean up the conrty data
adm_xwalk <- read_csv("/Users/ekrasovich/GPL NZ Project Dropbox/Emma Krasovich/GPL_covid/data/raw/usa/sources/uscities.csv") %>% 
  dplyr::select(city, state_id, county_name) %>% 
  rename(state = 'state_id',
         city_name = 'city')

city_pop <- left_join(adm_xwalk, adm3_population, by = c("city_name", "state")) %>% 
  rename(city_pop = 'pop') %>% 
  dplyr::select(-state_name) %>% 
  distinct()

all_pop <- left_join( population_data, city_pop, by = c("state", "county_name")) %>% 
  dplyr::select(-place, -county_name_long, -county, -st_code)

write.csv(all_pop, "/Users/ekrasovich/GPL NZ Project Dropbox/Emma Krasovich/GPL_covid/data/raw/usa/all_pop.csv")


policy <- readxl::read_xlsx("data/raw/usa/US_COVID-19_Policy_raw_w_extras.xlsx") %>% 
  rename(county_name = `adm2_name`,
         city_name = 'adm3_name',
         state = 'adm1_name') 
  
st_pop <- all_pop %>% 
  dplyr::select(state, state_pop) %>% 
  distinct()

county_pop <- all_pop %>% 
  dplyr::select(county_name, county_pop, state) %>% 
  distinct()

city_pop <- all_pop %>% 
  dplyr::select(city_name, city_pop, state) %>% 
  distinct() %>% 
  filter(city_pop != 0)




policy_and_pop <- policy %>% 
  left_join(st_pop, by = "state") %>% 
  left_join(county_pop, by = c("county_name", "state")) %>% 
  left_join(city_pop, by = c("city_name", "state")) 
            
  

weights <- policy_and_pop %>% 
  mutate(adm2_pop_weight = county_pop/state_pop) %>% 
  mutate(adm3_pop_weight = city_pop/state_pop) %>% 
  mutate(adm2_pop_weight = ifelse(county_name == "all", 1, adm2_pop_weight)) %>% 
  mutate(adm3_pop_weight = ifelse(city_name == "all", adm2_pop_weight, adm3_pop_weight)) %>% 
  mutate(adm3_pop_weight = ifelse(!is.na(school_weight), school_weight, adm3_pop_weight)) %>% 
  filter(!is.na(city_name) & !is.na(county_name)) %>% 
  mutate(date = as.Date(date)) %>% 
  bind_rows(US_school_closures) %>% 
  distinct()
  

write.csv(weights, "/Users/ekrasovich/GPL NZ Project Dropbox/Emma Krasovich/GPL_covid/data/raw/usa/US_COVID-19_policies.csv")
# 
# 
# 
#   
#   left_join(adm3_population, by= c("state", "city_name")) %>% 
#    dplyr::select(-place) %>% 
#   left_join(pop, by = c("state","county_name")) %>% 
#   # now create weighting variable
#   mutate(adm2_pop_weight = round(county_pop/state_pop)) %>% 
#   mutate(adm3_pop_weight = round(pop/state_pop)) %>% 
#    dplyr::select(adm0, state,  county_name, 
#                  adm2_pop_weight, city_name, adm3_pop_weight, date, policy, 
#                 travel_ban_country_list, no_gathering_size, Notes, 
#                 Optional, source, access_date) %>% 
#   rename(adm1_name = 'state',
#          adm2_name = 'county_name',
#          adm3_name = 'city_name')
# 
# # add in the weights
# policy_w_weights <- policy %>% 
#   mutate(adm2_pop_weight = ifelse(adm2_name == 'all', 1, adm2_pop_weight)) %>% 
#   mutate(adm3_pop_weight = ifelse(adm2_pop_weight == 1, 1, adm3_pop_weight))
# 
#   
# 
# 
# %>% 
#   mutate(adm2_pop_weight = ifelse(is.na(county_name), 1, county_st_weight)) %>% 
#   mutate(adm3_pop_weight = ifelse(city_name == 'all', 1, city_st_weight)) %>%
#   
#   rename(adm1_name = 'state',
#          adm2_name = 'county_name',
#          adm3_name = 'city_name') %>% 
#   dplyr::select(adm0, adm1_name, adm2_name, adm2_pop_weight, adm3_name, 
#                 adm3_pop_weight, date, policy, travel_ban_country_list,
#                 no_gathering_size, Notes, 
#                 Optional, source, access_date)
# 
# 
#           
#   
#   
#   mutate(st_pop_weight = round(pop/state_pop, digit = 3)) %>% 
#   mutate(adm1_pop_weight = ifelse(!is.na(st_pop_weight), st_pop_weight, adm1_pop_weight)) %>% 
#   mutate(adm2_pop_weight = ifelse(city_name == "all", 1, adm1_pop_weight)) %>% 
#   mutate(adm1_pop_weight = ifelse(county_name == "all", 1, adm1_pop_weight)) 
#   
#   
#   
  
  
  







