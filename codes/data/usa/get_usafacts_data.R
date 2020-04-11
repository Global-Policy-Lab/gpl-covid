get_usafacts_data <- function(){
  urls <- c(
    "https://usafactsstatic.blob.core.windows.net/public/data/covid-19/covid_confirmed_usafacts.csv",
    "https://usafactsstatic.blob.core.windows.net/public/data/covid-19/covid_deaths_usafacts.csv"
  )
  
  # Download the 2 csvs direct from the urls into tibbles
  usa_facts_covid_cases <- urls %>% map(read_csv,
                                        col_types = cols(
                                          .default = col_number(),
                                          countyFIPS = col_character(),
                                          stateFIPS = col_character(),
                                          `County Name` = col_character(),
                                          State = col_character()
                                        ))

  # add the variable types as a column to each tibble
  usa_facts_covid_cases <- list(usa_facts_covid_cases, c("cum_confirmed_cases",
                                             "cum_deaths")) %>% 
    pmap(~{
      .x %>% 
        mutate(variable = .y) %>%
        rename_at(vars(matches("/20$")), 
                       ~str_replace(.x, "/20$", "/2020"))
    }) %>% 
    bind_rows()

  usa_facts_covid_cases <- usa_facts_covid_cases %>% 
    select(-matches("X[0-9]+"))
  
  usa_facts_covid_cases <- usa_facts_covid_cases %>% 
    mutate(`County Name` = if_else(`County Name` == "Matthews County" & State == "VA",
                                   "Mathews County", `County Name`) %>% 
             str_replace(" city", " City") %>% 
             str_replace("Lac qui ", "Lac Qui ") %>% 
             str_replace("Doña Ana ", "Dona Ana ") %>% 
             str_replace("Broomfield County and City", "Broomfield County"))
  
  usa_facts_covid_cases <- usa_facts_covid_cases %>% 
    pivot_longer(cols = matches("[0-9]+/[0-9]+/[0-9]+"),
                 names_to = "date",
                 values_to = "value") %>% 
    rename(county_fips = `countyFIPS`,
           state_fips = `stateFIPS`,
           adm2_name = `County Name`,
           adm1_name = `State`)

    # check for duplicates
  duplicates <- usa_facts_covid_cases %>% 
    group_by(county_fips, state_fips, adm2_name, adm1_name, date, variable) %>% 
    arrange(county_fips, state_fips, adm2_name, adm1_name, variable, date) %>% 
    filter(n() > 1) 
  
  # just choose the max if there are duplicates. They said they would be fixed up 
  # so this should actually do nothing from 03/27
  usa_facts_covid_cases <- usa_facts_covid_cases %>% 
    group_by(county_fips, state_fips, adm2_name, adm1_name, date, variable) %>% 
    arrange(county_fips, state_fips, adm2_name, adm1_name, variable, date) %>% 
    summarise(value = max(value))
  
  usa_facts_covid_cases %>%
    ungroup() %>% 
    pivot_wider(id_cols = c("county_fips", "state_fips", "adm2_name", "adm1_name", "date"),
                names_from = variable,
                values_from = value) %>% 
    mutate(date = as.Date(date, format = "%m/%d/%y")) %>% 
    arrange(county_fips, state_fips, adm2_name, adm1_name, date) %>% 
    mutate(county_fips = county_fips %>% str_pad(5, pad = 0)) %>% 
    mutate(state_fips = state_fips %>% str_pad(2, pad = 0))
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
      filter(cum_confirmed_cases >= 10 | lead(cum_confirmed_cases) >= 10) %>% 
      arrange(tmp_id, date) %>% 
      group_by(tmp_id) %>% 
      filter({{variable}} < lag({{variable}}) | {{variable}} > lead({{variable}}) | lead({{variable}}) > lead({{variable}}, 2)) %>% 
      ungroup() %>% 
      slice(1:3)
    if(all((first_issue %>% pull({{variable}}) %>% .[1]) == 0, (first_issue %>% pull({{variable}}) %>% .[3]) == 0)){
      if(impute){
        data <- data %>% 
          mutate({{variable}} := if_else(tmp_id == first_issue$tmp_id[2] & date == first_issue$date[2], 0,
                                         {{variable}}))
      } else {
        data <- data %>% 
          mutate({{variable}} := if_else(tmp_id == first_issue$tmp_id[2] & date == first_issue$date[2], NA_real_,
                                         {{variable}}))
      }
    } else if((first_issue %>% pull({{variable}}) %>% .[1]) <= (first_issue %>% pull({{variable}}) %>% .[3])){
      if(impute){
        # If the first and last go up then log interpolate the second
        data <- data %>% 
          mutate({{variable}} := if_else(tmp_id == first_issue$tmp_id[2] & date == first_issue$date[2],
                                         round(exp((log(lead({{variable}})) + log(lag({{variable}})))/2)),
                                         {{variable}}))
      } else {
        data <- data %>% 
          mutate({{variable}} := if_else(tmp_id == first_issue$tmp_id[2] & date == first_issue$date[2],
                                         NA_real_,
                                         {{variable}}))
      }
    } else {
      # stop("Need to deal with an edge case of cumulative cases declining in the data. Comment out this error then run again and you will be debugging in the right place.")
      warning("Found an unhandled example of a cumulative variable decreasing.")
      data <- data %>% 
        mutate({{variable}} := if_else(tmp_id == first_issue$tmp_id[2] & date == first_issue$date[2],
                                       NA_real_,
                                       {{variable}}))
      print(first_issue %>% 
              select(tmp_id, date, {{variable}}),
            width = Inf) 
    }
    data
  }
  # filter to observations for which cum_confirmed_cases
  # is greater than 10
  # data <- data %>% 
  #   filter(cum_confirmed_cases >= 10)
  
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
  
  while(do_issues_exist(data %>% filter(cum_confirmed_cases >= 10), cum_confirmed_cases_imputed)){
    warning("Fixing an issue with cum_confirmed_cases")
    data <- fix_first_issue(data, cum_confirmed_cases_imputed, impute = TRUE)
    data <- fix_first_issue(data, cum_confirmed_cases, impute = FALSE)
  }
  data %>% 
    mutate(active_cases_imputed = cum_confirmed_cases_imputed - 
             cum_recoveries_imputed - 
             cum_deaths_imputed)
}
