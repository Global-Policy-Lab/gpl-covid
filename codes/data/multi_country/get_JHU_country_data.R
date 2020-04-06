get_jhu_data <- function(country = c("US", "Iran", "Korea, South", "Italy", "China",
                                     "Afghanistan", "Albania", "Algeria", "Andorra", 
                                     "Argentina", "Armenia", "Australia", "Austria", 
                                     "Azerbaijan", "Bahrain", "Bangladesh", "Belarus", 
                                     "Belgium", "Bhutan", "Bolivia", "Bosnia and Herzegovina", 
                                     "Brazil", "Brunei", "Bulgaria", "Burkina Faso", 
                                     "Cambodia", "Cameroon", "Canada", "Chile",
                                     "Colombia", "Congo (Kinshasa)", "Costa Rica", "Cote d'Ivoire", 
                                     "Croatia", "Cruise Ship", "Cuba", "Cyprus", "Czechia", 
                                     "Denmark", "Dominican Republic", "Ecuador", "Egypt", 
                                     "Estonia", "Finland", "France", "French Guiana", "Georgia", 
                                     "Germany", "Greece", "Guyana", "Holy See", "Honduras", 
                                     "Hungary", "Iceland", "India", "Indonesia", "Iraq", 
                                     "Ireland", "Israel", "Jamaica", "Japan", "Jordan", 
                                     "Kuwait", "Latvia", "Lebanon", 
                                     "Liechtenstein", "Lithuania", "Luxembourg", "Malaysia", 
                                     "Maldives", "Malta", "Martinique", "Mexico", "Moldova", 
                                     "Monaco", "Mongolia", "Morocco", "Nepal", "Netherlands", 
                                     "New Zealand", "Nigeria", "North Macedonia", "Norway", 
                                     "Oman", "Pakistan", "Panama", "Paraguay", "Peru", 
                                     "Philippines", "Poland", "Portugal", "Qatar", "Reunion", 
                                     "Romania", "Russia", "San Marino", "Saudi Arabia", "Senegal", 
                                     "Serbia", "Singapore", "Slovakia", "Slovenia", "South Africa", 
                                     "Spain", "Sri Lanka", "Sweden", "Switzerland", "Taiwan*", 
                                     "Thailand", "Togo", "Tunisia", "Turkey", "Ukraine", 
                                     "United Arab Emirates", "United Kingdom", "Vietnam"),
                         province_states_to_include = NULL){
  # This checks that the country is in the above vector
  country <- match.arg(country)
  urls <- c(
    "https://raw.githubusercontent.com/CSSEGISandData/COVID-19/master/csse_covid_19_data/csse_covid_19_time_series/time_series_covid19_confirmed_global.csv",
    "https://raw.githubusercontent.com/CSSEGISandData/COVID-19/master/csse_covid_19_data/csse_covid_19_time_series/time_series_covid19_deaths_global.csv",
    "https://raw.githubusercontent.com/CSSEGISandData/COVID-19/master/csse_covid_19_data/csse_covid_19_time_series/time_series_covid19_recovered_global.csv"
  )
  # Download the 3 csvs direct from the urls into tibbles
  jhu_covid_cases <- urls %>% map(read_csv,
                                  col_types = cols(
                                    .default = col_double(),
                                    `Province/State` = col_character(),
                                    `Country/Region` = col_character()
                                  ))
  
  # add the variable types as a column to each tibble
  jhu_covid_cases <- list(jhu_covid_cases, c("cum_confirmed_cases",
                                             "cum_deaths",
                                             "cum_recoveries")) %>% 
    pmap(~{
      .x %>% 
        mutate(variable = .y)
    }) %>% 
    bind_rows()
  
  
  jhu_covid_cases <- jhu_covid_cases %>% 
    pivot_longer(cols = matches("[0-9]+/[0-9]+/[0-9]+"),
                 names_to = "date",
                 values_to = "value") %>% 
    rename(province_state = `Province/State`,
           country_region = `Country/Region`) %>% 
    select(-Lat, -Long) %>% 
    pivot_wider(id_cols = c("province_state", "country_region", "date"),
                names_from = variable,
                values_from = value) %>% 
    mutate(date = as.Date(date, format = "%m/%d/%y")) 
  
  if(!is.null(province_states_to_include)){
    jhu_covid_cases <- jhu_covid_cases %>% 
      filter(province_state %in% province_states_to_include)
  }
  
  jhu_covid_cases <- jhu_covid_cases %>% 
    filter(country_region %>% str_detect(country)) %>% 
    mutate(active_cases = cum_confirmed_cases - cum_recoveries - cum_deaths)
  
  # Expand to include all dates
  jhu_covid_cases <- jhu_covid_cases %>% 
    unite(tmp_id, province_state, country_region, remove = FALSE) %>% 
    complete(tmp_id, date)
  jhu_covid_cases %>% 
    select(-tmp_id)
}

do_issues_exist <- function(data, variable){
  data %>% 
    arrange(tmp_id, date) %>% 
    group_by(tmp_id) %>% 
    filter({{variable}} < lag({{variable}})) %>% 
    nrow() %>% 
    magrittr::is_greater_than(0)
}

examine_issues <- function(data, variable){
  data %>% 
    arrange(tmp_id, date) %>% 
    group_by(tmp_id) %>% 
    filter({{variable}} < lag({{variable}}) | {{variable}} > lead({{variable}}) | lead({{variable}}) > lead({{variable}}, 2))
}

fix_issues <- function(data){
  # Check if there are cases where cumulative cases go down
  # Need to fix these one by one as the fix may cause other problems
  # impute is an indicator of whether to impute variables or set them to missing
  fix_first_issue <- function(data, variable, impute = FALSE){
    first_issue <- data %>% 
      arrange(tmp_id, date) %>% 
      group_by(tmp_id) %>% 
      filter({{variable}} < lag({{variable}}) | {{variable}} > lead({{variable}}) | lead({{variable}}) > lead({{variable}}, 2)) %>% 
      ungroup() %>% 
      slice(1:3)
    if(all((first_issue %>% pull({{variable}}) %>% .[1]) == 0, (first_issue %>% pull({{variable}}) %>% .[3]) == 0)){
      data <- data %>% 
        mutate({{variable}} := if_else(tmp_id == first_issue$tmp_id[2] & date == first_issue$date[2], 0,
                                       {{variable}}))
    } else if((first_issue %>% pull({{variable}}) %>% .[1]) <= (first_issue %>% pull({{variable}}) %>% .[3])){
      # If the first and last go up then log interpolate the second
      data <- data %>% 
        mutate({{variable}} := if_else(tmp_id == first_issue$tmp_id[2] & date == first_issue$date[2],
                                       round(exp((log(lead({{variable}})) + log(lag({{variable}})))/2)),
                                       {{variable}}))
    } else if ((first_issue %>% pull({{variable}}) %>% .[1]) == 135 & (first_issue %>% pull({{variable}}) %>% .[3]) == 118) {
      # This is a weird case in S Korea recoveries with a pattern of 41 135 135 118 118 247 - just log interpolate all 4 in the middle
      sequence <- data %>% 
        filter(tmp_id == first_issue$tmp_id[2] & date %in% seq.Date(first_issue$date[1] - 1, first_issue$date[1] + 4, by = "days"))
      if(identical(sequence %>% pull({{variable}}), c(41, 135, 135, 118, 118, 247))){
        new_values_for_chunk <- round(exp(zoo::na.approx(c(log(41), NA_real_, NA_real_, NA_real_, NA_real_, log(247)))))
        new_variable <- data %>% 
          pull({{variable}})
        new_variable[data$tmp_id == first_issue$tmp_id[1] & data$date %in% sequence$date] <- new_values_for_chunk
        data <- data %>% 
          mutate({{variable}} := new_variable)
      }
    } else if (all(first_issue$cum_confirmed_cases[3] == 0, first_issue$cum_deaths[3] == 0, first_issue$cum_recoveries[3] == 0)) {
      # This case is one where all the variables just go to zero and usually stay there (last one might be NA) - 
      # just delete these rows
      tmp <- data %>% 
        filter(date >= first_issue$date[3] & tmp_id == first_issue$tmp_id[3]) %>% 
        pull({{variable}})
      if(all(tmp == 0 | is.na(tmp))){
        data <- data %>% 
          filter(!(date >= first_issue$date[3] & tmp_id == first_issue$tmp_id[3]))
      }
    } else {
      # stop("Need to deal with an edge case of cumulative cases declining in the data. Comment out this error then run again and you will be debugging in the right place.")
      browser()
    }
    data
  }
  # filter to observations for which cum_confirmed_cases
  # is greater than 10
  # data <- data %>% 
  #   filter(cum_confirmed_cases >= 10)
  
  data <- data %>% 
    unite(tmp_id, province_state, country_region)
  
  # Expand to include all dates again in case some disappeared
  data <- data %>% 
    complete(tmp_id, date) %>% 
    group_by(tmp_id) %>% 
    filter({
      # This filters on whether we've seen our first observation above 10 in a place
      cumsum(!is.na(cum_confirmed_cases)) > 0
    }) %>% 
    ungroup()
  
  if(!"cum_confirmed_cases_imputed" %in% names(data)){
    data <- data %>% 
      mutate(cum_confirmed_cases_imputed = cum_confirmed_cases)
  }
  
  if(!"cum_recoveries_imputed" %in% names(data)){
    data <- data %>% 
      mutate(cum_recoveries_imputed = cum_recoveries)
  }
  
  if(!"cum_deaths_imputed" %in% names(data)){
    data <- data %>% 
      mutate(cum_deaths_imputed = cum_deaths)
  }
  
  while(do_issues_exist(data, cum_confirmed_cases_imputed)){
    warning("Fixing an issue with cum_confirmed_cases")
    data <- fix_first_issue(data, cum_confirmed_cases_imputed, impute = TRUE)
    data <- fix_first_issue(data, cum_confirmed_cases, impute = FALSE)
  }
  data %>% 
    mutate(active_cases_imputed = cum_confirmed_cases_imputed - 
             cum_recoveries_imputed - 
             cum_deaths_imputed) %>% 
    separate(tmp_id, c("province_state", "country_region"), sep = "_")
}
