compute_bootstrap_replications <- function(full_data, policy_variables_to_use, lhs, other_control_variables = NULL, times = 1000, gamma = 1/3,
                                           time_steps_per_day = 6){
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
  if("no_variation_for_unit" %in% names(full_data)){
    main_model <- felm(data = full_data %>% 
                         filter(!no_variation_for_unit) %>% 
                         mutate(tmp_id = droplevels(tmp_id)),
                       formula = formula,
                       cmethod = "reghdfe"); # summary(main_model)
    if(length(nan_variable <- rownames(main_model$coefficients)[which(is.nan(main_model$coefficients))]) > 0){
      return(nan_variable)
    }
  } else {
    main_model <- felm(data = full_data,
                       formula = formula,
                       cmethod = "reghdfe"); # summary(main_model)
  }
  
  # Eigen values can come out negative in small samples - set those ones to zero
  # https://github.com/sgaure/lfe/blob/deb7058637eb3ab95b0d41bb7fce7e589d480619/R/felm.R
  ev <- eigen(main_model$clustervcv)
  badev <- Im(ev$values) != 0 | Re(ev$values) < 0
  if(any(badev)) {
    warning('Negative eigenvalues set to zero in clustered variance matrix. See felm(...,psdef=FALSE)')
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
                                         time_steps_per_day = time_steps_per_day)
      pb$tick()$print()
      out
    }))
  
  final_results_new <- final_results %>% 
    unnest(model)
}

compute_predicted_cum_cases <- function(full_data, model, policy_variables_used, other_control_variables, lhs, filter_spec = TRUE, gamma = 1/3,
                                        time_steps_per_day = 6, mmat_actual = NULL){
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
    group_by(tmp_id) %>% 
    slice(-1) %>% 
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
  tmp_id_tbl <- mmat_actual %>% 
    as_tibble() %>% 
    bind_cols(true_data_subset_for_estimation %>% 
                select(tmp_id)) %>% 
    group_by(tmp_id) %>% 
    select(matches("tmp_id")) %>% 
    summarise_all(~.[1])
  true_data_subset_for_prediction <- true_data_subset_for_prediction %>% 
    left_join(tmp_id_tbl, by = c("tmp_id"))
  if("day_of_week" %in% other_control_variables){
    dow_tbl <- mmat_actual %>% 
      as_tibble() %>% 
      bind_cols(true_data_subset_for_estimation %>% 
                  select(day_of_week)) %>% 
      group_by(day_of_week) %>% 
      select(matches("day_of_week")) %>% 
      summarise_all(~.[1])
    true_data_subset_for_prediction <- true_data_subset_for_prediction %>% 
      left_join(dow_tbl, by = c("day_of_week"))
  }
  stopifnot(all(colnames(mmat_actual) %in% names(true_data_subset_for_prediction)))
  # colnames(mmat_actual)[!colnames(mmat_actual) %in% names(true_data_subset_for_prediction)]
  # Rows have been added and the names all match - can now reassign
  mmat_actual <- true_data_subset_for_prediction %>% 
    select(colnames(mmat_actual)) %>% 
    as.matrix()

  mmat_no_policy_counterfactual <- mmat_actual
  mmat_no_policy_counterfactual2 <- mmat_actual
  
  # We'll store the prediction data associated with counterfactual data here
  # The mutate sets all of the policy variables to zero for all time
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
  matching_indices <- no_policy_counterfactual_data_storage %>% 
    mutate(xxxxid = 1:n()) %>% 
    inner_join(no_policy_counterfactual_data_for_prediction, by = c("tmp_id", "date")) %>% 
    pull(xxxxid)
  # browser()
  no_policy_counterfactual_data_storage <- no_policy_counterfactual_data_storage %>% 
    ungroup() %>% 
    mutate(prediction_logdiff = {
      # This is a bit of a hack to get the predicted values added to the data.frame with
      # the NA values in the right place.
      tmp <- !!rlang::sym(lhs)
      # browser()
      stopifnot(length(tmp[matching_indices]) == nrow(np_predict))
      tmp[matching_indices] <- np_predict %>% pull(fit)
      tmp
    }) %>% 
    group_by(tmp_id) %>% 
    mutate(predicted_cum_confirmed_cases = 
             # Here we start at cum_confirmed_cases[1] - predict itself for the first one (exp(0))
             # Then predict the using the sum of the log changes from the second on
             {
               # cum_confirmed_cases == I + R
               # number_of_infectious_individuals == I

               # the simulation will start on the first hour of the second day
               # the seed of the simulation is the last hour of the first day - which we assume to be 
               # the number from the data
               
               cum_confirmed_cases_simulated <- rep(NA_real_, (length(cum_confirmed_cases) - 1)*time_steps_per_day + 1)
               number_of_infectious_individuals <- cum_confirmed_cases_simulated
               number_of_infectious_individuals[1] <- cum_confirmed_cases[1] # Assumption here is that all individuals are infectious initially
               cum_confirmed_cases_simulated[1] <- cum_confirmed_cases[1]
               prediction_logdiff_interpolated <- c(NA_real_, rep(prediction_logdiff[-1], each = time_steps_per_day))
               stopifnot(length(prediction_logdiff_interpolated) == length(cum_confirmed_cases_simulated))
               new_gamma = (1 + gamma)^(1/time_steps_per_day) - 1
               for(i in 2:length(cum_confirmed_cases_simulated)){ # adm1_pop is constant here
                 # new_infections <- number_of_infectious_individuals[i - 1]*
                 #   exp((prediction_logdiff[i] + gamma)*max(population[1] - out[i - 1], 0)/population[1]) -
                 #   number_of_infectious_individuals[i - 1]
                 
                 
                 # i_t+1 = i_t exp(beta*S - gamma)
                 number_of_infectious_individuals[i] = 
                   number_of_infectious_individuals[i - 1]*exp((prediction_logdiff_interpolated[i]/time_steps_per_day + new_gamma)*
                                                                 max(population[1] - cum_confirmed_cases_simulated[i - 1], 0)/population[1] - 
                                                                 new_gamma)
                 
                 recoveries <- number_of_infectious_individuals[i - 1]*(exp(new_gamma) - 1)
                 
                 new_infections <- number_of_infectious_individuals[i] - number_of_infectious_individuals[i - 1] + recoveries
                 # check a few timesteps and make sure we get convergence
                 # number_of_infectious_individuals[i] = number_of_infectious_individuals[i - 1]*exp(-gamma) + new_infections
                 # out[i] = out[i - 1] + active_cases[i - 1]*(exp(prediction_logdiff[i]*max(population[1] - out[i - 1], 0)/population[1]) - 1)
                 cum_confirmed_cases_simulated[i] = cum_confirmed_cases_simulated[i - 1] + new_infections
               }
               out <- cum_confirmed_cases_simulated[seq(1, length(cum_confirmed_cases_simulated), by = time_steps_per_day)]
               out
             })
  
  true_predict <- predict.felm(model, newdata = mmat_actual)
  
  true_data_storage <- true_data_storage %>% 
    ungroup() %>% 
    mutate(prediction_logdiff = {
      # This is a bit of a hack to get the predicted values added to the data.frame with
      # the NA values in the right place.
      tmp <- !!rlang::sym(lhs)
      stopifnot(length(tmp[matching_indices]) == nrow(true_predict))
      tmp[matching_indices] <- true_predict %>% pull(fit)
      tmp
    }) %>% 
    group_by(tmp_id) %>% 
    mutate(predicted_cum_confirmed_cases = 
             # Here we start at cum_confirmed_cases[1] - predict itself for the first one (exp(0))
             # Then predict the using the sum of the log changes from the second on
             {
               # cum_confirmed_cases == I + R
               # number_of_infectious_individuals == I
               time_steps_per_day <- 6
               
               # the simulation will start on the first hour of the second day
               # the seed of the simulation is the last hour of the first day - which we assume to be 
               # the number from the data
               cum_confirmed_cases_simulated <- rep(NA_real_, (length(cum_confirmed_cases) - 1)*time_steps_per_day + 1)
               number_of_infectious_individuals <- cum_confirmed_cases_simulated
               number_of_infectious_individuals[1] <- cum_confirmed_cases[1] # Assumption here is that all individuals are infectious initially
               cum_confirmed_cases_simulated[1] <- cum_confirmed_cases[1]
               prediction_logdiff_interpolated <- c(NA_real_, rep(prediction_logdiff[-1], each = time_steps_per_day))
               stopifnot(length(prediction_logdiff_interpolated) == length(cum_confirmed_cases_simulated))
               new_gamma = (1 + gamma)^(1/time_steps_per_day) - 1
               for(i in 2:length(cum_confirmed_cases_simulated)){ # adm1_pop is constant here
                 # new_infections <- number_of_infectious_individuals[i - 1]*
                 #   exp((prediction_logdiff[i] + gamma)*max(population[1] - out[i - 1], 0)/population[1]) -
                 #   number_of_infectious_individuals[i - 1]
                 
                 
                 # i_t+1 = i_t exp(beta*S - gamma)
                 number_of_infectious_individuals[i] = 
                   number_of_infectious_individuals[i - 1]*exp((prediction_logdiff_interpolated[i]/time_steps_per_day + new_gamma)*
                                                                 max(population[1] - cum_confirmed_cases_simulated[i - 1], 0)/population[1] - 
                                                                 new_gamma)
                 
                 recoveries <- number_of_infectious_individuals[i - 1]*(exp(new_gamma) - 1)
                 
                 new_infections <- number_of_infectious_individuals[i] - number_of_infectious_individuals[i - 1] + recoveries
                 # check a few timesteps and make sure we get convergence
                 # number_of_infectious_individuals[i] = number_of_infectious_individuals[i - 1]*exp(-gamma) + new_infections
                 # out[i] = out[i - 1] + active_cases[i - 1]*(exp(prediction_logdiff[i]*max(population[1] - out[i - 1], 0)/population[1]) - 1)
                 cum_confirmed_cases_simulated[i] = cum_confirmed_cases_simulated[i - 1] + new_infections
               }
               out <- cum_confirmed_cases_simulated[seq(1, length(cum_confirmed_cases_simulated), by = time_steps_per_day)]
               out
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