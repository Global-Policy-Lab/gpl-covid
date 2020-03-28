
#clean environment
rm(list = ls())

#load packages
library(dplyr)
library(magrittr)

# set working directory
dir <- "data/interim/korea/" 
pol.dir <- "data/raw/korea/"
template.dir <- "data/processed/"
output <- "adm1/KOR_processed.csv"

#load data
df <- read.csv(paste0(dir, "KOR_health.csv"), header = T, stringsAsFactors = F) #main health data manually collected
pop <- read.csv(paste0(dir, "KOR_population.csv"), header = T, stringsAsFactors = F)  #population data
pol <- read.csv(paste0(pol.dir, "KOR_policy_data_sources.csv"), header = T, stringsAsFactors = F)  #policy data
template <- read.csv(paste0(template.dir, '[country]_processed.csv'), header = T, stringsAsFactors = F)  #template data


#----------------------------------------------------------------------------------------------------------------------------
#convert date column
df$date <- as.Date(df$date, "%m/%d/%y")

#generate active cases column
df$active_cases <- df$cum_confirmed_cases - df$cum_recoveries - df$cum_deaths 

#merge pop data
df <- left_join(df, pop, by = c("adm1_name"))
rm(pop)

#rename policies that are optional
pol$policy <- ifelse(pol$optional=="Y", paste0(pol$policy,"_opt"), pol$policy)

#order policies
pol <- pol[order(pol$policy),]

#create variables
for (r in 1:NROW(pol$policy)){
  df[pol$policy[r]] <- 0 
}

#code policies according to date
for (p in 1:NROW(pol$policy)){
  
  print(paste0("coding for ", pol$policy[p], ", ", pol$date[p]))
  
  for (i in 1:nrow(df)){ 
    
    if(df$date[i]>= pol$date_start[p] & df$adm1_name[i] == pol$adm1_name[p]){ #province specific policies
    df[i, pol$policy[p]] <- 1
    }
    
    if(df$date[i]>= pol$date_start[p] & pol$adm1_name[p] == "All"){ #national policies
      df[i, pol$policy[p]] <- 1
    }
 
  }
  
}

# testing regimes
testing <- filter(pol, policy == "testing_regime")
df$testing_regime <- 0
for (t in 1:nrow(testing)){
df$testing_regime[df$date >= testing$date_start[t]]  <- t
}

# travel ban country list
df$travel_ban_intl_in_opt_country_list <- NA
intl_in <- filter(pol, policy == "travel_ban_intl_in") 
for (j in 1:nrow(intl_in)){
  df$travel_ban_intl_in_opt_country_list[df$travel_ban_intl_in == 1 & df$date >= intl_in$date_start[j]] <- intl_in$travel_ban_intl_in_country_list[j]
}

df$travel_ban_intl_out_opt_country_list <- NA
intl_out <- filter(pol, policy == "travel_ban_intl_out_opt") 
for (o in 1:nrow(intl_out)){
  df$travel_ban_intl_out_opt_country_list[df$travel_ban_intl_out_opt == 1 & df$date >= intl_out$date_start[o]] <- intl_out$travel_ban_intl_out_opt_country_list[o]
}

# Check that all columns are in template
stopifnot(names(df) %in% names(template)) 

#write csv
write.csv(df, paste0(template.dir, output), row.names = F)

