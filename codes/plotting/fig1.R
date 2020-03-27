##############################
##  Figure 1: Data Display  ##
##############################

rm(list=ls())
library(dplyr)
library(rgdal)
library(rgeos)
library(scales)
library(magrittr)
library(ggplot2)

data_dir <- "data/"
output_dir <- "results/figures/fig1/"

if (!dir.exists(output_dir)){ #make dir if it doesn't exist
  dir.create(output_dir, recursive=TRUE)
}

notify <- function(country) {
  message("Plotting map and timeseries for ",country)
}

#################

# ITALY
country <- "ITA"
notify(country)
#################

#### (1) Epidemiological timeseries ####
adm1 <- read.csv(paste0(data_dir, "processed/adm1/", country, "_processed.csv"))
adm1$cum_confirmed_cases_imputed_drop <- adm1$cum_confirmed_cases_imputed
adm1[adm1$cum_confirmed_cases_imputed < 10,]$cum_confirmed_cases_imputed_drop <- 0 
national <- aggregate(adm1[,c("cum_confirmed_cases_imputed", "cum_confirmed_cases_imputed_drop",
                              "cum_deaths_imputed")], 
                   by=list(adm1$date), FUN=sum)
colnames(national) <- c("date", "cases", "cases_drop", "deaths")
national$date <- as.character(national$date)
national$date <- as.Date(national$date, format='%Y-%m-%d')
national <- arrange(national, date)
national <- subset(national, date >= "2020-02-25" & date <= "2020-03-18")
write.csv(national, paste0(data_dir, "processed/adm0/", country, "_cases_deaths.csv"))

#### (2) Containment policies ####
adm2 <- read.csv(paste0(data_dir, "processed/adm2/", country, "_processed.csv"))

# Use only balanced panel 
ids <- unique(adm2$adm2_id)
for (id in ids){
  if (nrow(subset(adm2, adm2_id==id))!= length(unique(adm2$date))){
    adm2 <- subset(adm2$adm2_id!=id)
  }
}

# Find 5 common policiees for this country 
sum_polices <- colSums(adm2[,c(11:37)])
round(sum_polices,0)

# Aggregate these policies by date (so reflect # admin units have policy active on each day)
policies <- aggregate(adm2[,c("school_closure",
                              "social_distance",
                              "travel_ban_local",
                              "home_isolation",
                              "pos_cases_quarantine")], by=list(adm2$date), FUN="sum")
colnames(policies)[1] <- "date"

# Take differences to get # admin units that enacted the policy each day
policies$school_closure_diff <- policies$school_closure - lag(policies$school_closure)
policies$social_distance_diff <- policies$social_distance - lag(policies$social_distance)
policies$travel_ban_diff <- policies$travel_ban_local - lag(policies$travel_ban_local)
policies$home_isolation_diff <- policies$home_isolation - lag(policies$home_isolation)
policies$pos_cases_quarantine_diff <- policies$pos_cases_quarantine - lag(policies$pos_cases_quarantine)

# Clean up for plotting purposes 
policies <- subset(policies, !is.na(school_closure_diff)) # remove missing data bc lags 
policies[policies$school_closure_diff==0,]$school_closure_diff <- NA
policies[policies$social_distance_diff==0,]$social_distance_diff <- NA
policies[policies$travel_ban_diff==0,]$travel_ban_diff <- NA
policies[policies$home_isolation_diff==0,]$home_isolation_diff <- NA
policies[policies$pos_cases_quarantine_diff==0,]$pos_cases_quarantine_diff <- NA

## Make timeseries panel 
pdf(paste0(output_dir, country, "_timeseries.pdf"), width=8, heigh=5)
par(mar=c(4, 8, 4, 8) + 0.1)
cases_max <- max(national$cases) + 5000 # ylim for left axis 
policies_max <- max(max(policies$school_closure_diff, na.rm = T),
                    max(policies$social_distance_diff, na.rm = T),
                    max(policies$travel_ban_diff, na.rm = T),
                    max(policies$home_isolation_diff, na.rm = T),
                    max(policies$pos_cases_quarantine_diff, na.rm = T)) # ylim for right axis

## Plot epidemiological data 
plot(national$date, national$cases, type="l", ylim=c(0,cases_max), 
     axes=FALSE, xlab="", ylab="", lwd=2, main=country) # Confirmed cases, solid black line
points(national$date, national$cases, pch=19) # Confirmed cases, points 
axis(2, ylim=c(0,cases_max),las=1)  ## Left axis labels 
mtext("Cumulative cases (solid) and deaths (dashed)",side=2,line=4)
lines(national$date, national$deaths,axes=FALSE,  lty=2, lwd=2) # Cumulative deaths, dashed line

## Plot containment policy data 
par(new=TRUE)

plot(national$date, national$deaths, col = "white", xlab="", ylab="", 
     ylim=c(0,policies_max), axes=FALSE,  lty=2, lwd=2) # Blank slate to add segments to 

# School closures     
segments(as.Date(policies$date)-0.2, 0, 
         as.Date(policies$date)-0.2, policies$school_closure_diff, 
         col="darkblue", lwd=1.5)

# Trave ban (local)
segments(as.Date(policies$date)-0.1, 0, 
         as.Date(policies$date)-0.1, policies$travel_ban_diff, 
         col="steelblue3", lwd=1.5)

# Social distancing measurs 
segments(as.Date(policies$date), 0, 
         as.Date(policies$date), policies$social_distance_diff, 
         col="mediumpurple2", lwd=1.5)

# Home isolation 
segments(as.Date(policies$date)+0.1, 0, 
         as.Date(policies$date)+0.1, policies$home_isolation_diff, 
         col="mediumpurple4", lwd=1.5)

# Positive cases quarantine 
segments(as.Date(policies$date)+0.2, 0, 
         as.Date(policies$date)+0.2, policies$pos_cases_quarantine_diff, 
         col="slategray", lwd=1.5)

mtext("Containment policies (# of admin units)",side=4,col="black",line=4) 
axis(4, ylim=c(0,policies_max), col="black",col.axis="black",las=1)

## Add the time axis
axis.Date(1, national$date, 
          at=seq(min(national$date), max(national$date), "days"))
mtext("Date",side=1,col="black",line=2.5)  
dev.off()

#### (3) Map confirmed cases ####

map <- readOGR(paste0(data_dir, "interim/adm/adm2/adm2.shp"))
map <- subset(map, adm0_name == country)
map <- gSimplify(map, tol = 0.005)
adm2$date <- as.Date(adm2$date, format='%Y-%m-%d')
adm2 <- adm2[adm2$date==max(adm2$date),]

pdf(paste0(output_dir, country, "_map.pdf"),
    width = 5, heigh = 5)
plot(map)
points(adm2$lon, adm2$lat, col=alpha("darkred", 0.35), 
       pch=19, cex=0.15*sqrt(adm2$cum_confirmed_cases_imputed))

# Add legend, size = 1000 cases
points(min(adm2$lon, na.rm = T), min(adm2$lat, na.rm = T), col=alpha("darkred", 0.35), 
       pch=19, cex=0.15*sqrt(1000))
text(min(adm2$lon, na.rm = T), min(adm2$lat, na.rm = T), "1000 cases")

dev.off()

#######################################################################

country <- "IRN"
notify(country)
#####

#### (1) Epidemiological timeseries ####
adm1 <- read.csv(paste0(data_dir, "processed/adm1/", country, "_processed.csv"))

adm1$cum_confirmed_cases_imputed_drop <- adm1$cum_confirmed_cases_imputed
adm1[adm1$cum_confirmed_cases_imputed < 10,]$cum_confirmed_cases_imputed_drop <- 0 
national <- aggregate(adm1[,c("cum_confirmed_cases_imputed", "cum_confirmed_cases_imputed_drop")], 
                      by=list(adm1$date), FUN=sum)
colnames(national) <- c("date", "cases", "cases_drop")
national$date <- as.character(national$date)
national$date <- as.Date(national$date, format='%Y-%m-%d')
national <- arrange(national, date)

national <- subset(national, date >= "2020-02-27" & date <= "2020-03-18")
write.csv(national, paste0(data_dir, "processed/adm0/", country, "_cases_deaths.csv"))

#### (2) Containment policies ####

# Use only balanced panel 
ids <- unique(adm1$adm1_id)
for (id in ids){
  if (nrow(subset(adm1, adm1_id==id))!= length(unique(adm1$date))){
    adm1 <- subset(adm2$adm2_id!=id)
  }
}

# Find 5 common policies for this country
sum_polices <- colSums(adm1[,c(4:9)])
sum_polices

# Aggregate these policies by date (so reflect # admin units have policy active on each day)
policies <- aggregate(adm1[,c("school_closure",
                              "travel_ban_local_opt",
                              "home_isolation",
                              "work_from_home",
                              "no_gathering")], by=list(adm1$date), FUN="sum")
colnames(policies)[1] <- "date"

# Take differences to get # admin units that enacted the policy each day
policies$school_closure_diff <- policies$school_closure - lag(policies$school_closure)
policies$travel_ban_diff <- policies$travel_ban_local_opt - lag(policies$travel_ban_local_opt)
policies$home_isolation_diff <- policies$home_isolation - lag(policies$home_isolation)
policies$work_from_home_diff <- policies$work_from_home - lag(policies$work_from_home)
policies$no_gathering_diff <- policies$no_gathering - lag(policies$no_gathering)

# Clean up for plot
policies <- subset(policies, !is.na(school_closure_diff))
policies[policies$school_closure_diff==0,]$school_closure_diff <- NA
policies[policies$travel_ban_diff==0,]$travel_ban_diff <- NA
policies[policies$work_from_home_diff==0,]$work_from_home_diff <- NA
policies[policies$home_isolation_diff==0,]$home_isolation_diff <- NA
policies[policies$no_gathering_diff==0,]$no_gathering_diff <- NA


## Make timeseries panel 
pdf(paste0(output_dir, country, "_timeseries.pdf"), width=8, heigh=5)
par(mar=c(4, 8, 4, 8) + 0.1)
cases_max <- max(national$cases, na.rm=TRUE) + 5000
policies_max <- max(max(policies$travel_ban_diff, na.rm = T),
                    max(policies$home_isolation_diff, na.rm = T),
                    max(policies$work_from_home_diff, na.rm = T),
                    max(policies$no_gathering_diff, na.rm = T))

## Plot epidemiological data 
plot(national[!is.na(national$cases),]$date, 
     national[!is.na(national$cases),]$cases, type="l", ylim=c(0,cases_max), 
     axes=FALSE, xlab="", ylab="", lwd=2, main=country)
points(national$date, national$cases, pch=19)
axis(2, ylim=c(0,cases_max),las=1)  ## las=1 makes horizontal labels
mtext("Cumulative cases",side=2,line=4)

## Plot containment policy data 
par(new=TRUE)

plot(national$date, national$cases, col = "white", xlab="", ylab="", 
     ylim=c(0,policies_max), axes=FALSE,  lty=2, lwd=2)

segments(as.Date(policies$date)-0.1, 0, 
         as.Date(policies$date)-0.1, policies$school_closure_diff, 
         col="darkblue", lwd=1.5)
segments(as.Date(policies$date)-0.1, 0, 
         as.Date(policies$date)-0.1, policies$travel_ban_diff, 
         col="steelblue3", lwd=1.5)
segments(as.Date(policies$date)+0.1, 0, 
         as.Date(policies$date)+0.1, policies$home_isolation_diff, 
         col="mediumpurple4", lwd=1.5)
segments(as.Date(policies$date), 0, 
         as.Date(policies$date), policies$work_from_home_diff, 
         col="palegreen4", lwd=1.5)
segments(as.Date(policies$date)+0.2, 0, 
         as.Date(policies$date)+0.2, policies$no_gathering_diff, 
         col="darkgreen", lwd=1.5)


mtext("Containment policies (# of admin districts)",side=4,col="black",line=4) 
axis(4, ylim=c(0,policies_max), col="black",col.axis="black",las=1)

## Draw the time axis
axis.Date(1, national$date, 
          at=seq(min(national$date), max(national$date), "days"))
mtext("Date",side=1,col="black",line=2.5)  

dev.off()

### Cases Map ###
map <- readOGR(paste0(data_dir, "interim/adm/adm1/adm1.shp"))
map <- map[map$adm0_name=='IRN',]
centroids <- gCentroid(map, byid = T)
map$lon <- centroids$x
map$lat <- centroids$y
units <- as.data.frame(map[,c("adm1_name", "longitude", "latitude")])
adm1$date <- as.Date(adm1$date, format='%Y-%m-%d')
adm1 <- adm1[adm1$date==max(adm1$date),]
adm1 <- arrange(adm1, adm1_name)
units <- arrange(units, adm1_name)
adm1$lon <- units$lon
adm1$lat <- units$lat

map <- gSimplify(map, tol = 0.005)

pdf(paste0(output_dir, country, "_map.pdf"),
    width = 5, height = 5)
plot(map)
points(adm1$lon, adm1$lat, col=alpha("darkred", 0.35), 
       pch=19, cex=0.15*sqrt(adm1$cum_confirmed_cases_imputed))

dev.off()

######################################################################

country <- "CHN"
notify(country)

#####

#### (1) Epidemiological timeseries ####
adm2 <- read.csv(paste0(data_dir, "processed/adm2/", country, "_processed.csv"))

adm2$cum_confirmed_cases_imputed_drop <- adm2$cum_confirmed_cases_imputed
adm2[adm2$cum_confirmed_cases_imputed < 10,]$cum_confirmed_cases_imputed_drop <- 0 
national <- aggregate(adm2[,c("cum_confirmed_cases_imputed", "cum_confirmed_cases_imputed_drop",
                              "cum_deaths_imputed")], 
                      by=list(adm2$date), FUN=sum)
colnames(national) <- c("date", "cases", "cases_drop", "deaths")
national$date <- as.character(national$date)
national$date <- as.Date(national$date, format='%Y-%m-%d')
national <- arrange(national, date)

national <- subset(national, date >= "2020-01-16" & date <= "2020-03-18")
write.csv(national, paste0(data_dir, "processed/adm0/", country, "_cases_deaths.csv"))

#### (2) Containment policies ####

# Use balanced panel 
ids <- unique(adm2$adm2_id)
for (id in ids){
  if (nrow(subset(adm2, adm2_id==id))!= length(unique(adm2$date))){
    adm2 <- subset(adm2$adm2_id!=id)
  }
}

# Find 5 common policiees
sum_polices <- colSums(adm2[,c(5:10)])
sum_polices

# Aggregate these policies by date (so reflect # admin units have policy active on each day)
policies <- aggregate(adm2[,c("travel_ban_local",
                              "home_isolation")], by=list(adm2$date), FUN="sum")
colnames(policies)[1] <- "date"

# Take differences to get # admin units that enacted the policy each day
policies$travel_ban_diff <- policies$travel_ban_local - lag(policies$travel_ban_local)
policies$home_isolation_diff <- policies$home_isolation - lag(policies$home_isolation)

# Clean up for plot 
policies <- subset(policies, !is.na(travel_ban_diff))
policies[(policies$travel_ban_diff<0),]$travel_ban_diff <- 0
policies[(policies$home_isolation_diff<0),]$home_isolation_diff <- 0
policies[policies$travel_ban_diff==0,]$travel_ban_diff <- NA
policies[policies$home_isolation_diff==0,]$home_isolation_diff <- NA

## Make timeseries panel 
pdf(paste0(output_dir, country, "_timeseries.pdf"), width=8, heigh=5)
par(mar=c(4, 8, 4, 8) + 0.1)
cases_max <- max(national$cases, na.rm=TRUE) + 5000
policies_max <- max(max(policies$travel_ban_diff, na.rm = T),
                    max(policies$home_isolation_diff, na.rm = T))

## Plot epidemiological data 
plot(national[!is.na(national$cases),]$date, national[!is.na(national$cases),]$cases, type="l", ylim=c(0,cases_max), 
     axes=FALSE, xlab="", ylab="", lwd=2, main=country)
points(national$date, national$cases, pch=19)
axis(2, ylim=c(0,cases_max),las=1)  ## las=1 makes horizontal labels
mtext("Cumulative cases (solid) and deaths (dashed)",side=2,line=4)
lines(national$date, national$deaths,axes=FALSE,  lty=2, lwd=2)

## Plot containment policies
par(new=TRUE)

plot(national$date, national$cases, col = "white", xlab="", ylab="", 
     ylim=c(0,policies_max), axes=FALSE,  lty=2, lwd=2)

segments(as.Date(policies$date)-0.1, 0, 
         as.Date(policies$date)-0.1, policies$travel_ban_diff, 
         col="steelblue3", lwd=1.5)
segments(as.Date(policies$date)+0.1, 0, 
         as.Date(policies$date)+0.1, policies$home_isolation_diff, 
         col="mediumpurple4", lwd=1.5)

mtext("Containment policies (# of admin districts)",side=4,col="black",line=4) 
axis(4, ylim=c(0,policies_max), col="black",col.axis="black",las=1)

## Draw the time axis
axis.Date(1, national$date, 
          at=seq(min(national$date), max(national$date), "days"))
mtext("Date",side=1,col="black",line=2.5)  

dev.off()

## Cases Map ###

# additional file to match city names
match_city_names <- read.csv(
  paste0(data_dir, "raw/china/match_china_city_name_w_adm2.csv"),
  na.strings=c("", "NA"))

map <- readOGR(paste0(data_dir, "interim/adm/adm2/adm2.shp"))
map <- map[map$adm0_name == 'CHN', ]
adm2$date <- as.Date(adm2$date, format='%Y-%m-%d')
adm2 <- adm2[adm2$date==max(adm2$date),]
units <- as.data.frame(map[,c("adm1_name", "adm2_name", "longitude", "latitude")])
# incorporate manual matching
adm2 <- merge(adm2, match_city_names,
              by.x=c("adm1_name", "adm2_name"),
              by.y=c("epi_adm1", "epi_adm2"),
              all=TRUE)
# update col name
update_col <- is.na(adm2$shp_adm1)
adm2$shp_adm1 <- as.character(adm2$shp_adm1)
adm2[update_col, 'shp_adm1'] <- as.character(adm2[update_col, 'adm1_name'])
update_col <- is.na(adm2$shp_adm2)
adm2$shp_adm2 <- as.character(adm2$shp_adm2)
adm2[update_col, 'shp_adm2'] <- as.character(adm2[update_col, 'adm2_name'])
# merge with lon/lat
adm2 <- merge(units, adm2,
              by.x=c("adm1_name", "adm2_name"),
              by.y=c("shp_adm1", "shp_adm2"))

map <- gSimplify(map, tol = 0.005)

pdf(paste0(output_dir, country, "_map.pdf"),
    width = 5, height = 5)
plot(map)
points(adm2$longitude, adm2$latitude, col=alpha("darkred", 0.35), 
       pch=19, cex=0.15*sqrt(adm2$cum_confirmed_cases_imputed))
dev.off()

##########################################################

country <- "USA"
notify(country)
  
  policylist <- c("no_gathering_popwt", 
                  "travel_ban_local_popwt", 
                  "social_distance_popwt" , 
                  "school_closure_popwt", 
                  "business_closure_popwt")
  legend.list <- c("no gathering", 
                   "travel ban", 
                   "social distancing", 
                   "school closure", 
                   "business closure") #set up legend
  color.list <- c("darkgreen", 
                  "steelblue3", 
                  "mediumpurple2", 
                  "darkblue", 
                  "tomato3")

adm1 <- read.csv(paste0(data_dir, "processed/adm1/", country, "_processed.csv"))
adm1$date <- as.Date(as.character(adm1$date), format='%Y-%m-%d')

adm1$cum_confirmed_cases_imputed_drop <- adm1$cum_confirmed_cases_imputed
adm1[adm1$cum_confirmed_cases_imputed < 10,]$cum_confirmed_cases_imputed_drop <- 0 
national <- aggregate(adm1[,c("cum_confirmed_cases_imputed", "cum_confirmed_cases_imputed_drop",
                              "cum_deaths_imputed")], 
                      by=list(adm1$date), FUN=sum)
colnames(national) <- c("date", "cases", "cases_drop", "deaths")
national <- arrange(national, date)

write.csv(national, paste0(data_dir, "processed/adm0/", country, "_cases_deaths.csv"))
national <- subset(national, date >= "2020-03-03" & date <= "2020-03-18")

# Calculate number of adm regions that enacted each policy 
policies <- aggregate(adm1[,policylist], by=list(adm1$date), FUN="sum") 
names(policies) <- c('date', 'p.1', 'p.2','p.3','p.4', 'p.5')

for (p in 1:5){ #calculate difference between t and t-1 for each policy for each day
  d.var <- paste0('diff.', p)  
  p.var <- paste0('p.', p)
  policies[,d.var] <- policies[,p.var] - lag(policies[,p.var])
}

policies <- subset(policies, !is.na(diff.1)) #remove NAs
policies[policies == 0] <- NA #replace zeros with NA

## Make timeseries panel 
pdf(paste0(output_dir, country, "_timeseries.pdf"), width = 8, height = 5)
par(mar=c(4, 8, 4, 8) + 0.1)
cases_max <- max(national$cases) + round(max(national$cases)/25)
policies_max <- max(policies$diff.1, 
                    policies$diff.2, 
                    policies$diff.3, 
                    policies$diff.4, 
                    policies$diff.5, na.rm = T) + 3 # find out max number of adm regions among all policies

## Plot first set of data and draw its axis
plot(national$date, national$cases, type="l", ylim=c(0,cases_max), 
     axes=FALSE, xlab="", ylab="", lwd=2, main=country) #cases
points(national$date, national$cases, pch=19)
axis(2, ylim=c(0,cases_max),las=1)  ## las=1 makes horizontal labels
mtext("Cumulative cases (solid) and deaths (dashed)",side=2,line=4)
lines(national$date, national$deaths, axes=FALSE,  lty=2, lwd=2) #deaths

## Allow a second plot on the same graph
par(new=TRUE)

plot(national$date, national$deaths, col = "white", xlab="", ylab="", #hidden plot
     ylim=c(0, policies_max), axes=FALSE,  lty=2, lwd=0.1)

segments(as.Date(policies$date)-0.2, 0, 
         as.Date(policies$date)-0.2, policies$diff.1, 
         col=color.list[1], lwd=1.5)
segments(as.Date(policies$date)-0.1, 0, 
         as.Date(policies$date)-0.1, policies$diff.2, 
         col=color.list[2], lwd=1.5)
segments(as.Date(policies$date), 0, 
         as.Date(policies$date), policies$diff.3, 
         col=color.list[3], lwd=1.5)
segments(as.Date(policies$date)+0.1, 0, 
         as.Date(policies$date)+0.1, policies$diff.4, 
         col=color.list[4], lwd=1.5)
segments(as.Date(policies$date)+0.2, 0, 
         as.Date(policies$date)+0.2, policies$diff.5, 
         col=color.list[5], lwd=1.5)

mtext("Containment policies (# of admin districts)",side=4,col="black",line=4) 
axis(4, ylim=c(0, policies_max), col="black",col.axis="black",las=1)

## Draw the time axis
axis.Date(1, national$date, 
          at=seq(min(national$date), max(national$date), "days"))
mtext("Date",side=1,col="black",line=2.5)  
dev.off()



#######################################################################

### Cases Map ###
library(tigris)
map <- states(cb=TRUE)
map <- subset(map, !(STATEFP %in% c("15","02","60","72","66", "69", "78")))
centroids <- gCentroid(map, byid=TRUE)
map$lon <- centroids$x
map$lat <- centroids$y
units <- as.data.frame(map[,c("NAME", "lon", "lat")]) 
colnames(units)[1] <- "adm1_name"
adm1$date <- as.Date(adm1$date, format='%Y-%m-%d')
adm1 <- adm1[adm1$date==max(adm1$date),]
adm1 <- merge(adm1, units, by="adm1_name")

pdf(paste0(output_dir, country, "_map.pdf"), width = 5, height = 5)
plot(map)
points(adm1$lon, adm1$lat, col=alpha("darkred", 0.35), 
       pch=19, cex=0.15*sqrt(adm1$cum_confirmed_cases_imputed))
dev.off()

##########################################################

country <- "FRA"
notify(country)

policylist <- c("no_gathering_national_100", 
                "home_isolation", 
                "social_distance_national", 
                "school_closure_national", 
                "event_cancel")
legend.list <- c("no gatherings of more than 100", 
                 "no gatherings of more than 1000", 
                 "social distancing", 
                 "school closure", 
                 "event cancellations") #set up legend
color.list <- c("darkgreen", 
                "mediumpurple4", 
                "mediumpurple2", 
                "darkblue", 
                "deeppink4")
  
  #load data
  adm1 <- read.csv(paste0(data_dir, "processed/adm1/", country, "_processed.csv"), stringsAsFactors = F) 
  adm1$date <- as.Date(as.character(adm1$date), format='%Y-%m-%d')
  
  #load latlon
  latlon.agg <- read.csv(paste0(data_dir, "interim/adm/adm1/adm1.csv"), stringsAsFactors = F) %>%
    dplyr::filter(adm0_name == country) %>%
    dplyr::select(adm1_name, lat = latitude, lon = longitude)

  if (country=="FRA"){ #clean region names
    latlon.agg$adm1_name[latlon.agg$adm1_name =="Auvergne-Rhône-Alpes" ] <- "AuvergneRhôneAlpes"
    latlon.agg$adm1_name[latlon.agg$adm1_name =="Bourgogne-Franche-Comté" ] <- "BourgogneFrancheComté"
    latlon.agg$adm1_name[latlon.agg$adm1_name =="Centre-Val de Loire"] <- "Centre"
    latlon.agg$adm1_name[latlon.agg$adm1_name =="Grand Est" ] <- "GrandEst"
    latlon.agg$adm1_name[latlon.agg$adm1_name =="Hauts-de-France" ] <- "HautsdeFrance"
    latlon.agg$adm1_name[latlon.agg$adm1_name =="Île-de-France" ] <- "IledeFrance"
    latlon.agg$adm1_name[latlon.agg$adm1_name =="Nouvelle-Aquitaine" ] <- "NouvelleAquitaine"
    latlon.agg$adm1_name[latlon.agg$adm1_name =="Pays de la Loire"  ] <- "PaysdelaLoire"
    latlon.agg$adm1_name[latlon.agg$adm1_name =="Provence-Alpes-Côte d'Azur"  ] <- "Paca"
  }  
  
# merge latlon
  adm1 <- left_join(adm1, latlon.agg, by = c("adm1_name"))
  adm1$lat <- as.numeric(adm1$lat)
  adm1$lon <- as.numeric(adm1$lon)


#----------------------------------------------------------------------------------------------------------------------------

  adm1$cum_confirmed_cases_imputed_drop <- adm1$cum_confirmed_cases_imputed
  adm1[adm1$cum_confirmed_cases_imputed < 10,]$cum_confirmed_cases_imputed_drop <- 0 
  national <- aggregate(adm1[,c("cum_confirmed_cases_imputed", "cum_confirmed_cases_imputed_drop")], 
                        by=list(adm1$date), FUN=sum)
  colnames(national) <- c("date", "cases", "cases_drop")
  national <- arrange(national, date)
  national <- subset(national, date >= "2020-02-27" & date <= "2020-03-18")
  write.csv(national, paste0(data_dir, "processed/adm0/", country, "_cases_deaths.csv"))
  
  
  national <-  read.csv(paste0(data_dir, 
                               "interim/france/france_jhu_cases.csv"), header = T, stringsAsFactors = F) %>% # merge JHU dataset because adm1 has no deaths
    select(date, cases = cum_confirmed_cases, deaths = cum_deaths)
  national$date <- as.Date(national$date, format='%Y-%m-%d')
  national <- subset(national, date >= "2020-02-27" & date <= "2020-03-18")
national <- arrange(national, date)


# Containment policies
#sum_polices <- colSums(adm2[,c(15:38,40)])
#sum_policies

ids <- unique(adm1$adm1_name) 
for (id in ids){
  if (nrow(subset(adm1, adm1_name==id))!= length(unique(adm1$date))){
    adm1 <- subset(adm1, adm1_name!=id)
  }
}

# Calculate number of adm regions that enacted each policy 
policies <- aggregate(adm1[,policylist], by=list(adm1$date), FUN="sum") 
names(policies) <- c('date', 'p.1', 'p.2','p.3','p.4', 'p.5')

for (p in 1:5){ #calculate difference between t and t-1 for each policy for each day
  d.var <- paste0('diff.', p)  
  p.var <- paste0('p.', p)
  policies[,d.var] <- policies[,p.var] - lag(policies[,p.var])
}

policies <- subset(policies, !is.na(diff.1)) #remove NAs
policies[policies == 0] <- NA #replace zeros with NA

## Make timeseries panel 
pdf(paste0(output_dir, country, "_timeseries.pdf"), width = 8, height = 5)
par(mar=c(4, 8, 4, 8) + 0.1)
cases_max <- max(national$cases) + round(max(national$cases)/25)
policies_max <- max(policies$diff.1, 
                    policies$diff.2, 
                    policies$diff.3, 
                    policies$diff.4, 
                    policies$diff.5, na.rm = T) + 3 # find out max number of adm regions among all policies

## Plot first set of data and draw its axis
plot(national$date, national$cases, type="l", ylim=c(0,cases_max), 
     axes=FALSE, xlab="", ylab="", lwd=2, main=country) #cases
points(national$date, national$cases, pch=19)
axis(2, ylim=c(0,cases_max),las=1)  ## las=1 makes horizontal labels
mtext("Cumulative cases (solid) and deaths (dashed)",side=2,line=4)
lines(national$date, national$deaths, axes=FALSE,  lty=2, lwd=2) #deaths

## Allow a second plot on the same graph
par(new=TRUE)

plot(national$date, national$deaths, col = "white", xlab="", ylab="", #hidden plot
     ylim=c(0, policies_max), axes=FALSE,  lty=2, lwd=0.1)

segments(as.Date(policies$date)-0.2, 0, 
         as.Date(policies$date)-0.2, policies$diff.1, 
         col=color.list[1], lwd=1.5)
segments(as.Date(policies$date)-0.1, 0, 
         as.Date(policies$date)-0.1, policies$diff.2, 
         col=color.list[2], lwd=1.5)
segments(as.Date(policies$date), 0, 
         as.Date(policies$date), policies$diff.3, 
         col=color.list[3], lwd=1.5)
segments(as.Date(policies$date)+0.1, 0, 
         as.Date(policies$date)+0.1, policies$diff.4, 
         col=color.list[4], lwd=1.5)
segments(as.Date(policies$date)+0.2, 0, 
         as.Date(policies$date)+0.2, policies$diff.5, 
         col=color.list[5], lwd=1.5)

mtext("Containment policies (# of admin districts)",side=4,col="black",line=4) 
axis(4, ylim=c(0, policies_max), col="black",col.axis="black",las=1)

## Draw the time axis
axis.Date(1, national$date, 
          at=seq(min(national$date), max(national$date), "days"))
mtext("Date",side=1,col="black",line=2.5)  

dev.off()


### Cases Map ###
map <- readOGR(paste0(data_dir, "interim/adm/adm1/adm1.shp"))
map <- subset(map, adm0_name == country)
map <- subset(map, longitude > -10 & latitude > 0)
map <- gSimplify(map, tol = 0.005)

#%>%
#       gSimplify(units, tol = 0.005)
adm1$date <- as.Date(adm1$date, format='%Y-%m-%d')
adm1 <- adm1[adm1$date==max(adm1$date),]

pdf(paste0(output_dir, country, "_map.pdf"), width = 5, height = 5)
plot(map)
points(adm1$lon, adm1$lat, col=alpha("darkred", 0.35), 
       pch=19, cex=0.15*sqrt(adm1$cum_confirmed_cases_imputed))
dev.off()

###############################################################

country <- "KOR"
notify(country)

  policylist <- c("emergency_declaration", 
                  "no_demonstration",
                  "social_distance_opt", 
                  "religious_closure",
                  "business_closure")
  legend.list <- c("emergency declaration", 
                   "no demonstration", 
                   "social distancing", 
                   "religious_closure", 
                   "business closure") #set up legend
  color.list <- c("darkred", 
                  "seagreen4", 
                  "mediumpurple2", 
                  "orange3", 
                  "tomato3")

adm1 <- read.csv(paste0(data_dir, "processed/adm1/KOR_processed.csv"), stringsAsFactors = F) 
adm1$date <- as.Date(as.character(adm1$date), format='%Y-%m-%d')

#load latlon
latlon.agg <- read.csv(paste0(data_dir, "interim/adm/adm1/adm1.csv"), stringsAsFactors = F) %>%
  dplyr::filter(adm0_name == country) %>%
  dplyr::select(adm1_name, lat = latitude, lon = longitude)

# merge latlon
adm1 <- left_join(adm1, latlon.agg, by = c("adm1_name"))
adm1$lat <- as.numeric(adm1$lat)
adm1$lon <- as.numeric(adm1$lon)


adm1$cum_confirmed_cases_drop <- adm1$cum_confirmed_cases
adm1[adm1$cum_confirmed_cases < 10,]$cum_confirmed_cases_drop <- 0 
national <- aggregate(adm1[,c("cum_confirmed_cases", "cum_confirmed_cases_drop",
                              "cum_deaths")], 
                      by=list(adm1$date), FUN=sum)
colnames(national) <- c("date", "cases", "cases_drop", "deaths")
national$date <- as.character(national$date)
national$date <- as.Date(national$date, format='%Y-%m-%d')
national <- arrange(national, date)
national <- subset(national, date >= "2020-02-17" & date <= "2020-03-18")

write.csv(national, paste0(data_dir, "processed/adm0/", country, "_cases_deaths.csv"))

# Containment policies
#sum_polices <- colSums(adm2[,c(15:38,40)])
#sum_policies

ids <- unique(adm1$adm1_name) 
for (id in ids){
  if (nrow(subset(adm1, adm1_name==id))!= length(unique(adm1$date))){
    adm1 <- subset(adm1$adm1_id!=id)
  }
}

# Calculate number of adm regions that enacted each policy 
policies <- aggregate(adm1[,policylist], by=list(adm1$date), FUN="sum") 
names(policies) <- c('date', 'p.1', 'p.2','p.3','p.4', 'p.5')

for (p in 1:5){ #calculate difference between t and t-1 for each policy for each day
  d.var <- paste0('diff.', p)  
  p.var <- paste0('p.', p)
  policies[,d.var] <- policies[,p.var] - lag(policies[,p.var])
}

policies <- subset(policies, !is.na(diff.1)) #remove NAs
policies[policies == 0] <- NA #replace zeros with NA

## Make timeseries panel 
pdf(paste0(output_dir, country, "_timeseries.pdf"), width = 8, height = 5)
par(mar=c(4, 8, 4, 8) + 0.1)
cases_max <- max(national$cases) + round(max(national$cases)/25)
policies_max <- max(policies$diff.1, 
                    policies$diff.2, 
                    policies$diff.3, 
                    policies$diff.4, 
                    policies$diff.5, na.rm = T) + 3 # find out max number of adm regions among all policies

## Plot first set of data and draw its axis
plot(national$date, national$cases, type="l", ylim=c(0,cases_max), 
     axes=FALSE, xlab="", ylab="", lwd=2, main=country) #cases
points(national$date, national$cases, pch=19)
axis(2, ylim=c(0,cases_max),las=1)  ## las=1 makes horizontal labels
mtext("Cumulative cases (solid) and deaths (dashed)",side=2,line=4)
lines(national$date, national$deaths, axes=FALSE,  lty=2, lwd=2) #deaths

## Allow a second plot on the same graph
par(new=TRUE)

plot(national$date, national$deaths, col = "white", xlab="", ylab="", #hidden plot
     ylim=c(0, policies_max), axes=FALSE,  lty=2, lwd=0.1)

segments(as.Date(policies$date)-0.2, 0, 
         as.Date(policies$date)-0.2, policies$diff.1, 
         col=color.list[1], lwd=1.5)
segments(as.Date(policies$date)-0.1, 0, 
         as.Date(policies$date)-0.1, policies$diff.2, 
         col=color.list[2], lwd=1.5)
segments(as.Date(policies$date), 0, 
         as.Date(policies$date), policies$diff.3, 
         col=color.list[3], lwd=1.5)
segments(as.Date(policies$date)+0.1, 0, 
         as.Date(policies$date)+0.1, policies$diff.4, 
         col=color.list[4], lwd=1.5)
segments(as.Date(policies$date)+0.2, 0, 
         as.Date(policies$date)+0.2, policies$diff.5, 
         col=color.list[5], lwd=1.5)

mtext("Containment policies (# of admin districts)",side=4,col="black",line=4) 
axis(4, ylim=c(0, policies_max), col="black",col.axis="black",las=1)

## Draw the time axis
axis.Date(1, national$date, 
          at=seq(min(national$date), max(national$date), "days"))
mtext("Date",side=1,col="black",line=2.5)  
dev.off()



#######################################################################

### Cases Map ###
map <- readOGR(paste0(data_dir, "interim/adm/adm1/adm1.shp"))
map <- subset(map, adm0_name == country)
map <- gSimplify(map, tol = 0.005)

#%>%
#       gSimplify(units, tol = 0.005)
adm1$date <- as.Date(adm1$date, format='%Y-%m-%d')
adm1 <- adm1[adm1$date==max(adm1$date),]

pdf(paste0(output_dir, country, "_map.pdf"), width = 5, height = 5)
plot(map)
points(adm1$lon, adm1$lat, col=alpha("darkred", 0.35), 
       pch=19, cex=0.15*sqrt(adm1$cum_confirmed_cases))
dev.off()
