# Jeanette Tseng
# Created: 2020-03-14
# Description: read in tables from Sante publique France epidemiological update reports
# released every 1-3 days
# https://www.santepubliquefrance.fr/recherche/#search=COVID-19%20:%20point%20epidemiologique
# downloaded all PDFs and exported to Excel

# working directory = < GPL_covid > folder

library(tidyverse)
library(magrittr)
library(lubridate)

# List Excel versions of reports
epi_reports <- tibble(
  filename = list.files("data/raw/france") %>% 
    str_subset("^COVID19_PE_2020\\d{4}.xlsx")
) %>% 
  mutate(filedate = str_extract(filename, "\\d{8}") %>% ymd())

# Pull table 1 from each report which has stats on deaths and cases
table1 <- map(epi_reports$filename, function(fn){
  table <- openxlsx::read.xlsx(file.path("data/raw/france", fn), colNames = FALSE) %>% 
    mutate(table_start = if_else(str_detect(X1, "Tableau 1"), row_number()+1, NA_real_),
           table_end = if_else(X1=="Total Outre Mer", row_number(), NA_integer_)) %>% 
    fill(table_start, .direction = "updown") %>% 
    fill(table_end, .direction = "updown") %>% 
    filter(row_number()>=table_start & row_number()<=table_end) %>% 
    select(-c(table_start, table_end)) %>% 
    # drop empty columns
    dplyr::select_if(function(x) !all(is.na(x))) %>%
    mutate(date = epi_reports$filedate[epi_reports$filename==fn])
  
  if(unique(table$date)<"2020-03-10"){
    table %<>% set_colnames(c("var", "value", "date"))
  } else{
    table %<>% set_colnames(c("var", "cumulative_confirmed_cases", "icu_cases", "cumulative_deaths", "date"))
  }
}) %>% 
  bind_rows() %>% 
  # clean
  mutate(icu_cases = if_else(str_detect(var, "en réanimation"), str_extract(value, "^\\d+ ") %>% str_trim(), icu_cases),
         cumulative_deaths = if_else(var=="Dont décès", str_extract(value, "^\\d+ ") %>% str_trim(), cumulative_deaths)) %>% 
  filter(!str_detect(var, "Nombre |Exposition identifiée|Cas rattachés|démographiques|Sexe|Classes|ans|Région|Total ")) %>% 
  rename(adm1 = var) %>% 
  mutate(adm0 = "France",
         adm1 = if_else(str_detect(adm1, "^Dont "), NA_character_, adm1),
         cumulative_confirmed_cases = if_else(!str_detect(value, "%") & !is.na(value), value, cumulative_confirmed_cases)) %>% 
  group_by(adm0, adm1, date) %>% 
  mutate_at(vars(c("cumulative_confirmed_cases", "icu_cases", "cumulative_deaths")), as.numeric) %>% 
  summarise_at(vars(c("cumulative_confirmed_cases", "icu_cases", "cumulative_deaths")), ~sum(., na.rm = TRUE)) %>% 
  mutate_at(vars(c("icu_cases", "cumulative_deaths")), ~if_else(.==0 & date<"2020-03-10", NA_real_, .)) %>% 
  ungroup()

# calc national stats
all_france <- table1 %>% 
  filter(!is.na(adm1)) %>% 
  group_by(adm0, date) %>% 
  summarise_at(vars(c("cumulative_confirmed_cases", "icu_cases", "cumulative_deaths")), ~sum(., na.rm = TRUE)) %>% 
  ungroup() %>% 
  left_join(
    table1 %>% 
      filter(is.na(adm1)) %>% 
      select(adm0, date, icu_cases, cumulative_deaths),
    by = c("adm0", "date")) %>% 
  mutate(icu_cases = if_else(icu_cases.x==0, icu_cases.y, icu_cases.x),
         cumulative_deaths = if_else(cumulative_deaths.x==0, cumulative_deaths.y, cumulative_deaths.x)) %>% 
  select(-contains("."))
  
# combine regional and national stats
final <- table1 %>% 
  filter(!is.na(adm1)) %>% 
  bind_rows(all_france)

# output
write_csv(final, "data/interim/france/france_epi_cases_deaths_by_reg.csv")
