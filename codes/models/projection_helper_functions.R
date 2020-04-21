# KB re-reviewed this function on 03/27 - I think it's right.
compute_bootstrap_replications <- function(full_data, policy_variables_to_use, lhs, 
                                           other_control_variables = NULL, times = 1000, gamma = 1/3,
                                           time_steps_per_day = 6,
                                           proportion_confirmed = 1){
  full_data <- full_data %>% ungroup()
  if(!lhs %in% names(full_data)){
    stop(paste0("need ", lhs, " in full_data"))
  }
  if(!"tmp_id" %in% names(full_data)){
    stop("need tmp_id (as a factor) in full_data")
  }
  formula <- as.formula(
    paste(lhs, " ~ tmp_id + ", paste(c(policy_variables_to_use, other_control_variables), collapse = " + "),
          " - 1 | 0 | 0 | date "
    ))
  main_model <- felm(data = full_data,
                     formula = formula,
                     cmethod = "reghdfe"); # summary(main_model)
  
  # Eigen values can come out negative in small samples - set those ones to zero
  # https://github.com/sgaure/lfe/blob/deb7058637eb3ab95b0d41bb7fce7e589d480619/R/felm.R
  ev <- eigen(main_model$clustervcv)
  badev <- Im(ev$values) != 0 | Re(ev$values) < 0
  if(any(badev)) {
    # warning('Negative eigenvalues set to zero in clustered variance matrix. See felm(...,psdef=FALSE)')
    ev$values[badev] <- 0
    main_model$clustervcv[] <- Re(ev$vectors %*% diag(ev$values) %*% t(ev$vectors))
  }
  rm(ev)
  
  final_results <- tibble(id = 1:times)
  
  pb <- dplyr::progress_estimated(n = nrow(final_results))
  final_results <- final_results %>% 
    mutate(model = id %>% map(~{
      # use this for the regression
      stopifnot(isTRUE(all.equal(rownames(main_model$coefficients), (rownames(main_model$clustervcv)))))
      new_coefficients <- mvtnorm::rmvnorm(n = 1, mean = main_model$coefficients,
                                           sigma = main_model$clustervcv)
      
      new_main_model <- main_model
      # Replace the main model coefficients with the new coefficients for everything but tmp_id
      new_main_model$coefficients[] <- new_coefficients
      out <- compute_predicted_cum_cases(full_data = full_data, model = new_main_model, lhs = lhs, 
                                         policy_variables_used = policy_variables_to_use,
                                         other_control_variables = other_control_variables,
                                         gamma = gamma,
                                         time_steps_per_day = time_steps_per_day,
                                         proportion_confirmed = proportion_confirmed)
      pb$tick()$print()
      out
    }))
  
  final_results_new <- final_results %>% 
    unnest(model)
}

compute_predicted_cum_cases <- function(full_data, model, policy_variables_used, other_control_variables, 
                                        lhs, filter_spec = TRUE, gamma = 1/3,
                                        sigma = Inf,
                                        time_steps_per_day = 6, mmat_actual = NULL,
                                        proportion_confirmed = 1,
                                        return_no_policy_projection_output = FALSE){
  if(!"population" %in% names(full_data)){
    stop("\"population\" variable required. If unavailable, please add a column using full_data <- full_data %>% mutate(population = 1e+8)")
  }
  # We'll store the prediction data associated with true data here
  true_data <- full_data
  # In the case where we have rhs variables available but no lhs
  # we can still do the prediction here
  # these model matrix dimensions will be incorrect
  if(is.null(mmat_actual)){
    mmat_actual <- model.matrix.lm(model)
  }
  # subset to the sample you will be predicting for
  true_data_subset_for_prediction <- true_data %>%
    ungroup() %>% 
    select(tmp_id, date, all_of(policy_variables_used), all_of(other_control_variables)) %>% 
    drop_na() %>%
    # Don't want to bother predicting for the first period 
    # because we 
    group_by(tmp_id) %>% 
    dplyr::slice(-1) %>% 
    ungroup()
  
  true_data_subset_for_estimation <- true_data %>%
    ungroup() %>% 
    select(all_of(lhs), date, all_of(policy_variables_used), all_of(other_control_variables), tmp_id) %>% 
    drop_na()
  
  true_data_storage <- true_data %>%
    ungroup()
  
  # Check that the mmat and true_data_subset_for_estimation
  # rows are the same
  suppressWarnings(stopifnot(isTRUE(all.equal(
    mmat_actual %>% 
      as_tibble() %>% 
      select(all_of(policy_variables_used)),
    true_data_subset_for_estimation %>% 
      select(all_of(policy_variables_used))
  ))))
  
  # Creates a tibble with one row per unit and columns tmp_id
  # and the column names from the model matrix
  tmp_id_tbl <- mmat_actual %>% 
    as_tibble() %>% 
    bind_cols(true_data_subset_for_estimation %>% 
                select(tmp_id)) %>% 
    group_by(tmp_id) %>% 
    select(matches("tmp_id")) %>% 
    summarise_all(~.[1])
  
  # Add the model matrix columns to the prediction matrix
  true_data_subset_for_prediction <- true_data_subset_for_prediction %>% 
    left_join(tmp_id_tbl, by = c("tmp_id"))
  
  
  if("day_of_week" %in% other_control_variables){
    # Creates a tibble with one row per DOW and columns day_of_week
    # and the column names from the model matrix
    dow_tbl <- mmat_actual %>% 
      as_tibble() %>% 
      bind_cols(true_data_subset_for_estimation %>% 
                  select(day_of_week)) %>% 
      group_by(day_of_week) %>% 
      select(matches("day_of_week")) %>% 
      summarise_all(~.[1])
    # Add the DOW model matrix columns to the prediction matrix
    true_data_subset_for_prediction <- true_data_subset_for_prediction %>% 
      left_join(dow_tbl, by = c("day_of_week"))
  }
  stopifnot(all(colnames(mmat_actual) %in% names(true_data_subset_for_prediction)))
  # colnames(mmat_actual)[!colnames(mmat_actual) %in% names(true_data_subset_for_prediction)]
  # Rows have been added and the names all match - can now reassign
  
  # This is the mmat for all the rows where we have complete RHS data
  mmat_actual_for_prediction <- true_data_subset_for_prediction %>% 
    select(colnames(mmat_actual)) %>% 
    as.matrix()
  
  # mmat we'll use to predict the counterfactual
  mmat_no_policy_counterfactual <- mmat_actual_for_prediction
  # mmat we'll use to verify we constructed the first one correctly
  mmat_no_policy_counterfactual2 <- mmat_actual_for_prediction
  
  mmat_no_policy_counterfactual2 <- true_data_subset_for_prediction %>% 
    mutate_at(vars(all_of(policy_variables_used)),
              list(~0)) %>% 
    select(colnames(mmat_actual)) %>% 
    as.matrix()
  
  # We'll store the prediction data associated with counterfactual data here
  # The mutate sets all of the policy variables to zero for all time
  no_policy_counterfactual_data_storage <- true_data_storage %>% 
    mutate_at(vars(all_of(policy_variables_used)),
              list(~0))
  no_policy_counterfactual_data_for_prediction <- true_data_subset_for_prediction %>% 
    mutate_at(vars(all_of(policy_variables_used)),
              list(~0))
  
  for(p in policy_variables_used){
    stopifnot(isTRUE(all.equal(unname(mmat_no_policy_counterfactual[,p]), 
                               true_data_subset_for_prediction %>% pull(p))))
    mmat_no_policy_counterfactual[,p] <- no_policy_counterfactual_data_for_prediction %>% 
      pull(p)
  }
  # Computed the same thing in two ways to make sure they're the same
  stopifnot(isTRUE(all.equal(mmat_no_policy_counterfactual, mmat_no_policy_counterfactual2)))
  
  np_predict <- predict.felm(model, newdata = mmat_no_policy_counterfactual)
  stopifnot(nrow(mmat_no_policy_counterfactual) == nrow(no_policy_counterfactual_data_for_prediction))
  np_predict_df <- no_policy_counterfactual_data_for_prediction %>% 
    mutate(prediction_logdiff = np_predict$fit) %>% 
    select(tmp_id, date, prediction_logdiff)
  
  # This helps us to look at which rows don't get matched to diagnose data errors
  # This can uncover instances of missing RHS that shouldn't be missing
  # no_policy_counterfactual_data_storage %>%
  #   group_by(tmp_id) %>% 
  #   dplyr::slice(-1) %>% 
  #   anti_join(no_policy_counterfactual_data_for_prediction, by = c("tmp_id", "date")) %>% 
  #   select(tmp_id, date, other_control_variables, policy_variables_to_use)
  
  # This bit adds the predicted values in the spots where we are predicting
  
  no_policy_counterfactual_data_storage <- no_policy_counterfactual_data_storage %>% 
    left_join(np_predict_df, by = c("tmp_id", "date")) 
  # All the first ones should be NA
  stopifnot({
    no_policy_counterfactual_data_storage %>% 
      group_by(tmp_id) %>% 
      dplyr::slice(1) %>% 
      pull(prediction_logdiff) %>% 
      is.na() %>% 
      all()
  })
  
  # All the ones other than the first should not be NA
  stopifnot({
    no_policy_counterfactual_data_storage %>% 
      group_by(tmp_id) %>% 
      dplyr::slice(-1) %>% 
      pull(prediction_logdiff) %>% 
      is.na() %>%
      magrittr::not() %>% 
      all()
  })
  # There should be no gaps in the dates for any unit
  stopifnot({
    no_policy_counterfactual_data_storage %>% 
      group_by(tmp_id) %>% 
      mutate(date_diff = c(1, diff(date))) %>% 
      pull(date_diff) %>% 
      magrittr::equals(1) %>% 
      all()
  })
  
  if(return_no_policy_projection_output){
    out <- 
      no_policy_counterfactual_data_storage %>% 
      group_by(tmp_id) %>% 
      summarise(projection_output = {
        list(calculate_projection_for_one_unit(
          cum_confirmed_cases_first = cum_confirmed_cases[1],
          prediction_logdiff = prediction_logdiff,
          time_steps_per_day = time_steps_per_day,
          daily_gamma = gamma,
          daily_sigma = sigma,
          unit_population = population[1],
          proportion_confirmed = proportion_confirmed,
          all = TRUE
        ))
      }) %>% 
      unnest(projection_output)
    return(out)
  }
  
  no_policy_counterfactual_data_storage <- 
    no_policy_counterfactual_data_storage %>% 
    group_by(tmp_id) %>% 
    mutate(predicted_cum_confirmed_cases = {
      calculate_projection_for_one_unit(
        cum_confirmed_cases_first = cum_confirmed_cases[1],
        prediction_logdiff = prediction_logdiff,
        time_steps_per_day = time_steps_per_day,
        daily_gamma = gamma,
        daily_sigma = sigma,
        unit_population = population[1],
        proportion_confirmed = proportion_confirmed
      )
    })
  
  
  true_predict <- predict.felm(model, newdata = mmat_actual_for_prediction)
  true_predict_df <- true_data_subset_for_prediction %>% 
    mutate(prediction_logdiff = true_predict$fit) %>% 
    select(tmp_id, date, prediction_logdiff)
  
  true_data_storage <- true_data_storage %>% 
    ungroup() %>% 
    left_join(true_predict_df, by = c("tmp_id", "date")) %>% 
    group_by(tmp_id) %>% 
    mutate(predicted_cum_confirmed_cases = {
      calculate_projection_for_one_unit(
        cum_confirmed_cases_first = cum_confirmed_cases[1],
        prediction_logdiff = prediction_logdiff,
        time_steps_per_day = time_steps_per_day,
        daily_gamma = gamma,
        daily_sigma = sigma,
        unit_population = population[1],
        proportion_confirmed = proportion_confirmed
      )
    })
  
  out <- true_data_storage %>% 
    filter({{filter_spec}}) %>% 
    group_by(date) %>% 
    summarise(predicted_cum_confirmed_cases_true = sum(predicted_cum_confirmed_cases)) %>% 
    left_join(
      no_policy_counterfactual_data_storage %>% 
        filter({{filter_spec}}) %>% 
        group_by(date) %>% 
        summarise(predicted_cum_confirmed_cases_no_policy = sum(predicted_cum_confirmed_cases)),
      by = "date"
    )
  out  
}

# Here we start at cum_confirmed_cases[1] - predict itself for the first one (exp(0))
# Then predict the using the sum of the log changes from the second on
calculate_projection_for_one_unit <- function(cum_confirmed_cases_first, 
                                              prediction_logdiff,
                                              time_steps_per_day,
                                              daily_gamma,
                                              unit_population,
                                              proportion_confirmed,
                                              all = FALSE, 
                                              daily_sigma = Inf){
  # cum_confirmed_cases == I + R
  # number_of_infectious_individuals == I
  stopifnot(is.na(prediction_logdiff[1]))
  stopifnot(!is.na(cum_confirmed_cases_first))
  
  # the simulation will start on the first hour of the second day
  # the seed of the simulation is the last hour of the first day - which we assume to be 
  # the number from the data
  
  cum_confirmed_cases_simulated <- rep(NA_real_, (length(prediction_logdiff) - 1)*time_steps_per_day + 1)
  number_of_infectious_individuals <- cum_confirmed_cases_simulated # NA
  number_of_susceptible_individuals <- cum_confirmed_cases_simulated # NA
  number_of_recovered_individuals <- cum_confirmed_cases_simulated # NA
  if (daily_sigma < Inf){
    number_of_exposed_individuals <- cum_confirmed_cases_simulated # NA  
  }
  
  
  # Assumption here is that all individuals are infectious initially
  number_of_infectious_individuals[1] <- cum_confirmed_cases_first/proportion_confirmed
  cum_confirmed_cases_simulated[1] <- cum_confirmed_cases_first
  number_of_recovered_individuals[1] <- 0
  new_gamma = (1 + daily_gamma)^(1/time_steps_per_day) - 1
  prediction_logdiff_interpolated <- c(NA_real_, rep(prediction_logdiff[-1], each = time_steps_per_day))
  stopifnot(length(prediction_logdiff_interpolated) == length(cum_confirmed_cases_simulated))
  if (daily_sigma < Inf){
    new_sigma = (1 + daily_sigma)^(1/time_steps_per_day) - 1
    new_beta <- (max(prediction_logdiff_interpolated[2]/time_steps_per_day, 0) + new_gamma) * 
      (max(prediction_logdiff_interpolated[2]/time_steps_per_day, 0) + new_sigma) / new_sigma
    mat <- matrix(c(-new_sigma, new_sigma, 
                    new_beta, -new_gamma), nrow = 2)
    eig <- eigen(mat)
    pos_eig_vector <- eig$vectors[,which.max(eig$values)]
    # Assumes we're on the equilibrium path at the start
    number_of_exposed_individuals[1] <- pos_eig_vector[1]/pos_eig_vector[2]*number_of_infectious_individuals[1]
    number_of_susceptible_individuals[1] <- unit_population - number_of_infectious_individuals[1] - 
      number_of_exposed_individuals[1]
  } else {
    number_of_susceptible_individuals[1] <- unit_population - number_of_infectious_individuals[1]
  }
  
  
  for(i in 2:length(cum_confirmed_cases_simulated)){
    new_removed <- number_of_infectious_individuals[i - 1]*new_gamma
    if (daily_sigma < Inf){
      new_beta <- (prediction_logdiff_interpolated[i]/time_steps_per_day + new_gamma) * 
        (prediction_logdiff_interpolated[i]/time_steps_per_day + new_sigma) / new_sigma
      new_exposed_rate = new_beta*number_of_susceptible_individuals[i - 1]/unit_population
      new_exposed = number_of_infectious_individuals[i - 1]*new_exposed_rate

      new_infected = number_of_exposed_individuals[i - 1]*new_sigma
      
      number_of_exposed_individuals[i] = 
        number_of_exposed_individuals[i - 1] + new_exposed - new_infected
      
      number_of_infectious_individuals[i] = 
        number_of_infectious_individuals[i - 1] + new_infected - new_removed
      
      number_of_susceptible_individuals[i] = number_of_susceptible_individuals[i - 1] - 
        new_exposed
      
      number_of_recovered_individuals[i] <- unit_population - 
        number_of_infectious_individuals[i] - 
        number_of_susceptible_individuals[i] - 
        number_of_exposed_individuals[i]
    } else {
      new_infected_rate = (prediction_logdiff_interpolated[i]/time_steps_per_day + new_gamma)*
        number_of_susceptible_individuals[i - 1]/unit_population
      number_of_infectious_individuals[i] = 
        number_of_infectious_individuals[i - 1]*exp(new_infected_rate - new_gamma)
      
      number_of_susceptible_individuals[i] = number_of_susceptible_individuals[i - 1] - 
        number_of_infectious_individuals[i]*new_infected_rate
      
      number_of_recovered_individuals[i] <- unit_population - 
        number_of_infectious_individuals[i] - 
        number_of_susceptible_individuals[i]
    }
    
    new_true_infections <- number_of_infectious_individuals[i] - number_of_infectious_individuals[i - 1] + new_removed
    
    cum_confirmed_cases_simulated[i] = cum_confirmed_cases_simulated[i - 1] + new_true_infections*proportion_confirmed
  }
  if (all){
    if(daily_sigma < Inf){
      out <- tibble(number_of_susceptible_individuals = number_of_susceptible_individuals, 
                    number_of_infectious_individuals = number_of_infectious_individuals, 
                    number_of_recovered_individuals = number_of_recovered_individuals,
                    number_of_exposed_individuals = number_of_exposed_individuals,
                    share_of_susceptible_individuals = number_of_susceptible_individuals / unit_population)
    } else {
      out <- tibble(number_of_susceptible_individuals = number_of_susceptible_individuals, 
                    number_of_infectious_individuals = number_of_infectious_individuals, 
                    number_of_recovered_individuals = number_of_recovered_individuals,
                    share_of_susceptible_individuals = number_of_susceptible_individuals / unit_population)
    }
  } else {
    out <- cum_confirmed_cases_simulated[seq(1, length(cum_confirmed_cases_simulated), by = time_steps_per_day)]
  }
  if(any(is.na(out))){
    browser()
  }
  out
}
