# --------------------------------------------------------
#
# Final cleaning and merge of Covid-19 data for Iran.
#
#
# NOTE ABOUT THE DATA: Iran has generally reported adm1 level new cases.
# However, on the dates of March 2 and 3, 2020, Iran only reported
# national new cases, not broken down to the adm1 level. We will handle
# this in two different options:
# 1) Report as missing any adm1 outcomes for these two days.
# 2) Disaggregate the national new cases on March 2 and 3 to
#    the adm1 level, using March 1 new cases as adm1-weights.
#
#
# Widespread screening on 3/3/2020
# The health minister, Saeed Namaki, on Sunday announced a plan to dispatch
# a force of 300,000 plainclothes Basij militiamen that would go house to
# house to screen residents and disinfect their homes.  Iranian doctors and
# politicians immediately criticized the plan, saying that untrained militiamen
# were more likely to spread the virus than to contain it.  The latest plan
# announced on Thursday did not mention door-to-door screening.
# https://www.nytimes.com/2020/03/03/world/middleeast/coronavirus-iran.html,
# https://www.cnbc.com/2020/03/01/reuters-america-update-3-irans-coronavirus-death-toll-jumps-to-54-with-978-infected.html
# [This plan was cancelled. https://www.dailymail.co.uk/news/article-8082443/ANOTHER-senior-Iranian-official-dies-coronavirus.html]
# On Sunday, Namaki had said that 300,000 teams, including members of the Basij militia,
# would be sent out to perform door-to-door coronavirus screening.
# The plan sparked criticism from Iranians online about the possibility of
# the teams spreading, rather than stopping, infections.
#
# Andy Hultgren, hultgren@berkeley.edu
# 3/15/20
#
# --------------------------------------------------------


# Clean the workspace and load packages

rm(list=ls())

options (warn = -1)
suppressPackageStartupMessages(require(tidyverse))
suppressPackageStartupMessages(require(reshape2))

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
policies_in <- 'data/interim/iran/IRN_policy_data_sources.csv'
file_out <- 'data/interim/iran/IRN_interim.csv'
file_out_adm0 <- 'data/interim/iran/adm0/IRN_interim.csv'
dir.create('data/interim/iran/adm0', showWarnings=FALSE)

### !!! User defined !!!
### Iran did not report subnational data for 3/2 and 3/3/20. One option is to disaggregate the national
### new cases to adm1 units using the most recent measure of cumulative cases (3/1/20) as weights.
weights.date <- '3/1/2020'
missing.dates <- c('3/2/2020', '3/3/2020')



### Load cases data and reshape from wide to long
cases.data <- read.csv(cases_in)
cases.data <- melt(cases.data, id.vars=c('date'))
cases.data$variable <- as.character(cases.data$variable)
cases.data$value <- as.numeric(cases.data$value)

# units are coded as [adm1_name]_[region_number_from_wiki].  Pull out adm1_name.
cases.data$adm0_name <- 'IRN'
cases.data$adm1_name <- NA

cases.data$adm1_name <- sapply( 1:length(cases.data$variable), function(x) {
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
  group_by(adm0_name, adm1_name) %>%
  mutate( cum_confirmed_cases = cumsum(tmp) ) %>%
  mutate( cum_deaths = cumsum(new_deaths_national)) %>%
  ungroup()

# Re-insert missing values where subnational data was missing
cases.data$cum_confirmed_cases[ is.na(cases.data$new_confirmed_cases) ] <- NA

# Do the cumulative sum, imputing new cases at the adm1 level for the days in which it was not
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
  group_by(adm0_name, adm1_name) %>%
  mutate( cum_confirmed_cases_imputed = cumsum(new_confirmed_cases_imputed) ) %>%
  ungroup()


# Clean up
cases.data$tmp <- NULL
cases.data$date <- as.Date(cases.data$date, '%m/%d/%Y')


### Load and merge the policies
policies.data <- read.csv(policies_in) %>%
  mutate(
    policy = as.character(policy),
    policy = if_else(optional=="Y", paste0(policy, "_opt"), policy)
  )

policy.types <- unique(as.character(policies.data$policy))
policies.data$date <- as.Date(policies.data$date_start, '%m/%d/%Y')

tmp <- as.data.frame(matrix(0,ncol=length(policy.types),nrow=dim(cases.data)[1]))
colnames(tmp) <- policy.types

cases.data <- cbind(cases.data, tmp)


for (i in 1:dim(policies.data)[1]) {

  p <- as.character(policies.data$policy[i])
  d <- policies.data$date[i]

  if(policies.data$adm1_name[i]=='All') {

    cases.data[ cases.data$date >= d, p ] <- 1

  } else {

    locations.list <- strsplit(as.character(policies.data$adm1_name[i]), ', ')[[1]]
    my_filter <- (as.character(cases.data$adm1_name) %in% locations.list) & (cases.data$date >= d)
    cases.data[ my_filter, p ] <- 1

  }

}

cases.data <- cases.data[c('date', 'adm0_name', 'adm1_name', policy.types, 'new_confirmed_cases', 'cum_confirmed_cases',
                           'new_confirmed_cases_imputed', 'cum_confirmed_cases_imputed',
                           'new_deaths_national', 'cum_deaths')]

# Split out adm1 and adm0 data, and write to .csv
cases.data.adm1 <- cases.data[ !is.na(cases.data$adm1_name),
                               c('date', 'adm0_name', 'adm1_name', policy.types, 'new_confirmed_cases', 'cum_confirmed_cases',
                                 'new_confirmed_cases_imputed', 'cum_confirmed_cases_imputed')]

cases.data.adm0 <- cases.data[ is.na(cases.data$adm1_name),
                               c('date', 'adm0_name', policy.types, 'new_confirmed_cases', 'cum_confirmed_cases',
                                 'new_deaths_national', 'cum_deaths')]

write.csv(cases.data.adm1, file_out, row.names=FALSE)
write.csv(cases.data.adm0, file_out_adm0, row.names=FALSE)
