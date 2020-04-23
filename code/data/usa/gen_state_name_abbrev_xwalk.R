# create crosswalk between state name and abbreviation

library(tidyverse)

crosswalk <- tibble(
  adm1_name = state.name,
  adm1_abb = state.abb
) %>% 
  bind_rows(
    tibble(
      adm1_name = "District of Columbia",
      adm1_abb = "DC"
    )
  )

write.csv(crosswalk, "data/raw/usa/state_name_abbrev_xwalk.csv", row.names = FALSE)