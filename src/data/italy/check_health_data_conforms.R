suppressPackageStartupMessages(library(tidyverse, warn.conflicts = FALSE, quietly = TRUE))
suppressPackageStartupMessages(library(magrittr, warn.conflicts = FALSE, quietly = TRUE))

names_order <- read_csv("data/processed/[country]_processed.csv", 
                        col_types = cols(.default = col_character())) %>% names()
issue_found <- FALSE
examine_issues <- function(data, variable){
  data %>% 
    arrange(tmp_id, date) %>% 
    group_by(tmp_id) %>% 
    filter({{variable}} < lag({{variable}}) | {{variable}} > lead({{variable}}) | lead({{variable}}) > lead({{variable}}, 2))
}

fn <- "data/processed/adm1/ITA_processed.csv"
data <- read_csv(fn,
                       col_types = cols(
                         .default = col_double(),
                         date = col_date(format = ""),
                         adm0_name = col_character(),
                         adm1_name = col_character(),
                         adm2_name = col_logical(),
                         adm3_name = col_logical(),
                         time = col_time(format = "")
                       ))

# does the dataset remove cases below 10?
test <- data %>% 
  filter(cumulative_confirmed_cases < 10) %>% 
  nrow() %>% 
  equals(0)
if(!test){
  issue_found <- TRUE
  message(paste0("ISSUE: ", fn, " data contains cumulative_confirmed_cases < 10"))
}

minimum_names_required_for_health <- 
  names_order %>% str_subset("^date$|^adm|^cumulative_confirmed_cases(_with_imputations)?$")

missing_min_names <- setdiff(minimum_names_required_for_health, data %>% names())

if(length(missing_min_names) > 0){
  issue_found <- TRUE
  message(paste0("ISSUE: Missing required names: \"", paste0(missing_min_names, collapse = "\", \""),"\" in ", fn))
}

issues <- data %>% 
  filter(cumulative_confirmed_cases >= 10) %>% 
  unite(tmp_id, adm0_name, adm1_name, adm2_name) %>% 
  examine_issues(cumulative_confirmed_cases) %>% 
  select(date, tmp_id, cumulative_confirmed_cases)
if(issues %>% nrow() %>% is_greater_than(0)){
  issue_found <- TRUE
  message(paste0("ISSUE: Examples of declines in cumulative_confirmed_cases in ",fn," after running filter(cumulative_confirmed_cases >= 10):"))
  print(issues)
}

if(!issue_found){
  message(paste0("NO ISSUES FOUND WITH HEALTH DATA IN \"", fn, "\" NICE!"))
}