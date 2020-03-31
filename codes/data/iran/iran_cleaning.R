# --------------------------------------------------------
# 
# Final cleaning and merge of Covid-19 data for Iran.
#
# 
# NOTE ABOUT THE DATA: Iran has generally reported adm2 level new cases. 
# However, on the dates of March 2 and 3, 2020, Iran only reported
# national new cases, not broken down to the adm2 level. We will handle
# this in two different options:
# 1) Report as missing any adm2 outcomes for these two days.
# 2) Disaggregate the national new cases on March 2 and 3 to
#    the adm2 level, using March 1 new cases as adm2-weights.
# 
# 
# Andy Hultgren, hultgren@berkeley.edu
# 3/15/20
# 
# --------------------------------------------------------


# Clean the workspace and load packages

# setwd('C:/Users/Andy Hultgren/Documents/ARE/GPL/coronavirus_sprint/AAA_repo/gpl-covid')

rm(list=ls())

require(dplyr)
require(ggplot2)
require(reshape2)

# Let's set up Fiona's excellent plotting theme.
myThemeStuff <- theme(panel.background = element_rect(fill = NA),
                      panel.border = element_rect(fill = NA, color = "black"),
                      panel.grid.major = element_blank(),
                      panel.grid.minor = element_blank(),
                      axis.ticks = element_line(color = "gray5"),
                      axis.text = element_text(color = "black", size = 10),
                      axis.title = element_text(color = "black", size = 12),
                      legend.key = element_blank()
)

# Set paths
cases_in <- 'data/interim/iran/covid_iran_cases.csv' 
policies_in <- 'data/interim/iran/covid_iran_policies.csv' 
file_out <- 'data/interim/iran/IRN_interim.csv' 
file_out_adm0 <- 'data/interim/iran/adm0/IRN_interim.csv' 
dir.create('data/interim/iran/adm0', showWarnings=FALSE)

### !!! User defined !!!
### Iran did not report subnational data for 3/2 and 3/3/20. One option is to disaggregate the national
### new cases to adm2 units using the most recent measure of cumulative cases (3/1/20) as weights.
weights.date <- '3/1/2020'
missing.dates <- c('3/2/2020', '3/3/2020')



### Load cases data and reshape from wide to long
cases.data <- read.csv(cases_in)
cases.data <- melt(cases.data, id.vars=c('date'))
cases.data$variable <- as.character(cases.data$variable)
cases.data$value <- as.numeric(cases.data$value)

# units are coded as [adm2_name]_[adm1_number].  Break out adm2_name and adm1_number.
cases.data$adm0_name <- 'IRN'
cases.data$adm1_name <- NA
cases.data$adm2_name <- NA

cases.data$adm1_name <- as.numeric( sapply( 1:length(cases.data$variable), function(x) {
  ifelse( (substr(cases.data$variable[x], nchar(cases.data$variable[x])-2, nchar(cases.data$variable[x])-2) == '_'), 
          substr(cases.data$variable[x], nchar(cases.data$variable[x]), nchar(cases.data$variable[x])), 
          NA) 
}))

cases.data$adm2_name <- sapply( 1:length(cases.data$variable), function(x) {
  ifelse( (substr(cases.data$variable[x], nchar(cases.data$variable[x])-2, nchar(cases.data$variable[x])-2) == '_'), 
          substr(cases.data$variable[x], 1, nchar(cases.data$variable[x])-3), 
          NA) 
})

# Move national deaths to its own column and then drop the (now) unnecessary rows and 'variable' column
cases.data$new_deaths_national <- NA
cases.data$new_deaths_national[cases.data$variable == 'new_confirmed_national'] <- cases.data$value[cases.data$variable == 'new_deaths_national']
cases.data <- cases.data[ cases.data$variable != 'new_deaths_national', ]
cases.data$variable <- NULL
colnames(cases.data)[ colnames(cases.data)=='value' ] <- 'new_confirmed_cases'

# Report cumulative cases and deaths, treating days with missing data as missing in the cumulative data
cases.data$tmp <- ifelse(is.na(cases.data$new_confirmed_cases),0,cases.data$new_confirmed_cases)
cases.data <- cases.data %>%
  group_by(adm0_name, adm1_name, adm2_name) %>%
  mutate( cum_confirmed_cases = cumsum(tmp) ) %>%
  mutate( cum_deaths = cumsum(new_deaths_national)) %>%
  ungroup()

# Re-insert missing values where subnational data was missing
cases.data$cum_confirmed_cases[ is.na(cases.data$new_confirmed_cases) ] <- NA

# Do the cumulative sum, imputing new cases at the adm2 level for the days in which it was not 
# reported (3/2/20 and 3/2/20). Save as a separate set of columns with "_imputed" names.
cases.data$new_confirmed_cases_imputed <- cases.data$new_confirmed_cases

weights <- cases.data$new_confirmed_cases[ (as.character(cases.data$date)==weights.date) & is.na(cases.data$new_deaths_national) ]
weights <- weights / sum(weights)

for (d in missing.dates) {
  aggregate_to_distribute <- cases.data$new_confirmed_cases[ (as.character(cases.data$date)==d) & is.na(cases.data$adm1_name) ]
  
  cases.data$new_confirmed_cases_imputed[ (as.character(cases.data$date)==d) & is.na(cases.data$new_deaths_national) ] <- round( weights * aggregate_to_distribute)
}

# Report cumulative cases and deaths, using imputed data for days with missing data
cases.data <- cases.data %>%
  group_by(adm0_name, adm1_name, adm2_name) %>%
  mutate( cum_confirmed_cases_imputed = cumsum(new_confirmed_cases_imputed) ) %>%
  ungroup()


# Clean up
cases.data$tmp <- NULL
cases.data$date <- as.Date(cases.data$date, '%m/%d/%Y')


### Load and merge the policies
policies.data <- read.csv(policies_in)

policies.data.end <- min(which(policies.data$date==''))
policies.data <- policies.data[1:policies.data.end-1,]
policy.types <- unique(as.character(policies.data$Policy.type))
policies.data$date <- as.Date(policies.data$date, '%m/%d/%Y')

tmp <- as.data.frame(matrix(0,ncol=length(policy.types),nrow=dim(cases.data)[1]))
colnames(tmp) <- policy.types

cases.data <- cbind(cases.data, tmp)


for (i in 1:dim(policies.data)[1]) {
  
  p <- as.character(policies.data$Policy.type[i])
  d <- policies.data$date[i]
  
  if(policies.data$Locations.affected[i]=='National') {
    
    cases.data[ cases.data$date >= d, p ] <- 1
  
  } else {
    
    locations.list <- strsplit(as.character(policies.data$Locations.affected[i]), ',')[[1]]
    my_filter <- (as.character(cases.data$adm2_name) %in% locations.list) & (cases.data$date >= d)
    cases.data[ my_filter, p ] <- 1
    
  }
  
}

cases.data <- cases.data[c('date', 'adm0_name', 'adm1_name', 'adm2_name', policy.types, 'new_confirmed_cases', 'cum_confirmed_cases', 
                           'new_confirmed_cases_imputed', 'cum_confirmed_cases_imputed', 
                           'new_deaths_national', 'cum_deaths')]

# Split out adm2 and adm0 data, and write to .csv
cases.data.adm2 <- cases.data[ !is.na(cases.data$adm2_name), 
                               c('date', 'adm0_name', 'adm1_name', 'adm2_name', policy.types, 'new_confirmed_cases', 'cum_confirmed_cases', 
                                 'new_confirmed_cases_imputed', 'cum_confirmed_cases_imputed')]

cases.data.adm0 <- cases.data[ is.na(cases.data$adm2_name), 
                               c('date', 'adm0_name', policy.types, 'new_confirmed_cases', 'cum_confirmed_cases', 
                                 'new_deaths_national', 'cum_deaths')]

write.csv(cases.data.adm2, file_out, row.names=FALSE)
write.csv(cases.data.adm0, file_out_adm0, row.names=FALSE)


