
#clean environment
rm(list = ls())

#load packages
library(dplyr)
library(magrittr)

# set working directory
dir <- "data/interim/korea/" 
outputname <- "KOR_interim"

#load data
df <- read.csv(paste0(dir, "KOR_health.csv"), header = T, stringsAsFactors = F) #main health data manually collected
pop <- read.csv(paste0(dir, "KOR_population.csv"), header = T, stringsAsFactors = F)  #population data

#----------------------------------------------------------------------------------------------------------------------------

#generate active cases column
df$active_cases <- df$cumulative_confirmed_cases - df$cumulative_recoveries - df$cumulative_deaths #calculate active cases

#merge pop data
df <- left_join(df, pop, by = c("adm1_name"))

#add policies
# travel_ban_intl_in_opt
df$travel_ban_intl_in_opt <- 0
df$travel_ban_intl_in_opt[df$date >= as.Date("2020-01-28")] <- 1 

# travel_ban_intl_in_opt_country_list
df$travel_ban_intl_in_opt_country_list <- NA
df$travel_ban_intl_in_opt_country_list[df$date >= as.Date("2020-01-28")] <- "['China']"
df$travel_ban_intl_in_opt_country_list[df$date >= as.Date("2020-02-12")] <- "['China', 'Hongkong', 'Macau']"
df$travel_ban_intl_in_opt_country_list[df$date >= as.Date("2020-03-11")] <- "['China', 'Hongkong', 'Macau', 'Italy', 'Iran']"
df$travel_ban_intl_in_opt_country_list[df$date >= as.Date("2020-03-15")] <- "['China', 'Hongkong', 'Macau', 'Italy', 'Iran', 'France', 'Germany', 'Spain', 'UK', 'Netherlands']"
df$travel_ban_intl_in_opt_country_list[df$date >= as.Date("2020-03-16")] <- "['China', 'Hongkong', 'Macau', 'Italy', 'Iran', 'All Europe']"

# travel_ban_intl_out_opt
df$travel_ban_intl_out_opt <- 0
df$travel_ban_intl_out_opt[df$date >= as.Date("2020-01-28")] <- 1 

# travel_ban_intl_out_opt_country_list
df$travel_ban_intl_out_opt_country_list <- NA
df$travel_ban_intl_out_opt_country_list[df$date >= as.Date("2020-01-28")] <- "['China', 'Hongkong', 'Macau']"

# emergency_declaration
df$emergency_declaration <- 0
df$emergency_declaration[df$date >= as.Date("2020-03-15") & df$adm1_name == "Daegu"] <- 1 
df$emergency_declaration[df$date >= as.Date("2020-03-15") & df$adm1_name == "Gyeongsangbuk-do"] <- 1 

# school_closure
df$school_closure <- 1 
df$school_closure[df$date >= as.Date("2020-03-02")] <- 1 

# business_closure
df$business_closure <- 0
df$business_closure[df$date >= as.Date("2020-02-28") & df$adm1_name %in% c("Busan", "Chungcheongbuk-do", "Daegu", "Daejeon", "Gangwon-do", "Gwangju", "Gyeonggi-do",
                                                                           "Gyeongsangbuk-do", "Incheon", "Jeju", "Jeollabuk-do", "Jeollanam-do", "Sejong", 
                                                                           "Seoul", "Ulsan")] <- 1 
# travel_advisory_outbound_optional
df$travel_advisory_outbound_optional <- 0
df$travel_advisory_outbound_optional[df$date >= as.Date("2020-02-13")] <- 1 

# social_distance_optional
df$social_distance_optional <- 0
df$social_distance_optional[df$date >= as.Date("2020-02-22") & df$adm1_name == "Daegu"] <- 1 
df$social_distance_optional[df$date >= as.Date("2020-02-29")] <- 1 

# work_from_home_optional
df$work_from_home_optional <- 0
df$work_from_home_optional[df$date >= as.Date("2020-03-11")] <- 1 

# define testing regime
df$testing_regime <- 0
df$testing_regime[df$date >= as.Date("2020-01-28")] <- 1 

# no demonstration
df$no_demonstration <- 0
df$no_demonstration[df$date >= as.Date("2020-03-06") & df$adm1_name == "Daegu"] <- 1 
df$no_demonstration[df$date >= as.Date("2020-02-24") & df$adm1_name == "Incheon"] <- 1 
df$no_demonstration[df$date >= as.Date("2020-02-21") & df$adm1_name == "Seoul"] <- 1 

# shutdown_religious_places
df$shutdown_religious_places <- 0
df$shutdown_religious_places[df$date >= as.Date("2020-02-26") & df$adm1_name %in% c("Busan", "Chungcheongbuk-do","Jeollabuk-do")] <- 1 
df$shutdown_religious_places[df$date >= as.Date("2020-02-18") & df$adm1_name == "Daegu"] <- 1 
df$shutdown_religious_places[df$date >= as.Date("2020-02-28") & df$adm1_name == "Daejeon"] <- 1 
df$shutdown_religious_places[df$date >= as.Date("2020-02-22") & df$adm1_name == "Gangwon-do"] <- 1 
df$shutdown_religious_places[df$date >= as.Date("2020-02-27") & df$adm1_name == "Gwangju"] <- 1 
df$shutdown_religious_places[df$date >= as.Date("2020-02-19") & df$adm1_name == "Gyeongsangbuk-do"] <- 1 
df$shutdown_religious_places[df$date >= as.Date("2020-02-23") & df$adm1_name == "Jeju"] <- 1 
df$shutdown_religious_places[df$date >= as.Date("2020-02-24") & df$adm1_name %in% c("Jeollanam-do", "Gyeonggi-do")] <- 1 
df$shutdown_religious_places[df$date >= as.Date("2020-02-25") & df$adm1_name %in% c("Incheon", "Ulsan")] <- 1 
df$shutdown_religious_places[df$date >= as.Date("2020-02-21") & df$adm1_name == "Seoul"] <- 1 

# business_closure_optional
df$business_closure_optional <- 0
df$business_closure_optional[df$date >= as.Date("2020-03-18") & df$adm1_name == "Gyeonggi-do"] <- 1 
df$business_closure_optional[df$date >= as.Date("2020-03-11") & df$adm1_name == "Seoul"] <- 1 
  
#order variables
df <- select(df, adm1_name, 
               date,
               adm0_name,
               cumulative_confirmed_cases,
               cumulative_deaths,
               cumulative_recoveries,
               active_cases,
               travel_ban_intl_in_opt,
               travel_ban_intl_in_opt_country_list, 
               travel_ban_intl_out_opt,
               travel_ban_intl_out_opt_country_list,
               emergency_declaration,
               school_closure, 
               business_closure,
               travel_advisory_outbound_optional,
               social_distance_optional,
               work_from_home_optional,
               testing_regime,
               no_demonstration,
               shutdown_religious_places,
               business_closure_optional,
               population)

write.csv(df, paste0(dir, outputname, ".csv"), row.names = F)
