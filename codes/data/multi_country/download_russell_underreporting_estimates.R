suppressPackageStartupMessages(library(tidyverse))
cfr_data <- read_rds(url("https://github.com/thimotei/CFR_calculation/blob/master/global_estimates/data/reportDataFinal.rds?raw=true", "rb"))

cfr_data <- cfr_data %>% 
  filter(country %>% str_detect("United States|South Korea|China|France|Italy|Iran"))

dir.create("data/interim/multi_country/", showWarnings = FALSE)
write_csv(cfr_data, "data/interim/multi_country/under_reporting.csv")
