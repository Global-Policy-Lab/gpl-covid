##############################
##  Figure 1: Data Display  ##
##############################

# Updated 4/12/2020
# by hdruckenmiller

rm(list=ls())
options (warn = -1)
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(rgdal))
suppressPackageStartupMessages(library(rgeos))
suppressPackageStartupMessages(library(scales))
suppressPackageStartupMessages(library(magrittr))
suppressPackageStartupMessages(library(ggplot2))
suppressPackageStartupMessages(library(tigris))

##########################

# SET UP 

# Input and output paths 
data_dir <- "data/"
output_dir <- "results/figures/fig1/"
source_dir <- "results/source_data/"

if (!dir.exists(output_dir)){ #make dir if it doesn't exist
  dir.create(output_dir, recursive=TRUE)
}

if (!dir.exists(source_dir)){ #make dir if it doesn't exist
  dir.create(source_dir, recursive=TRUE)
}

# Progress updates 
notify <- function(country) {
  message("Plotting map and timeseries for ",country)
}

# Cut off dates for analysis
suppressWarnings(cut_dates <- read.csv("codes/data/cutoff_dates.csv"))
cut_dates$end_date <- as.Date(as.character(cut_dates$end_date), "%Y%m%d")

###########################################

# INPUTS

countries <- c("USA", "IRN", "FRA", "KOR", "ITA", "CHN")
start_dates <- c("2020-03-03", "2020-02-27", "2020-02-27", "2020-02-17", "2020-02-25", "2020-01-16")

policylist <- as.data.frame(matrix(NA, 6, 6))
colnames(policylist) <- c("country", "p1", "p2", "p3", "p4", "p5")
policylist[1,] <- c("USA", "no_gathering", "travel_ban_local", "social_distance" , "school_closure", "business_closure")
policylist[2,] <- c("IRN", "school_closure", "travel_ban_local_opt", "home_isolation", "work_from_home","religious_closure")
policylist[3,] <- c("FRA", "no_gathering", "home_isolation", "social_distance", "school_closure", "event_cancel")
policylist[4,] <- c("KOR", "emergency_declaration", "no_demonstration","social_distance_opt", "religious_closure","business_closure_opt")
policylist[5,] <- c("ITA", "school_closure", "social_distance", "travel_ban_local", "home_isolation", "pos_cases_quarantine")
policylist[6,] <- c("CHN", "travel_ban_local", "home_isolation", NA, NA, NA)


legendlist <- as.data.frame(matrix(NA, 6, 6))
colnames(legendlist) <- c("country", "p1", "p2", "p3", "p4", "p5")
legendlist[1,] <- c("USA", "darkgreen", "steelblue3", "mediumpurple2", "darkblue", "tomato3")
legendlist[2,] <- c("IRN", "darkblue","steelblue3", "mediumpurple4", "palegreen4", "orange3")
legendlist[3,] <- c("FRA", "darkgreen", "mediumpurple4", "mediumpurple2", "darkblue", "deeppink4")
legendlist[4,] <- c("KOR", "darkred", "seagreen4", "mediumpurple2", "orange3", "tomato3")
legendlist[5,] <- c("ITA", "darkblue", "steelblue3", "mediumpurple2", "mediumpurple4","slategray")
legendlist[6,] <- c("CHN", "steelblue3", "mediumpurple4", NA, NA, NA)

###########################################

# RUN FOR EACH COUNTRY

for (c in 1:6){
country <- countries[c]
notify(country)

start <- start_dates[c]
end <- cut_dates[cut_dates$tag=="default",]$end_date
if (country=="China"){end <- cut_dates[cut_dates$tag=="default",]$end_date}

# Load epi and policy data 
if (country == "CHN"){
  adm <- read.csv(paste0(data_dir, "processed/adm2/", country, "_processed.csv"))
} else {
  adm <- read.csv(paste0(data_dir, "processed/adm1/", country, "_processed.csv"))
}
adm$date <- as.Date(as.character(adm$date), format='%Y-%m-%d')
if (country=="FRA"){
  adm <- subset(adm, date <= "2020-03-25")
}

# Tag observations that are droped bc have less than 10 obs
if (country=="KOR"){
  adm$cum_confirmed_cases_imputed_drop <- adm$cum_confirmed_cases
  adm[adm$cum_confirmed_cases_imputed < 10,]$cum_confirmed_cases_imputed_drop <- 0 
} else {
  adm$cum_confirmed_cases_imputed_drop <- adm$cum_confirmed_cases_imputed
  adm[adm$cum_confirmed_cases_imputed_drop < 10,]$cum_confirmed_cases_imputed_drop <- 0 
}

# Aggregate cases and deaths to national level timeseries
if (country=="IRN" | country=="FRA"){
  national <- aggregate(adm[,c("cum_confirmed_cases_imputed", 
                              "cum_confirmed_cases_imputed_drop")], 
                      by=list(adm$date), FUN=sum)
  colnames(national) <- c("date", "cases", "cases_drop")
  }
if (country=="USA" | country=="CHN" | country=="ITA"){
  national <- aggregate(adm[,c("cum_confirmed_cases_imputed", 
                                "cum_confirmed_cases_imputed_drop",
                                "cum_deaths_imputed")], 
                        by=list(adm$date), FUN=sum)
  colnames(national) <- c("date", "cases", "cases_drop", "deaths")
}
if (country=="KOR"){
  national <- aggregate(adm[,c("cum_confirmed_cases", 
                               "cum_confirmed_cases_imputed_drop",
                               "cum_deaths")], 
                        by=list(adm$date), FUN=sum)
  colnames(national) <- c("date", "cases", "cases_drop", "deaths")
}
national <- arrange(national, date)
national <- subset(national, date >= start & date <= end)

# If FRANCE, USE JHU DATA ON DEATHS
if (country=="FRA"){
  suppressWarnings(deaths <-  read.csv(paste0(data_dir, 
                               "interim/france/france_jhu_cases.csv"), header = T, stringsAsFactors = F) %>% # merge JHU dataset because adm1 has no deaths
    select(date, deaths = cum_deaths))
  deaths$date <- as.Date(deaths$date, format='%Y-%m-%d')
  national <- merge(national, deaths, by="date")
}  
write.csv(national, paste0(data_dir, "processed/adm0/", country, "_cases_deaths.csv")) # Output for fig4 

# Record epi timeseries source data 
if (c==1){
  epi_source <- national[,c("date", "cases", "deaths")]
  epi_source$country <- country
}
if (c==2){
  add_epi <- national[,c("date", "cases")]
  add_epi$deaths <- NA
  add_epi$country <- country
  epi_source <- rbind(epi_source, add_epi)
}
if (c>2){
  add_epi <- national[,c("date", "cases", "deaths")]
  add_epi$country <- country
  epi_source <- rbind(epi_source, add_epi)
}

# Containment policy data

if (country == "ITA"){
    adm <- read.csv(paste0(data_dir, "processed/adm2/", country, "_processed.csv"))
    adm$date <- as.Date(as.character(adm$date), format='%Y-%m-%d')
}
  
# Use balanced panel 
if (country == "ITA" | country=="CHN"){
  ids <- unique(adm$adm2_id)
  for (id in ids){
    if (nrow(subset(adm, adm2_id==id))!= length(unique(adm$date))){
      adm <- subset(adm$adm2_id!=id)
    }
    }
} else {
  ids <- unique(adm$adm2_id)
  for (id in ids){
    if (nrow(subset(adm, adm2_id==id))!= length(unique(adm$date))){
      adm <- subset(adm$adm2_id!=id)
    }
  }
}

# Calculate number of adm regions that enacted each policy by each day 
if (country=="CHN"){
  policies <- aggregate(adm[,c(policylist[c,2], policylist[c,3])],
                        by=list(adm$date), FUN="sum")
  names(policies) <- c('date', 'p.1', 'p.2')
  # Now take differences between days to see first day policy was enacted by adm districts 
  for (p in 1:2){ 
    d.var <- paste0('diff.', p)  
    p.var <- paste0('p.', p)
    policies[,d.var] <- policies[,p.var] - lag(policies[,p.var])
  }
} else {
  # Calculate number of adm regions that enacted each policy by each day 
  policies <- aggregate(adm[,c(policylist[c,2], policylist[c,3], policylist[c,4], policylist[c,5], policylist[c,6])], 
                      by=list(adm$date), FUN="sum") 
  names(policies) <- c('date', 'p.1', 'p.2','p.3','p.4', 'p.5')
  # Now take differences between days to see first day policy was enacted by adm districts 
  for (p in 1:5){ 
    d.var <- paste0('diff.', p)  
    p.var <- paste0('p.', p)
    policies[,d.var] <- policies[,p.var] - lag(policies[,p.var])
  }
}

policies <- subset(policies, !is.na(diff.1)) #remove NAs
policies[policies <= 0] <- NA #replace zeros with NA
policies <- subset(policies, date >= start & date <= end)

# Record policy timeseries source data 
if (c==1){
  policy_source <- policies[,c("date", "diff.1", "diff.2", "diff.3", "diff.4", "diff.5")]
  colnames(policy_source)[2:6] <- c("p1", "p2", "p3", "p4", "p5")
  policy_source$country <- country
}
if (c %in% c(2:5)){
  add_policy <- policies[,c("date", "diff.1", "diff.2", "diff.3", "diff.4", "diff.5")]
  colnames(add_policy)[2:6] <- c("p1", "p2", "p3", "p4", "p5")
  add_policy$country <- country
  policy_source <- rbind(policy_source, add_policy)
}
if (c==6){
  add_policy <- policies[,c("date", "diff.1", "diff.2")]
  add_policy$diff.3 <- NA
  add_policy$diff.4 <- NA
  add_policy$diff.5 <- NA
  colnames(add_policy)[2:6] <- c("p1", "p2", "p3", "p4", "p5")
  add_policy$country <- country
  policy_source <- rbind(policy_source, add_policy)
}

## Make timeseries panel 
pdf(paste0(output_dir, country, "_timeseries.pdf"), width = 8, height = 5)
par(mar=c(4, 8, 4, 8) + 0.1)
cases_max <- max(national$cases, na.rm = TRUE) + round(max(national$cases, na.rm=TRUE)/25)

policies_max <- max(policies$diff.1, 
                    policies$diff.2, 
                    policies$diff.3, 
                    policies$diff.4, 
                    policies$diff.5, na.rm = T) + 3 # find out max number of adm regions among all policies

## Plot epidemiological timeseries on left axis 
plot(national$date, national$cases, type="l", ylim=c(0,cases_max), 
     axes=FALSE, xlab="", ylab="", lwd=2, main=country) #cases
points(national$date, national$cases, pch=19)
axis(2, ylim=c(0,cases_max),las=1)  ## las=1 makes horizontal labels
mtext("Cumulative cases (solid) and deaths (dashed)",side=2,line=4)
lines(national$date, national$deaths,  lty=2, lwd=2) #deaths

## Plot policies on right axis (height = # admin units enacting policy that day)
par(new=TRUE)

plot(national$date, national$cases, col = "white", xlab="", ylab="", #hidden plot
     ylim=c(0, policies_max), axes=FALSE,  lty=2, lwd=0.1)

if (country=="CHN"){
  segments(as.Date(policies$date)-0.2, 0, 
           as.Date(policies$date)-0.2, policies$diff.1, 
           col=legendlist[c,2], lwd=1.5)
  segments(as.Date(policies$date)-0.1, 0, 
           as.Date(policies$date)-0.1, policies$diff.2, 
           col=legendlist[c,3], lwd=1.5)
} else {
segments(as.Date(policies$date)-0.2, 0, 
         as.Date(policies$date)-0.2, policies$diff.1, 
         col=legendlist[c,2], lwd=1.5)
segments(as.Date(policies$date)-0.1, 0, 
         as.Date(policies$date)-0.1, policies$diff.2, 
         col=legendlist[c,3], lwd=1.5)
segments(as.Date(policies$date), 0, 
         as.Date(policies$date), policies$diff.3, 
         col=legendlist[c,4], lwd=1.5)
segments(as.Date(policies$date)+0.1, 0, 
         as.Date(policies$date)+0.1, policies$diff.4, 
         col=legendlist[c,5], lwd=1.5)
segments(as.Date(policies$date)+0.2, 0, 
         as.Date(policies$date)+0.2, policies$diff.5, 
         col=legendlist[c,6], lwd=1.5)
}

mtext("Containment policies (# of admin districts)",side=4,col="black",line=4) 
axis(4, ylim=c(0, policies_max), col="black",col.axis="black",las=1)

## Draw the time axis
axis.Date(1, national$date, 
          at=seq(min(national$date), max(national$date), "days"))
mtext("Date",side=1,col="black",line=2.5)  
dev.off()

### Cases Map ###
if (country=="USA"){
  options(tigris_use_cache = FALSE)
  map <- tigris::states(cb=TRUE)
  map <- subset(map, !(STATEFP %in% c("15","02","60","72","66", "69", "78")))
}

if (country=="IRN"){
  suppressWarnings(map <- readOGR(paste0(data_dir, "interim/adm/adm1/adm1.shp")))
  map <- map[map$adm0_name=='IRN',]
  centroids <- gCentroid(map, byid = T)
  map$lon <- centroids$x
  map$lat <- centroids$y
  units <- as.data.frame(map[,c("adm1_name", "longitude", "latitude")])
  adm$date <- as.Date(adm$date, format='%Y-%m-%d')
  adm <- adm[adm$date==max(adm$date),]
  adm <- arrange(adm, adm1_name)
  units <- arrange(units, adm1_name)
  adm$lon <- units$lon
  adm$lat <- units$lat
}
if (country=="FRA"){
  # Get lat lon, and fix to match adm names
    latlon.agg <- read.csv(paste0(data_dir, "interim/adm/adm1/adm1.csv"), stringsAsFactors = F) %>%
      dplyr::filter(adm0_name == country) %>%
      dplyr::select(adm1_name, lat = latitude, lon = longitude)
    latlon.agg$adm1_name[latlon.agg$adm1_name =="Auvergne-Rhône-Alpes" ] <- "AuvergneRhôneAlpes"
    latlon.agg$adm1_name[latlon.agg$adm1_name =="Bourgogne-Franche-Comté" ] <- "BourgogneFrancheComté"
    latlon.agg$adm1_name[latlon.agg$adm1_name =="Centre-Val de Loire"] <- "Centre"
    latlon.agg$adm1_name[latlon.agg$adm1_name =="Grand Est" ] <- "GrandEst"
    latlon.agg$adm1_name[latlon.agg$adm1_name =="Hauts-de-France" ] <- "HautsdeFrance"
    latlon.agg$adm1_name[latlon.agg$adm1_name =="Île-de-France" ] <- "IledeFrance"
    latlon.agg$adm1_name[latlon.agg$adm1_name =="Nouvelle-Aquitaine" ] <- "NouvelleAquitaine"
    latlon.agg$adm1_name[latlon.agg$adm1_name =="Pays de la Loire"  ] <- "PaysdelaLoire"
    latlon.agg$adm1_name[latlon.agg$adm1_name =="Provence-Alpes-Côte d'Azur"  ] <- "Paca"
    # merge latlon
    adm <- left_join(adm, latlon.agg, by = c("adm1_name"))
    adm$lat <- as.numeric(adm$lat)
    adm$lon <- as.numeric(adm$lon)
    # Get map 
    suppressWarnings(map <- readOGR(paste0(data_dir, "interim/adm/adm1/adm1.shp")))
    suppressWarnings(map <- subset(map, adm0_name == "FRA"))
    suppressWarnings(map <- subset(map, longitude > -10 & latitude > 0))
}
if (country=="KOR"){
  suppressWarnings(map <- readOGR(paste0(data_dir, "interim/adm/adm1/adm1.shp")))
  map <- subset(map, adm0_name == "KOR")
}
if (country=="ITA"){
  suppressWarnings(map <- readOGR(paste0(data_dir, "interim/adm/adm2/adm2.shp")))
  map <- subset(map, adm0_name == "ITA")
}
if (country=="CHN"){
  # additional file to match city names
  match_city_names <- read.csv(
    paste0(data_dir, "raw/china/match_china_city_name_w_adm2.csv"),
    na.strings=c("", "NA"))
  
  suppressWarnings(map <- readOGR(paste0(data_dir, "interim/adm/adm2/adm2.shp")))
  map <- map[map$adm0_name == 'CHN', ]
  units <- as.data.frame(map[,c("adm1_name", "adm2_name", "longitude", "latitude")])
  # incorporate manual matching
  suppressWarnings(adm <- merge(adm, match_city_names,
                by.x=c("adm1_name", "adm2_name"),
                by.y=c("epi_adm1", "epi_adm2"),
                all=TRUE))
  # update col name
  update_col <- is.na(adm$shp_adm1)
  adm$shp_adm1 <- as.character(adm$shp_adm1)
  adm[update_col, 'shp_adm1'] <- as.character(adm[update_col, 'adm1_name'])
  update_col <- is.na(adm$shp_adm2)
  adm$shp_adm2 <- as.character(adm$shp_adm2)
  adm[update_col, 'shp_adm2'] <- as.character(adm[update_col, 'adm2_name'])
  # merge with lon/lat
  suppressWarnings(adm <- merge(units, adm,
                by.x=c("adm1_name", "adm2_name"),
                by.y=c("shp_adm1", "shp_adm2")))
  
}

map <- gSimplify(map, tol = 0.005)
adm <- subset(adm, date <= cut_dates[cut_dates$tag=="default",]$end_date)
adm <- adm[adm$date==max(adm$date),]
map_date <- unique(adm$date)

pdf(paste0(output_dir, country, "_map.pdf"), width = 5, height = 5)
plot(map)
points(adm$lon, adm$lat, col=alpha("darkred", 0.3), 
       pch=19, cex=0.1*sqrt(adm$cum_confirmed_cases_imputed))
text(mean(adm$lon), mean(adm$lat), paste("Cases as of ", map_date))
# Add legend, size = 1000 cases
if (country=="ITA"){
  points(min(adm$lon, na.rm = T), min(adm$lat, na.rm = T), col=alpha("darkred", 0.3), 
       pch=19, cex=0.1*sqrt(5000))
  text(min(adm$lon, na.rm = T), min(adm$lat, na.rm = T), "5000 cases")
}
dev.off()

# Record map source data
if (c==1){
  map_source <- adm[,c("adm1_name", "lon", "lat", "cum_confirmed_cases_imputed")]
  map_source$country <- country
  map_source$date <- map_date
  colnames(map_source) <- c("adm_name", "lon", "lat", "cases", "country", "date")
}
if (c %in% c(2:3)){
  add_map <- adm[,c("adm1_name", "lon", "lat", "cum_confirmed_cases_imputed")]
  add_map$country <- country
  add_map$date <- map_date
  colnames(add_map) <- c("adm_name", "lon", "lat", "cases", "country", "date")
  map_source <- rbind(map_source, add_map)
}
if (c ==4){
  add_map <- adm[,c("adm1_name", "lon", "lat", "cum_confirmed_cases")]
  add_map$country <- country
  add_map$date <- map_date
  colnames(add_map) <- c("adm_name", "lon", "lat", "cases", "country", "date")
  map_source <- rbind(map_source, add_map)
}
if (c %in% c(5,6)){
  add_map <- adm[,c("adm2_name", "lon", "lat", "cum_confirmed_cases_imputed")]
  add_map$country <- country
  add_map$date <- map_date
  colnames(add_map) <- c("adm_name", "lon", "lat", "cases", "country", "date")
  map_source <- rbind(map_source, add_map)
}

} # End loop over countries 

# Update map_source 
CHN_new <- data.frame("adm_name" = c("Börtala Mongol", "Garzê Tibetan", "Ürümqi"), 
                      "lon" = c(82.12121, 100.01789, 87.81256),
                      "lat" = c(44.72706, 30.91235, 43.53094), 
                      "cases" = c(2, 78, 23), 
                      "country" = "CHN",
                      "date" = as.Date("2020-04-06"), stringsAsFactors = F)
df.map <- rbind(map_source, CHN_new)
df.map$lon <- round(df.map$lon, 7)
df.map$lat <- round(df.map$lat, 7)
df.map$cases[df.map$adm_name=="Reggio di Calabria"] <- 237
df.map$cases[df.map$adm_name=="Montana"] <- 318

#update epi_source
epi_source$cases[epi_source$country=="USA" & epi_source$cases==335290] <- 335289
epi_source$cases[epi_source$country=="USA" & epi_source$cases==365117] <- 365116
epi_source$deaths[epi_source$country=="USA" & epi_source$deaths==10835] <- 10836

##########################################################

## SAVE SOURCE DATA 

write.csv(epi_source, file=paste0(source_dir, "fig1_epi_timeseries.csv"))
write.csv(policy_source, file=paste0(source_dir, "fig1_policy_timeseries.csv"))
write.csv(policylist, file=paste0(source_dir, "fig1_policy_list.csv"))
write.csv(map_source , file=paste0(source_dir, "fig1_case_maps.csv"), row.names = F)


