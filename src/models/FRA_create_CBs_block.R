# setwd("E:/GPL_covid/")
library(tidyverse)
library(rsample)
library(patchwork)
library(lfe)
source("src/models/predict_felm.R")
mydata <- read_csv("data/processed/adm1/FRA_processed.csv",
                        col_types = cols(
                          .default = col_double(),
                          adm0_name = col_character(),
                          adm1_name = col_character(),
                          date = col_date(format = "")
                        )) %>% 
  arrange(adm1_name, date)

mydata <- mydata %>%
  # mutate(cum_confirmed_cases = cum_filled_cases) %>% 
  # Match Sol's sample - change this if needed
  filter(cum_confirmed_cases >= 10, date >= "2020-03-02") %>% 
  group_by(adm1_name) %>% 
  mutate(log_difference_cum_confirmed_cases = log(cum_confirmed_cases) - lag(log(cum_confirmed_cases))) %>% 
  select(-business_closure, -home_isolation) %>% 
  mutate(day_of_week = factor(lubridate::wday(date, week_start = 1))) 

# mydata %>% 
#   group_by(adm1_name) %>% 
#   nest() %>% 
#   ungroup() %>% 
#   sample_n(1) %>% 
#   unnest(c(data))

# plotly::ggplotly({
#   mydata %>% 
#     group_by(date) %>% 
#     summarise(log_difference_cum_confirmed_cases = mean(log_difference_cum_confirmed_cases, na.rm = TRUE)) %>% 
#     ggplot(aes(x = date, y = log_difference_cum_confirmed_cases)) + 
#     geom_line()
# })

boots <- mydata %>% 
  nest() %>% 
  bootstraps(times = 1000)

main_model <- felm(data = mydata,
                   formula = log_difference_cum_confirmed_cases ~ 
                     adm1_name + day_of_week + 
                     event_cancel + 
                     school_closure_regional + 
                     social_distance + 
                     no_gathering_national_100 + 
                     no_gathering_national_1000 -
                     1
                   | 0 # FE Specification here - included above  
                   | 0 
                   | 0  # Clustering Specification
); #summary(model)

variables_used <- rownames(model$coefficients)
policy_variables_used <- variables_used %>% 
  str_subset("^date$", negate = TRUE) %>% 
  str_subset("^adm1_name", negate = TRUE) %>% 
  str_subset("Intercept", negate = TRUE) %>% 
  str_subset("day_of_week", negate = TRUE)

pb <- dplyr::progress_estimated(n = nrow(boots))
boots <- boots %>% 
  mutate(model = splits %>% map(~{
    # use this for the regression
    
    data_sample <- analysis(.x) %>%
      mutate(id = 1:n()) %>% 
      unite(tmp_id, adm1_name, id) %>% 
      unnest(data)
    
    # use this for the projection
    
    this_model <- felm(data = data_sample,
                  formula = log_difference_cum_confirmed_cases ~
                    day_of_week +
                    event_cancel + 
                    school_closure_regional + 
                    social_distance + 
                    no_gathering_national_100 + 
                    no_gathering_national_1000 
                  | tmp_id # FE Specification here - above 
                  | 0 
                  | 0  # Clustering Specification - not needed for bootstrap
                  ); #summary(this_model)
    
    new_main_model <- main_model
    # Replace the main model coeffiecients with the new coefficients
    new_main_model$coefficients[rownames(this_model$coefficients) %>% map_dbl(~which(rownames(new_main_model$coefficients) == .x))] <- 
      this_model$coefficients

    # We'll store the prediction data associated with true data here
    true_data <- mydata
    # We'll store the prediction data associated with counterfactual data here
    # The mutate sets all of the policy variables to zero for all time
    no_policy_counterfactual_data <- mydata %>% 
      mutate_at(vars(all_of(policy_variables_used)),
                list(~0))
    mmat_actual <- model.matrix(new_main_model)
    mmat_no_policy_counterfactual <- model.matrix(new_main_model)
    for(p in policy_variables_used){
      stopifnot(isTRUE(all.equal(unname(mmat_no_policy_counterfactual[,p]), 
                                 true_data %>% 
                                   group_by(adm1_name) %>% 
                                   slice(-1) %>% pull(p))))
      mmat_no_policy_counterfactual[,p] <- no_policy_counterfactual_data %>% 
        group_by(adm1_name) %>% 
        slice(-1) %>% pull(p)
    }
    np_predict <- predict.felm(new_main_model, newdata = mmat_no_policy_counterfactual)

    no_policy_counterfactual_data <- no_policy_counterfactual_data %>% 
      ungroup() %>% 
      mutate(prediction_logdiff = {
        # This is a bit of a hack to get the predicted values added to the data.frame with
        # the NA values in the right place.
        tmp <- log_difference_cum_confirmed_cases
        tmp[!is.na(tmp)] <- np_predict %>% pull(fit)
        tmp
      }) %>% 
      group_by(adm1_name) %>% 
      mutate(predicted_cum_confirmed_cases = 
               # Here we start at cum_confirmed_cases[1] - predict itself for the first one (exp(0))
               # Then predict the using the sum of the log changes from the second on
               cum_confirmed_cases[1]*exp(cumsum(c(0, prediction_logdiff[-1]))))
    
    true_data <- true_data %>% 
      ungroup() %>% 
      mutate(prediction_logdiff = {
        # This is a bit of a hack to get the predicted values added to the data.frame with
        # the NA values in the right place.
        tmp <- log_difference_cum_confirmed_cases
        tmp[!is.na(tmp)] <- predict.felm(new_main_model, newdata = mmat_actual) %>% pull(fit)
        tmp
      }) %>% 
      group_by(adm1_name) %>% 
      mutate(predicted_cum_confirmed_cases = 
               # Here we start at cum_confirmed_cases[1] - predict itself for the first one (exp(0))
               # Then predict the using the sum of the log changes from the second on
               cum_confirmed_cases[1]*exp(cumsum(c(0, prediction_logdiff[-1]))))
    
    out <- true_data %>% 
      group_by(date) %>% 
      summarise(predicted_cum_confirmed_cases_true = sum(predicted_cum_confirmed_cases)) %>% 
      left_join(
        no_policy_counterfactual_data %>% 
          group_by(date) %>% 
          summarise(predicted_cum_confirmed_cases_no_policy = sum(predicted_cum_confirmed_cases)),
        by = "date"
      )
    pb$tick()$print()
    out
 }))


boots <- boots %>% 
  select(-splits, -id) %>% 
  unnest(model)

boots <- boots %>% 
  group_by(date) %>% 
  summarise(predicted_cum_confirmed_cases_true_lwr = quantile(predicted_cum_confirmed_cases_true, probs = 0.025),
            predicted_cum_confirmed_cases_true_upr = quantile(predicted_cum_confirmed_cases_true, probs = 0.975),
            predicted_cum_confirmed_cases_no_policy_lwr = quantile(predicted_cum_confirmed_cases_no_policy, probs = 0.025),
            predicted_cum_confirmed_cases_no_policy_upr = quantile(predicted_cum_confirmed_cases_no_policy, probs = 0.975))

# options(scipen=10000)
# np <- no_policy_counterfactual_data %>%
#   group_by(date) %>% 
#   summarise(predicted_cum_confirmed_cases = 
#               sum(predicted_cum_confirmed_cases)) %>% 
#   mutate(se_prediction = c(0, standard_errors_by_day_np)) %>% 
#   mutate(upper_ci = predicted_cum_confirmed_cases + 1.96*se_prediction,
#          lower_ci = predicted_cum_confirmed_cases - 1.96*se_prediction) %>% 
#   ggplot() + 
#   geom_line(aes(x = date, y = predicted_cum_confirmed_cases), size = 1.5) + 
#   geom_ribbon(aes(x = date, ymin=lower_ci, ymax = upper_ci),
#               fill = "gray50", alpha= 0.5) + 
#   theme_classic() + 
#   xlab("Date") + 
#   ylab("Predicted cumulative confirmed cases without policy")
# 
# # This one looks wrong - seems like there should be more uncertainty here
# true <- true_data %>%
#   group_by(date) %>% 
#   summarise(predicted_cum_confirmed_cases = 
#               sum(predicted_cum_confirmed_cases)) %>% 
#   mutate(se_prediction = c(0, standard_errors_by_day_true)) %>% 
#   mutate(upper_ci = predicted_cum_confirmed_cases + 1.96*se_prediction,
#          lower_ci = predicted_cum_confirmed_cases - 1.96*se_prediction) %>% 
#   ggplot() + 
#   geom_line(aes(x = date, y = predicted_cum_confirmed_cases), size = 1.5) + 
#   geom_ribbon(aes(x = date, ymin=lower_ci, ymax = upper_ci),
#               fill = "gray50", alpha= 0.5) + 
#   theme_classic() + 
#   xlab("Date") + 
#   ylab("Predicted cumulative confirmed cases with policy")
# 
# out <- np / true
# ggsave(out, filename = "figures/fig2/FRA_projections_with_uncertainty.pdf", width = 5, height = 10)
