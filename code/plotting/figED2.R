# source code from
# https://github.com/thimotei/CFR_calculation

# Code to fit GAMs to time-series of under-reporting estimates

# Set up paths and parameters ---------------------------------------------

# Load libraries
suppressPackageStartupMessages(library(tidyverse, padr, mgcv, gridExtra, ggplot2))

args <- commandArgs()
nd <- args[length(args)] == "--nd"

scale_cfr_temporal <- function(data_1_in, delay_fun = hospitalisation_to_death_truncated){
  
  case_incidence <- data_1_in$new_cases
  death_incidence <- data_1_in$new_deaths
  cumulative_known_t <- NULL # cumulative cases with known outcome at time tt
  # Sum over cases up to time tt
  for(ii in 1:nrow(data_1_in)){
    known_i <- 0 # number of cases with known outcome at time ii
    for(jj in 0:(ii - 1)){
      known_jj <- (case_incidence[ii - jj]*delay_fun(jj))
      known_i <- known_i + known_jj
    }
    cumulative_known_t <- c(cumulative_known_t,known_i) # Tally cumulative known
  }
  
  # naive CFR value
  b_tt <- sum(death_incidence)/sum(case_incidence) 
  # corrected CFR estimator
  p_tt <- (death_incidence/cumulative_known_t) %>% pmin(.,1)
  
  data.frame(nCFR = b_tt, cCFR = p_tt, total_deaths = sum(death_incidence), 
             cum_known_t = round(cumulative_known_t), total_cases = sum(case_incidence))
}


#get time varying cfr data for a country
get_plot_data <- function(country_name, data = allTogetherCleanA){
  
  true_cfr <- 1.4/100
  
  #filter country data and adjust date
  country_data <- data %>% 
    filter(country == country_name) %>% 
    mutate(date = date - zmeanHDT)
  
  #date where cumulative deaths passed 10
  death_threshold_date <- country_data %>% 
    mutate(death_cum_sum = cumsum(new_deaths)) %>% 
    filter(death_cum_sum >= 10) %>% 
    pull(date) %>% 
    min()
  
  #return adjusted date and reporting_estimate
  cfr <- scale_cfr_temporal(country_data) %>% 
    as_tibble() %>% 
    mutate(reporting_estimate = true_cfr/cCFR) %>% 
    mutate(reporting_estimate = pmin(reporting_estimate, 1),
           country = country_data$country,
           date = country_data$date,
           date_num = as.numeric(country_data$date),
           deaths = country_data$new_deaths,
           cases_known = cum_known_t) %>% 
    filter(date >= death_threshold_date) %>% 
    select(country, date, date_num, reporting_estimate, deaths, cases_known)
  
  return(cfr)
  
}

# Set parameters
zmeanHDT <- 13
zsdHDT <- 12.7
zmedianHDT <- 9.1
muHDT <- log(zmedianHDT)
sigmaHDT <- sqrt(2*(log(zmeanHDT) - muHDT))
cCFRBaseline <- 1.38
cCFREstimateRange <- c(1.23, 1.53)
#cCFRIQRRange <- c(1.3, 1.4)


# Hospitalisation to death distribution
hospitalisation_to_death_truncated <- function(x) {
  plnorm(x + 1, muHDT, sigmaHDT) - plnorm(x, muHDT, sigmaHDT)
}

cutoff_date <- read_csv("code/data/cutoff_dates.csv", col_types = cols())
cutoff_date <- cutoff_date[cutoff_date$tag == 'default', 'end_date'] %>%
  unlist() %>%
  lubridate::ymd()

# Load data -----------------------------------------------------
if (nd) {
  allDat <- read_csv("data/raw/multi_country/ecdc.csv", col_types = cols())
} else {
  httr::GET("https://opendata.ecdc.europa.eu/covid19/casedistribution/csv", httr::authenticate(":", ":", type="ntlm"), httr::write_disk(tf <- tempfile(fileext = ".csv")))
  allDat <- read_csv(tf, col_types = cols())
}

allDatDesc <- allDat %>% 
  dplyr::arrange(countriesAndTerritories, dateRep) %>% 
  dplyr::mutate(dateRep = lubridate::dmy(dateRep))%>% 
  dplyr::rename(date = dateRep, new_cases = cases, new_deaths = deaths, country = countriesAndTerritories) %>%
  dplyr::select(date, country, new_cases, new_deaths) %>%
  dplyr::filter(country %in% c("China", "United_States_of_America", "Italy", "Iran", "France", "South_Korea")) %>%
  dplyr::filter(date <= cutoff_date) %>%
  dplyr::arrange(country, date)

# Do analysis
allTogetherCleanA <- allDatDesc %>%
  dplyr::group_by(country) %>%
  padr::pad() %>%
  dplyr::mutate(new_cases = tidyr::replace_na(new_cases, 0),
                new_deaths = tidyr::replace_na(new_deaths, 0)) %>%
  #What is this doing?
  dplyr::group_by(country) %>%
  dplyr::mutate(cum_deaths = sum(new_deaths)) %>%
  dplyr::filter(cum_deaths > 0) %>%
  dplyr::select(-cum_deaths)


# Plot rough reporting over time -----------------------------------------

plot_country_names <- allTogetherCleanA %>% 
  dplyr::mutate(death_cum_sum = cumsum(new_deaths)) %>% 
  dplyr::filter(death_cum_sum >= 10) %>% 
  dplyr::mutate(max_deaths = max(death_cum_sum)) %>% 
  dplyr::arrange(-max_deaths) %>% 
  dplyr::group_by(country) %>% 
  dplyr::filter(n() >= 8) %>%
  dplyr::pull(country) %>% 
  unique()
plot_country_names <- c("China", "Iran", "South_Korea", "France", "Italy", "United_States_of_America")

plots <- list()
plots_data <- data.frame()
for (country_name in plot_country_names){
  plot_data <- get_plot_data(country_name = country_name)
  
  plot_data <- plot_data %>%
    dplyr::mutate(log_est = log(reporting_estimate),
                  lag_log_est = dplyr::lag(log_est),
                  log_diff = log_est - lag_log_est) %>%
    dplyr::slice(2:dplyr::n())
  plots_data <- rbind(plots_data, plot_data)
  mean_log_diff <- mean(plot_data$log_diff)
  p <- ggplot2::ggplot(plot_data, ggplot2::aes(x=date, y=log_diff)) +
    ggplot2::geom_point() +
    ggplot2::geom_hline(yintercept=mean_log_diff) +
    ggplot2::labs(
      subtitle=paste0(country_name, " (Mean: ", round(mean_log_diff, 3), ")"),
      y="",
      x="") +
    ggplot2::theme_bw()

  plots[[country_name]] = p
  
}

plots = arrangeGrob(grobs = plots,
                    ncol = 2,
                    left = "First differences in log(% of cases reported)", 
                    rot = 90)

write_csv(plots_data, 'results/source_data/ExtendedDataFigure2.csv')

ggsave('results/figures/appendix/figED2.pdf',
       plots,
       width = 8,
       height = 10)

