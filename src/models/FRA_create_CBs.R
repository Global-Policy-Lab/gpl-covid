# setwd("E:/GPL_covid/")
library(tidyverse)
library(patchwork)
library(lfe)
source("src/models/predict_felm.R")
france_data <- read_csv("data/processed/adm1/FRA_processed.csv",
                        col_types = cols(
                          .default = col_double(),
                          adm0_name = col_character(),
                          adm1_name = col_character(),
                          date = col_date(format = "%d%b%Y")
                        )) %>% 
  arrange(adm1_name, date)

france_data <- france_data %>%
  # mutate(cumulative_confirmed_cases = cumulative_filled_cases) %>% 
  # Match Sol's sample - change this if needed
  filter(cumulative_confirmed_cases >= 10, date >= "2020-03-02") %>% 
  group_by(adm1_name) %>% 
  mutate(log_difference_cumulative_confirmed_cases = log(cumulative_confirmed_cases) - lag(log(cumulative_confirmed_cases))) %>% 
  select(-business_closure, -home_isolation) %>% 
  mutate(day_of_week = factor(lubridate::wday(date, week_start = 1))) 

# france_data %>% 
#   group_by(adm1_name) %>% 
#   nest() %>% 
#   ungroup() %>% 
#   sample_n(1) %>% 
#   unnest(c(data))

# plotly::ggplotly({
#   france_data %>% 
#     group_by(date) %>% 
#     summarise(log_difference_cumulative_confirmed_cases = mean(log_difference_cumulative_confirmed_cases, na.rm = TRUE)) %>% 
#     ggplot(aes(x = date, y = log_difference_cumulative_confirmed_cases)) + 
#     geom_line()
# })

model <- felm(data = france_data,
              formula = log_difference_cumulative_confirmed_cases ~ 
                adm1_name + day_of_week + 
                event_cancel + 
                school_closure_regional + 
                social_distance + 
                no_gathering_national_100 + 
                no_gathering_national_1000 
              | 0 # FE Specification here - included above 
              | 0 
              | adm1_name  # Clustering Specification
              ,
              cmethod = "cgm2"); #summary(model)

# Eigen values can come out negative in small samples - set those ones to zero
eig <- eigen(model$clustervcv)
eig$values[eig$values < 0] <- 0
tmp <- eig$vectors %*% Diagonal(x = eig$values) %*% solve(eig$vectors)
model$clustervcv[] <- tmp[]

variables_used <- rownames(model$coefficients)
policy_variables_used <- variables_used %>% 
  str_subset("^date$", negate = TRUE) %>% 
  str_subset("^adm1_name", negate = TRUE) %>% 
  str_subset("Intercept", negate = TRUE) %>% 
  str_subset("day_of_week", negate = TRUE)

# We'll store the prediction data associated with true data here
true_data <- france_data

# We'll store the prediction data associated with counterfactual data here
# The mutate sets all of the policy variables to zero for all time
no_policy_counterfactual_data <- france_data %>% 
  mutate_at(vars(all_of(policy_variables_used)),
            list(~0))

mmat_actual <- model.matrix(model)
mmat_no_policy_counterfactual <- model.matrix(model)
mmat_no_policy_counterfactual_cumulative <- model.matrix(model)

for(p in policy_variables_used){
  stopifnot(isTRUE(all.equal(unname(mmat_no_policy_counterfactual[,p]), 
                      true_data %>% 
                        group_by(adm1_name) %>% 
                        slice(-1) %>% pull(p))))
  mmat_no_policy_counterfactual[,p] <- no_policy_counterfactual_data %>% 
    group_by(adm1_name) %>% 
    slice(-1) %>% pull(p)
  mmat_no_policy_counterfactual_cumulative[,p] <- mmat_no_policy_counterfactual[,p]
}

# Go through for each adm1 and replace each series with the cumsum
for(nm in (colnames(mmat_no_policy_counterfactual_cumulative) %>% str_subset("adm1"))){
  indices <- unname(which(mmat_no_policy_counterfactual_cumulative[,nm]==1))
  for(nm2 in colnames(mmat_no_policy_counterfactual_cumulative)){
    mmat_no_policy_counterfactual_cumulative[indices,nm2] <- cumsum(mmat_no_policy_counterfactual_cumulative[indices,nm2])
  }
}


np_predict <- predict.felm(model, newdata = mmat_no_policy_counterfactual,
                           interval = "confidence")

no_policy_counterfactual_data <- no_policy_counterfactual_data %>% 
  ungroup() %>% 
  mutate(prediction_logdiff = {
    # This is a bit of a hack to get the predicted values added to the data.frame with
    # the NA values in the right place.
    tmp <- log_difference_cumulative_confirmed_cases
    tmp[!is.na(tmp)] <- predict.felm(model, newdata = mmat_no_policy_counterfactual) %>% pull(fit)
    tmp
  }) %>% 
  group_by(adm1_name) %>% 
  mutate(predicted_cumulative_confirmed_cases = 
           # Here we start at cumulative_confirmed_cases[1] - predict itself for the first one (exp(0))
           # Then predict the using the sum of the log changes from the second on
           cumulative_confirmed_cases[1]*exp(cumsum(c(0, prediction_logdiff[-1]))))

no_policy_counterfactual_data2 <- no_policy_counterfactual_data %>% 
  ungroup() %>% 
  mutate(prediction_logdiff_cumulative = {
    pred <- predict.felm(model, newdata = mmat_no_policy_counterfactual_cumulative, interval = "confidence")
    # This is a bit of a hack to get the predicted values added to the data.frame with
    # the NA values in the right place.
    tmp_fit <- log_difference_cumulative_confirmed_cases
    tmp_fit[!is.na(tmp_fit)] <- pred$fit
    tmp_upr <- log_difference_cumulative_confirmed_cases
    tmp_upr[!is.na(tmp_upr)] <- pred$upr
    tmp_lwr <- log_difference_cumulative_confirmed_cases
    tmp_lwr[!is.na(tmp_lwr)] <- pred$lwr
    tibble(fit = tmp_fit,
           upr = tmp_upr,
           lwr = tmp_lwr) %>% 
      group_by(1:n()) %>% 
      nest() %>% 
      pull(data)
  }) %>%
  unnest(cols = prediction_logdiff_cumulative) %>% 
  group_by(adm1_name) %>% 
  mutate(log_predicted_cumulative_confirmed_cases = 
           # Here we start at cumulative_confirmed_cases[1] - predict itself for the first one (exp(0))
           # Then predict the using the sum of the log changes from the second on
           log(cumulative_confirmed_cases[1]) + c(0, fit[-1]),
         log_predicted_cumulative_confirmed_cases_upr = 
           # Here we start at cumulative_confirmed_cases[1] - predict itself for the first one (exp(0))
           # Then predict the using the sum of the log changes from the second on
           log(cumulative_confirmed_cases[1]) + c(0, upr[-1]),
         log_predicted_cumulative_confirmed_cases_lwr = 
           # Here we start at cumulative_confirmed_cases[1] - predict itself for the first one (exp(0))
           # Then predict the using the sum of the log changes from the second on
           log(cumulative_confirmed_cases[1]) + c(0, lwr[-1]),
         predicted_cumulative_confirmed_cases = exp(log_predicted_cumulative_confirmed_cases))

# The cumulative and summing method should yield the same result
stopifnot(isTRUE(all.equal(no_policy_counterfactual_data$predicted_cumulative_confirmed_cases,
                           no_policy_counterfactual_data2$predicted_cumulative_confirmed_cases, tol = 0.01)))
######
## Want to get to a point where we're using predict to get the final log values for the country
######
# Shows the CIs for each cumulative prediction
# predict.felm(model, newdata = mmat_no_policy_counterfactual_cumulative, interval = "confidence")

true_data <- true_data %>% 
  ungroup() %>% 
  mutate(prediction_logdiff = {
    # This is a bit of a hack to get the predicted values added to the data.frame with
    # the NA values in the right place.
    tmp <- log_difference_cumulative_confirmed_cases
    tmp[!is.na(tmp)] <- predict.felm(model, newdata = mmat_actual) %>% pull(fit)
    tmp
  }) %>% 
  group_by(adm1_name) %>% 
  mutate(predicted_cumulative_confirmed_cases = 
           # Here we start at cumulative_confirmed_cases[1] - predict itself for the first one (exp(0))
           # Then predict the using the sum of the log changes from the second on
           cumulative_confirmed_cases[1]*exp(cumsum(c(0, prediction_logdiff[-1]))))

indices_with_na_y <- which(is.na(no_policy_counterfactual_data$log_difference_cumulative_confirmed_cases))
for(nm in colnames(mmat_no_policy_counterfactual)){
  no_policy_counterfactual_data <- no_policy_counterfactual_data %>% 
    ungroup() %>% 
    mutate(!!nm := {
      tmp = log_difference_cumulative_confirmed_cases
      tmp[!is.na(tmp)] <- mmat_no_policy_counterfactual[,nm]
      tmp
    })
  true_data <- true_data %>% 
    ungroup() %>% 
    mutate(!!nm := {
      tmp = log_difference_cumulative_confirmed_cases
      tmp[!is.na(tmp)] <- mmat_actual[,nm]
      tmp
    })
}

no_policy_counterfactual_data <- no_policy_counterfactual_data %>% 
  group_by(adm1_name) %>% 
  mutate_at(.vars = vars(colnames(mmat_no_policy_counterfactual)),
            list(nabla = ~{
              stopifnot(is.na(.x[1]))
              c(NA_real_, cumsum(.x[-1])) * predicted_cumulative_confirmed_cases
            }))

true_data <- true_data %>% 
  group_by(adm1_name) %>% 
  mutate_at(.vars = vars(colnames(mmat_actual)),
            list(nabla = ~{
              stopifnot(is.na(.x[1]))
              c(NA_real_, cumsum(.x[-1])) * predicted_cumulative_confirmed_cases
            }))

# The first day in the sample for each place is NA here. We're not including those dates in the prediction for that day
# Just the known first value for that place (not the prediction).
nabla_h_by_date_np <- no_policy_counterfactual_data %>% 
  group_by(adm1_name) %>%
  # Don't include the first day for anyone
  slice(-1) %>% 
  group_by(date) %>% 
  select(date, matches("nabla")) %>% 
  summarise_all(sum)

nabla_h_by_date_np_mat <- nabla_h_by_date_np %>% 
  select(-date) %>% 
  as.matrix()

bread_np <- nabla_h_by_date_np_mat
veggie_patty <- model$clustervcv
# Check the names are in the right order
stopifnot(all.equal(colnames(veggie_patty), colnames(bread_np) %>% str_replace("_nabla", "")))
standard_errors_by_day_np <- sqrt(diag(bread_np %*% veggie_patty %*% t(bread_np)))

nabla_h_by_date_true <- true_data %>% 
  group_by(adm1_name) %>%
  # Don't include the first day for anyone
  slice(-1) %>% 
  group_by(date) %>% 
  select(date, matches("nabla")) %>% 
  summarise_all(sum)

nabla_h_by_date_true_mat <- nabla_h_by_date_true %>% 
  select(-date) %>% 
  as.matrix()

bread_true <- nabla_h_by_date_true_mat
# Check the names are in the right order
stopifnot(all.equal(colnames(veggie_patty), colnames(bread_true) %>% str_replace("_nabla", "")))
standard_errors_by_day_true <- sqrt(diag(bread_true %*% veggie_patty %*% t(bread_true)))

options(scipen=10000)
np <- no_policy_counterfactual_data %>%
  group_by(date) %>% 
  summarise(predicted_cumulative_confirmed_cases = 
              sum(predicted_cumulative_confirmed_cases)) %>% 
  mutate(se_prediction = c(0, standard_errors_by_day_np)) %>% 
  mutate(upper_ci = predicted_cumulative_confirmed_cases + 1.96*se_prediction,
         lower_ci = predicted_cumulative_confirmed_cases - 1.96*se_prediction) %>% 
  ggplot() + 
  geom_line(aes(x = date, y = predicted_cumulative_confirmed_cases), size = 1.5) + 
  geom_ribbon(aes(x = date, ymin=lower_ci, ymax = upper_ci),
              fill = "gray50", alpha= 0.5) + 
  theme_classic() + 
  xlab("Date") + 
  ylab("Predicted cumulative confirmed cases without policy")

# This one looks wrong - seems like there should be more uncertainty here
true <- true_data %>%
  group_by(date) %>% 
  summarise(predicted_cumulative_confirmed_cases = 
              sum(predicted_cumulative_confirmed_cases)) %>% 
  mutate(se_prediction = c(0, standard_errors_by_day_true)) %>% 
  mutate(upper_ci = predicted_cumulative_confirmed_cases + 1.96*se_prediction,
         lower_ci = predicted_cumulative_confirmed_cases - 1.96*se_prediction) %>% 
  ggplot() + 
  geom_line(aes(x = date, y = predicted_cumulative_confirmed_cases), size = 1.5) + 
  geom_ribbon(aes(x = date, ymin=lower_ci, ymax = upper_ci),
              fill = "gray50", alpha= 0.5) + 
  theme_classic() + 
  xlab("Date") + 
  ylab("Predicted cumulative confirmed cases with policy")

out <- np / true
ggsave(out, filename = "figures/fig2/FRA_projections_with_uncertainty.pdf", width = 5, height = 10)
