# JT
# Created: 2020-03-14; Updated: 2020-03-16 so it pulls both table titles and uses the latest date
# Description: scrape table of confirmed cases by region in France (updates daily)

# working directory = < GPL_covid > folder

library(tidyverse)
library(rvest)
library(lubridate)

url <- 'https://www.santepubliquefrance.fr/maladies-et-traumatismes/maladies-et-infections-respiratoires/infection-a-coronavirus/articles/infection-au-nouveau-coronavirus-sars-cov-2-covid-19-france-et-monde'
webpage <- read_html(url)

# Pull title with date and time
title1 <- webpage %>% 
  html_nodes('h2') %>% 
  html_text() %>% 
  str_subset("Nombre")

title2 <- webpage %>% 
  html_nodes('h4') %>% 
  html_text() %>% 
  str_subset("Nombre")

# Since scraping is scheduled to run daily,
# use the latest date from table titles
datetime_update1 <- dmy_h(paste(str_extract(title1, "\\d{2}/\\d{2}/\\d{4}"), str_extract(title1, "[0-9][0-9]?h")))
datetime_update2 <- dmy_h(paste(str_extract(title2, "\\d{2}/\\d{2}/\\d{4}"), str_extract(title2, "[0-9][0-9]?h")))
datetime_update <- max(datetime_update1, datetime_update2)

# Pull table headers
header <- webpage %>% 
  html_nodes('th') %>% 
  html_text()

# Pull all table text
# (Region and Case numbers)
table_text <- webpage %>% 
  html_nodes('td') %>% 
  html_text()

# Combine date/time, header, and table text
table <- tibble(
  adm1_name = str_subset(table_text, "[a-z]"),
  cumulative_confirmed_cases = str_subset(table_text, "\\d") %>% str_remove_all(" |\\*") # *** for footnotes
) %>% 
  mutate(cumulative_confirmed_cases = as.numeric(cumulative_confirmed_cases),
         datetime_update = datetime_update,
         date = as_date(datetime_update),
         datetime_download = now(),
         adm0_name = "France")

# Output
write_csv(table, 
          paste0("data/raw/france/france_confirmed_cases_by_region_", 
                 unique(table$date) %>% str_remove_all("-"), ".csv"))
