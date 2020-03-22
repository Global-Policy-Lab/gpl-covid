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

fn <- "data/processed/adm1/USA_processed.csv"
names_order <- read_csv("data/processed/[country]_processed.csv", 
                        col_types = cols(.default = col_character())) %>% names()
data <- read_csv(fn, 
                 col_types = cols(
                   .default = col_double(),
                   date = col_date(format = ""),
                   adm0_name = col_character(),
                   adm1_name = col_character()
                 )
)
setdiff(names(data), names_order)
# does the dataset remove cases below 10?

issues <- data %>% 
  filter(cum_confirmed_cases >= 10) %>% 
  unite(tmp_id, adm0_name, adm1_name) %>% 
  examine_issues(cum_confirmed_cases) %>% 
  select(date, tmp_id, cum_confirmed_cases)
if(issues %>% nrow() %>% is_greater_than(0)){
  issue_found <- TRUE
  message(paste0("ISSUE: Examples of declines in cumulative_confirmed_cases in ",fn," after running filter(cumulative_confirmed_cases >= 10):"))
  print(issues)
}

if(!issue_found){
  message(paste0("NO ISSUES FOUND WITH HEALTH DATA IN \"", fn, "\" NICE!"))
}
