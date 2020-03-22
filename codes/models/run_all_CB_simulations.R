# Full script to run R code for projection:
library(tidyverse)
library(lfe)
set.seed(718)
times = 1000
# source("codes/models/calculate_gamma_from_china_and_korea.R")
gamma = readr::read_csv("models/gamma_est.csv") %>% 
  filter(adm0_name %in% c("CHN", "KOR")) %>% 
  pull(gamma_est) %>% 
  mean()

source("codes/models/FRA_create_CBs.R")
source("codes/models/IRN_create_CBs.R")
source("codes/models/KOR_create_CBs.R")
source("codes/models/USA_create_CBs.R")
source("codes/models/CHN_create_CBs.R")
source("codes/models/ITA_create_CBs.R")
