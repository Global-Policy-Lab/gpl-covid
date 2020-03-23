# Emma Krasovich, ekrasovich@berkeley.edu
# Date: 3/15/20 | updated: 3/23/20
# description: cleaning up school closure data from covid19
# source: 

# load libraries
library(tidyverse)
library(dplyr)
library(stringr)
library(purrr)
library(readxl) # use to open/read excel files

# NOTE: set up the working directory as the github environment


# NOTE: this school closures data comes from: https://www.edweek.org/ew/section/multimedia/map-coronavirus-and-school-closures.html
# last downloaded: 3/23/20

# source the school closures data:
school_closures <- readxl::read_xlsx("gpl-covid/data/raw/usa/coronavirus-school-closures-data.xlsx", skip = 1, sheet = "Districts") %>% 
  rename(adm1_name = 'State',
         adm3_name = 'City',
         dates_closed = `Dates Closed`,
         ) %>% 
  dplyr::select(adm1_name, adm3_name, dates_closed) %>% 
  #select only the non-missing city names
  filter(!is.na(adm3_name)) 

# now clean up the dates
US_school_closures_clean <- school_closures %>% 
  mutate(date_closed = str_split(dates_closed, " ") %>% map(1) %>% unlist()) %>%
  mutate(date_closed = ifelse(date_closed == 'Closed', NA, date_closed)) %>% 
  mutate(date_closed2 = str_split(dates_closed, " ", simplify = TRUE)[,2]) %>% 
  mutate(date_closed = ifelse(is.na(date_closed), date_closed2, date_closed)) %>% 
  mutate(date_closed3 = str_split(dates_closed, " ", simplify = TRUE)[,3]) %>% 
  mutate(date_closed = ifelse(date_closed == 'starting', NA, date_closed)) %>% 
  mutate(date_closed = ifelse(is.na(date_closed), date_closed3, date_closed)) %>% 
  mutate(date_closed = as.Date(date_closed, format = "%m/%d/%Y")) %>% 
  dplyr::select(-date_closed2, -date_closed3, -dates_closed) %>% 
  mutate(source = "https://www.edweek.org/ew/section/multimedia/map-coronavirus-and-school-closures.html",
         policy = "school_closure",
         access_date = file.mtime("data/raw/usa/coronavirus-school-closures-data.xlsx")) %>% 
  mutate(access_date = as.Date(access_date, format="%Y %m %d"),
         Optional = "N")

# save population file out to the interim folder, this will be merged w/ the raw policy data
write_csv(US_school_closures_clean, "gpl-covid/data/interim/usa/US_school_closures_clean.csv")


