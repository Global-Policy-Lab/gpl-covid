#!/usr/bin/env Rscript
args = commandArgs(trailingOnly=TRUE)

if(length(args) > 0){
  times <- strtoi(args)
} else {
  times = 1000  
}

# Full script to run R code for projection:
suppressPackageStartupMessages(library(tidyverse))
suppressPackageStartupMessages(library(lfe))
set.seed(718)

underreporting <- read_csv("data/interim/multi_country/under_reporting.csv",
                           col_types = cols(
                             country = col_character(),
                             total_cases = col_double(),
                             total_deaths = col_double(),
                             underreporting_estimate = col_double(),
                             lower = col_double(),
                             upper = col_double(),
                             underreporting_estimate_clean = col_character()
                           ))
gamma = readr::read_csv("models/gamma_est.csv",
                        col_types = 
                          cols(
                            recovery_delay = col_double(),
                            gamma = col_double()
                          )) %>% 
  filter(adm0_name %in% c("CHN", "KOR"), recovery_delay == 0) %>% 
  pull(gamma) %>% 
  mean()

dir.create("models/projections", recursive=TRUE, showWarnings=FALSE)
message("Running France projection.")
source("code/models/FRA_create_CBs.R")
message("Running Iran projection.")
source("code/models/IRN_create_CBs.R")
message("Running South Korea projection.")
source("code/models/KOR_create_CBs.R")
message("Running USA projection.")
source("code/models/USA_create_CBs.R")
message("Running China projection.")
source("code/models/CHN_create_CBs.R")
message("Running Italy projection.")
source("code/models/ITA_create_CBs.R")
