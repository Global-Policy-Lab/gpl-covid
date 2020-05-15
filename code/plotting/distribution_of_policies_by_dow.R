# look at number of policies enacted on specific day of week

library(tidyverse)
library(magrittr)
library(lubridate)
library(RColorBrewer)

# CHN----------------------------------------------------------------------------------------------------

chn_data <- read_csv("models/reg_data/CHN_reg_data.csv",                   
                     col_types = cols(
                       .default = col_double(),
                       adm0_name = col_character(),
                       adm1_name = col_character(),
                       adm2_name = col_character(),
                       date = col_date(format = ""),
                       t = col_character(),
                       adm2_id = col_character(),
                       adm1_id = col_character(),
                       adm1_adm2_name = col_character(),
                       day_avg = col_double()
                     )) %>% 
  arrange(adm1_name, adm2_name, date) %>% 
  # drop cities w/ no case info
  group_by(adm0_name, adm1_name, adm2_name, adm12_id) %>% 
  filter(sum(!is.na(active_cases))>0) %>% 
  # flag when policies are turned on
  select(adm0_name, adm1_name, adm2_name, adm12_id, date, dow, home_isolation, travel_ban_local, emergency_declaration) %>% 
  mutate_at(vars(c(home_isolation, travel_ban_local, emergency_declaration)), list(on = ~ . - lag(.))) %>% 
  filter((home_isolation_on + travel_ban_local_on + emergency_declaration_on)>0 & !is.na(home_isolation_on)) %>% 
  ungroup() %>% 
  # calc total number of cities that enacted policy by policy type and dow
  mutate(dow_factor = wday(date, label = TRUE)) %>% # stata dow is a number from 0-6
  group_by(adm0_name, dow, dow_factor) %>% 
  summarise_at(vars(ends_with("_on")), sum) %>% 
  ungroup() %>% 
  # reshape long
  pivot_longer(
    cols = ends_with("_on"),
    names_to = "policy",
    values_to = "n"
  ) %>% 
  mutate(policy = policy %>% 
           str_replace_all("_", " ") %>% 
           str_remove("on$") %>% str_remove("local") %>% 
           str_replace("^e", "E") %>% str_replace("^t", "T") %>% str_replace("^h", "H") %>% 
           str_trim(),
         policy_factor = factor(policy, levels = c("Emergency declaration", "Travel ban", "Home isolation")))

# KOR ----------------------------------------------------------------------------------------------------

kor_data <- read_csv("models/reg_data/KOR_reg_data.csv",
                     col_types = cols(
                       .default = col_double(),
                       adm0_name = col_character(),
                       adm1_name = col_character(),
                       date = col_date(format = ""),
                       adm1_id = col_character(),
                       t = col_character(),
                       travel_ban_intl_in_opt_country_l = col_character(),
                       travel_ban_intl_out_opt_country_ = col_character()
                     )) %>% 
  arrange(adm1_name, date) %>% 
  # flag when policies are turned on
  select(adm0_name, adm1_name, adm1_id, date, dow, 
         business_closure_opt, work_from_home_opt, social_distance_opt, no_gathering_opt, 
         no_demonstration, religious_closure, welfare_services_closure, 
         emergency_declaration, pos_cases_quarantine) %>% 
  group_by(adm0_name, adm1_name, adm1_id) %>% 
  mutate_at(vars(c(business_closure_opt, work_from_home_opt, social_distance_opt, no_gathering_opt, 
                   no_demonstration, religious_closure, welfare_services_closure, 
                   emergency_declaration, pos_cases_quarantine)), 
            list(on = ~ as.numeric((. - lag(.))>0))) %>% 
  ungroup() %>% 
  # calc total number of cities that enacted policy by policy type and dow
  mutate(dow_factor = wday(date, label = TRUE)) %>% # stata dow is a number from 0-6
  group_by(adm0_name, dow, dow_factor) %>% 
  summarise_at(vars(ends_with("_on")), sum, na.rm = TRUE) %>% 
  ungroup() %>% 
  # reshape long
  pivot_longer(
    cols = ends_with("_on"),
    names_to = "policy0",
    values_to = "n"
  ) %>% 
  # policy packages
  mutate(policy0 = str_remove(policy0, "_on"),
         policy = case_when(
           policy0 %in% c("business_closure_opt", "work_from_home_opt", "social_distance_opt", "no_gathering_opt") ~ "Social distance (optional)",
           policy0 %in% c("no_demonstration", "religious_closure", "welfare_services_closure") ~ "Social distance (mandatory)",
           policy0=="emergency_declaration" ~ "Emergency declaration",
           policy0=="pos_cases_quarantine" ~ "Quarantine positive cases",
         )) 

# ITA ----------------------------------------------------------------------------------------------------

ita_data <- read_csv("models/reg_data/ITA_reg_data.csv",
                     col_types = cols(
                       .default = col_double(),
                       adm0_name = col_character(),
                       adm1_name = col_character(),
                       adm2_name = col_character(),
                       date = col_date(format = ""),
                       adm1_id = col_character(),
                       adm2_id = col_character(),
                       t = col_character()
                     )) %>% 
  arrange(adm1_name, adm2_name, date) %>% 
  # flag when policies are turned on
  select(adm0_name, adm1_name, adm1_id, date, dow, 
         no_gathering_popwt, social_distance_opt_popwt, social_distance_popwt, work_from_home_opt_popwt, work_from_home_popwt, 
         school_closure_popwt, 
         travel_ban_local_popwt, transit_suspension_popwt, 
         pos_cases_quarantine_popwt,
         business_closure_popwt, 
         home_isolation_popwt) %>% 
  group_by(adm0_name, adm1_name, adm1_id) %>% 
  mutate_at(vars(c(no_gathering_popwt, social_distance_opt_popwt, social_distance_popwt, work_from_home_opt_popwt, work_from_home_popwt, 
                   school_closure_popwt, 
                   travel_ban_local_popwt, transit_suspension_popwt, 
                   pos_cases_quarantine_popwt,
                   business_closure_popwt, 
                   home_isolation_popwt)), 
            list(on = ~ as.numeric((. - lag(.))>0))) %>% 
  ungroup() %>% 
  # calc total number of cities that enacted policy by policy type and dow
  mutate(dow_factor = wday(date, label = TRUE)) %>% # stata dow is a number from 0-6
  group_by(adm0_name, dow, dow_factor) %>% 
  summarise_at(vars(ends_with("_on")), sum, na.rm = TRUE) %>% 
  ungroup() %>% 
  # reshape long
  pivot_longer(
    cols = ends_with("_on"),
    names_to = "policy",
    values_to = "n"
  ) 

# IRN ----------------------------------------------------------------------------------------------------

irn_data <- read_csv("models/reg_data/IRN_reg_data.csv",
                     col_types = cols(
                       .default = col_double(),
                       adm0_name = col_character(),
                       adm1_name = col_character(),
                       date = col_date(format = ""),
                       adm1_id = col_character(),
                       t = col_character()
                     )) %>% 
  arrange(adm1_name, date) %>% 
  # flag when policies are turned on
  select(adm0_name, adm1_name, adm1_id, date, dow, 
         travel_ban_local_opt, work_from_home, school_closure, 
         home_isolation) %>% 
  group_by(adm0_name, adm1_name, adm1_id) %>% 
  mutate_at(vars(c(travel_ban_local_opt, work_from_home, school_closure, 
                   home_isolation)), 
            list(on = ~ as.numeric((. - lag(.))>0))) %>% 
  ungroup() %>% 
  # calc total number of cities that enacted policy by policy type and dow
  mutate(dow_factor = wday(date, label = TRUE)) %>% # stata dow is a number from 0-6
  group_by(adm0_name, dow, dow_factor) %>% 
  summarise_at(vars(ends_with("_on")), sum, na.rm = TRUE) %>% 
  ungroup() %>% 
  # reshape long
  pivot_longer(
    cols = ends_with("_on"),
    names_to = "policy",
    values_to = "n"
  ) 

# FRA ----------------------------------------------------------------------------------------------------

fra_data <- read_csv("models/reg_data/FRA_reg_data.csv",
                     col_types = cols(
                       .default = col_double(),
                       adm0_name = col_character(),
                       adm1_name = col_character(),
                       date = col_date(format = "")
                     )) %>% 
  arrange(adm1_name, date) %>% 
  # flag when policies are turned on
  select(adm0_name, adm1_name, adm1_id, date, dow, 
         no_gathering_1000, no_gathering_100, event_cancel_popwt, no_gathering_inside_popwt, social_distance_popwt,
         school_closure_popwt, business_closure, home_isolation_popwt) %>% 
  group_by(adm0_name, adm1_name, adm1_id) %>% 
  mutate_at(vars(c(no_gathering_1000, no_gathering_100, event_cancel_popwt, no_gathering_inside_popwt, social_distance_popwt,
                   school_closure_popwt, business_closure, home_isolation_popwt)), 
            list(on = ~ as.numeric((. - lag(.))>0))) %>% 
  ungroup() %>% 
  # calc total number of cities that enacted policy by policy type and dow
  mutate(dow_factor = wday(date, label = TRUE)) %>% # stata dow is a number from 0-6
  group_by(adm0_name, dow, dow_factor) %>% 
  summarise_at(vars(ends_with("_on")), sum, na.rm = TRUE) %>% 
  ungroup() %>% 
  # reshape long
  pivot_longer(
    cols = ends_with("_on"),
    names_to = "policy",
    values_to = "n"
  ) 

# USA ----------------------------------------------------------------------------------------------------

usa_data <- read_csv("models/reg_data/USA_reg_data.csv",
                     col_types = cols(
                       .default = col_double(),
                       adm0_name = col_character(),
                       adm1_name = col_character(),
                       date = col_date(format = ""),
                       adm1_id = col_character(),
                       adm1_abb = col_character(),
                       t = col_character()
                     )) %>% 
  arrange(adm1_name, date) %>% 
  # flag when policies are turned on
  select(adm0_name, adm1_name, adm1_id, date, dow, 
         no_gathering_popwt, social_distance_popwt, 
         pos_cases_quarantine_popwt, paid_sick_leave_popwt,
         work_from_home_popwt, school_closure_popwt,
         travel_ban_local_popwt, transit_suspension_popwt,
         business_closure_popwt, religious_closure_popwt,
         home_isolation_popwt,
         federal_guidelines) %>% 
  group_by(adm0_name, adm1_name, adm1_id) %>% 
  mutate_at(vars(c(no_gathering_popwt, social_distance_popwt, 
                   pos_cases_quarantine_popwt, paid_sick_leave_popwt,
                   work_from_home_popwt, school_closure_popwt,
                   travel_ban_local_popwt, transit_suspension_popwt,
                   business_closure_popwt, religious_closure_popwt,
                   home_isolation_popwt,
                   federal_guidelines)), 
            list(on = ~ as.numeric((. - lag(.))>0))) %>% 
  ungroup() %>% 
  # calc total number of cities that enacted policy by policy type and dow
  mutate(dow_factor = wday(date, label = TRUE)) %>% # stata dow is a number from 0-6
  group_by(adm0_name, dow, dow_factor) %>% 
  summarise_at(vars(ends_with("_on")), sum, na.rm = TRUE) %>% 
  ungroup() %>% 
  # reshape long
  pivot_longer(
    cols = ends_with("_on"),
    names_to = "policy",
    values_to = "n"
  ) 


# COMBINE ----------------------------------------------------------------------------------------------------

combined <- bind_rows(
  chn_data %>% mutate(country = "China") %>% select(-policy_factor),
  kor_data %>% mutate(country = "South Korea") %>% select(-policy) %>% rename(policy = policy0),
  ita_data %>% mutate(country = "Italy"),
  irn_data %>% mutate(country = "Iran"),
  fra_data %>% mutate(country = "France"),
  usa_data %>% mutate(country = "United States")
) %>% 
  mutate(Policy = policy %>% 
           str_to_lower() %>% 
           str_replace_all("_", " ") %>% 
           str_remove_all(" on|opt|local|\\d|inside|popwt") %>% 
           str_trim() %>% 
           str_replace("federal guidelines", "US federal guidelines"))

unique(combined$policy) %>% sort()

# create color palette
pal <- colorRampPalette(brewer.pal(11, "RdYlBu"))(16)

# by policy and country
combined %>% 
  group_by(country, Policy, dow_factor) %>% 
  summarise(n = sum(n, na.rm = TRUE)) %>% 
  mutate(n = if_else(n==0, NA_real_, n)) %>% 
ggplot(aes(dow_factor, n, fill = Policy)) + 
  geom_col(position = position_stack(reverse = TRUE)) +
  # geom_text(aes(label = n), size = 4, position = position_stack(vjust = 0.5, reverse = TRUE)) +
  labs(title = "Policy deployment by day of week",
       x = "Day of week", y = "Number of administrative units") +
  scale_fill_manual(values = pal) +
  facet_wrap(country ~ ., scales = "free") +
  theme_bw()


# total policy count by dow and country
tot_policy_ct <- combined %>% 
  group_by(country, dow, dow_factor) %>% 
  summarise(n = sum(n)) %>% 
  ungroup() %>% 
  group_by(country) %>% 
  mutate(pct = n / sum(n))

# conduct chi-sq test to see if each dow is equally common
# http://www.sthda.com/english/wiki/chi-square-goodness-of-fit-test-in-r
chisq_results <- map(unique(tot_policy_ct$country), function(c){
  observed <- tot_policy_ct %>% 
    filter(country==c) %>% 
    pull(n)
  
  results <- chisq.test(x = observed, p = rep(1/7, 7))
  
  tibble(
    country = c,
    chi_sq = results[[1]],
    p_val = results[[3]],
  )
}) %>% 
  bind_rows()

