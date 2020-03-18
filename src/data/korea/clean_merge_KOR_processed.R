# COVID-19

# This script cleans up & joins health data to policy data to output KOR_processed.csv
# Country: South Korea

# Dependencies
# 1a) Health (province-level): South_Korea_province_mortality_20200314_share.csv
# 1b) Recoveries (province-level): South_Korea_province_recovery_20200317_share.csv
# 2) Policy (currently national & province level): https://www.dropbox.com/scl/fi/wgm41o2bc4z7sdq8qjnde/policy_korea.gsheet?dl=0&rlkey=ywuwvqy321vxpg82k2bsif8jj#gid=1500676384
# Data dictionary: https://www.dropbox.com/scl/fi/p1n46gfmpszijmj6nsdtl/data_dictionary.gsheet?dl=0&rlkey=3ckx65br3vbkz7fjvjkw3i40f#gid=0
# Adm1_name Key: district_list_eng_name.csv

# Updated: 17 Mar 2020
# Jaecheol & Trin 

#----------------------------------------------------------------------------------------------------------------------------

#clean environment
rm(list = ls())

#load packages
library(dplyr)
library(magrittr)
library(ggplot2)

impute <- T #impute recoveries before 6 Mar?

# set working directory
dir <- "/Users/trinettachong/Dropbox/Aerial_Photos/covid/" 
outputname <- "KOR_processed"

#load data
df <- read.csv(paste0(dir, "South_Korea_province_mortality_20200314_share.csv"), header = T, stringsAsFactors = F) #main health data
jhu <-  read.csv(paste0(dir, "korea_jhu_cases.csv"), header = T, stringsAsFactors = F) #jhu dataset
recovery <- read.csv(paste0(dir, "South_Korea_province_recovery_20200317_share.csv"), header = T, stringsAsFactors = F) #cumulative recoveries
eng <- read.csv(paste0(dir, "district_list_eng_name.csv"), header = T, stringsAsFactors = F) %>% #english string names
  select(adm1_code, adm1_name = prov_name_eng) %>%
  unique()

#----------------------------------------------------------------------------------------------------------------------------
#set col names
names(df) <- c("adm1_code", "date", "daily_count", "cumulative_confirmed_cases", "daily_count_mortality", "cumulative_deaths", "adm1_korean", "adm0_name")

df <- left_join(df, eng, by = "adm1_code") %>%  #merge english name
      left_join(recovery, by = c("date", "adm1_name")) #merge recoveries

df$adm0_name <- "KOR" #change labeling to iso code
df$adm1_name[df$adm1_name =="sejong" ] <- "Sejong"

if(impute){ #impute values for recoveries before 6 Mar
  

  outputname <- paste0(outputname,"_imputed")
}

df$active_cases <- df$cumulative_confirmed_cases - df$cumulative_recoveries - df$cumulative_deaths #calculate active cases

# define testing regime
df$testing_regime <- 0
df$testing_regime[df$date >= as.Date("2020-01-28")] <- 1 
df$testing_regime[df$date >= as.Date("2020-02-04")] <- 2 
df$testing_regime[df$date >= as.Date("2020-02-07")] <- 3 
df$testing_regime[df$date >= as.Date("2020-02-08")] <- 4 
df$testing_regime[df$date >= as.Date("2020-02-20")] <- 5 
df$testing_regime[df$date >= as.Date("2020-02-29")] <- 6 

#add policies
# travel_ban_international_inbound
df$travel_ban_international_inbound <- 0
df$travel_ban_international_inbound[df$date >= as.Date("2020-01-28")] <- 1 

# travel_ban_country_list
df$travel_ban_country_list <- NA
df$travel_ban_country_list[df$date >= as.Date("2020-01-28")] <- "['China']"
df$travel_ban_country_list[df$date >= as.Date("2020-02-12")] <- "['China', 'Hongkong', 'Macau']"
df$travel_ban_country_list[df$date >= as.Date("2020-03-11")] <- "['China', 'Hongkong', 'Macau', 'Italy', 'Iran']"
df$travel_ban_country_list[df$date >= as.Date("2020-03-15")] <- "['China', 'Hongkong', 'Macau', 'Italy', 'Iran', 'France', 'Germany', 'Spain', 'UK', 'Netherlands']"
df$travel_ban_country_list[df$date >= as.Date("2020-03-16")] <- "['China', 'Hongkong', 'Macau', 'Italy', 'Iran', 'All Europe']"

# travel_advisory_outbound_optional
df$travel_advisory_outbound_optional <- 0
df$travel_advisory_outbound_optional[df$date >= as.Date("2020-02-13")] <- 1 

# emergency_declaration
df$emergency_declaration <- 0
df$emergency_declaration[df$date >= as.Date("2020-02-19") & df$adm1_name == "Daegu"] <- 1 
df$emergency_declaration[df$date >= as.Date("2020-03-05") & df$adm1_name == "Gyeongsangbuk-do"] <- 1 

# social_distance_optional
df$social_distance_optional <- 0
df$social_distance_optional[df$date >= as.Date("2020-02-22") & df$adm1_name == "Daegu"] <- 1 
df$social_distance_optional[df$date >= as.Date("2020-02-29")] <- 1 

# school_closure
df$school_closure <- 0
df$school_closure[df$date >= as.Date("2020-03-02")] <- 1 

# work_from_home_optional
df$work_from_home_optional <- 0
df$work_from_home_optional[df$date >= as.Date("2020-03-11")] <- 1 

# business_closure
df$business_closure <- 0
df$business_closure[df$date >= as.Date("2020-03-12")] <- 1 

#select & order variables
df <- select(df, date,
             adm0_name,
             adm1_name,
             #adm1_korean,
             cumulative_confirmed_cases,
             cumulative_deaths,
             cumulative_recoveries,
             active_cases,
             travel_ban_international_inbound,
             travel_ban_country_list, 
             emergency_declaration,
             school_closure, 
             business_closure,
             travel_advisory_outbound_optional, 
             social_distance_optional,
             work_from_home_optional,
             #cumulative_estimated_cases,
             #cumulative_tests,
             #new_cases = daily_count,
             #new_deaths = daily_count_mortality,
             #adm0_cumulative_recoveries,
             testing_regime)


write.csv(df, paste0(dir, outputname, ".csv"), row.names = F)


# adm <- read.csv(paste0(dir, "adm.csv"), header = T, stringsAsFactors = F) %>% #load standardized names & latlon
#       filter(adm0_name=="KOR") %>%
#       select(adm1_name, latitude, longitude)

# add missing variables anyway
# df$cumulative_estimated_cases <- NA
# df$cumulative_tests <- NA

#----------------------------------------------------------------------------------------------------------------------------
#plot JHU against local data as sanity check

#aggreate provinces to country level
plot <- aggregate(list(cumulative_confirmed_cases = df$cumulative_confirmed_cases, cumulative_deaths = df$cumulative_deaths), by = list(df$date), FUN = sum) 
plot$cumulative_recoveries <- df$adm0_cumulative_recoveries[1:55]
plot$source <- "Korean local govt"
names(plot) <- c("date", "cumulative_confirmed_cases", "cumulative_deaths", "cumulative_recoveries", "source")

#JHU data
jhu$source <- "JHU"
jhu <- select(jhu, date, cumulative_confirmed_cases, cumulative_deaths, cumulative_recoveries, source)

plot <- rbind(plot, jhu) #combine data
plot$date <- as.POSIXct(plot$date, format="%Y-%m-%d") #set date format
plot$cumulative_recoveries <- as.numeric(plot$cumulative_recoveries) #set char to num

# write function to plot
plottimeseries <- function(y.var){
  plotting <- plot
  plotting['mainvar'] <- plotting[y.var]
  ggplot(data = plotting) +
  geom_line(aes(x=date, y=mainvar, color = source), alpha = 1, size=2) + #prov
  scale_colour_manual(name="Source:", 
                      breaks=c("Korean local govt", "JHU"),  
                      values=c("Korean local govt"="grey30", "JHU"="grey80")) +
  theme_minimal() +
  theme(panel.grid.major = element_blank(), 
        panel.grid.minor = element_blank(),
        panel.background = element_blank(), 
        axis.line = element_line(colour = "black")) +
  xlab("date") + ylab(y.var) +
  ggtitle(paste0("KOR ", y.var)) 
rm(plotting)
ggsave(file = paste0(dir, y.var, ".png"), width = 8, height = 6)
}

#use function
plottimeseries("cumulative_confirmed_cases")
plottimeseries("cumulative_deaths")
plottimeseries("cumulative_recoveries")

#---------------------------------------------------------------------------------------
# #export for recoveries
# df.recoveries <- select(df, date,
#              adm1_name,
#              cumulative_confirmed_cases,
#              cumulative_deaths)
# 
# df.recoveries <- df.recoveries[order(df.recoveries$date),]
# write.csv(df.recoveries, paste0(dir, "South_Korea_province_recovery_20200317_share.csv"), row.names = F)



