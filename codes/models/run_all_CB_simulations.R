# Full script to run R code for projection:
suppressPackageStartupMessages(library(tidyverse))
suppressPackageStartupMessages(library(lfe))
set.seed(718)
times = 1000
underreporting <- read_rds("data/interim/multi_country/under_reporting.rds")
# source("codes/models/calculate_gamma_from_china_and_korea.R")
gamma = readr::read_csv("models/gamma_est.csv",
                        col_types = 
                          cols(
                            adm0_name = col_character(),
                            gamma_est = col_double()
                          )) %>% 
  filter(adm0_name %in% c("CHN", "KOR")) %>% 
  pull(gamma_est) %>% 
  mean()

dir.create("data/post_processing", recursive=TRUE, showWarnings=FALSE)
message("Running France projection.")
source("codes/models/FRA_create_CBs.R")
message("Running Iran projection.")
source("codes/models/IRN_create_CBs.R")
message("Running South Korea projection.")
source("codes/models/KOR_create_CBs.R")
message("Running USA projection.")
source("codes/models/USA_create_CBs.R")
message("Running China projection.")
source("codes/models/CHN_create_CBs.R")
message("Running Italy projection.")
source("codes/models/ITA_create_CBs.R")
