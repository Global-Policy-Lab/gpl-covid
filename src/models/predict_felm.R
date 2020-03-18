#' @title Predict method for S3 felm objects
#' @description Predict method for S3 felm objects. Requires
#' newdata to be explicitly provided and does not predict using
#' and variables that were projected out.
#' The order of preference for the variance-covariance
#' matrix is object$clustervcv, object$robustvcv,
#' then object$vcv. The only implemented features are
#' predictions, se.fit, and confidence intervals.
#' @export
predict.felm <- function(object, newdata, se.fit = FALSE,
                         interval = "none",
                         level = 0.95){
  if(missing(newdata)){
    stop("predict.felm requires newdata and predicts for all group effects = 0.")
  }
  
  tt <- terms(object)
  Terms <- delete.response(tt)
  if(!"(Intercept)" %in% rownames(object$coefficients)){
    attr(Terms, "intercept") <- 0
  }
  
  m.mat <- as.matrix(newdata)

  m.coef <- as.numeric(object$coefficients)
  m.coef[is.nan(m.coef)] <- 0
  fit <- as.vector(m.mat %*% m.coef)
  fit <- data.frame(fit = fit)
  
  if(se.fit | interval != "none"){
    if(!is.null(object$clustervcv)){
      vcov_mat <- object$clustervcv
    } else if (!is.null(object$robustvcv)) {
      vcov_mat <- object$robustvcv
    } else if (!is.null(object$vcv)){
      vcov_mat <- object$vcv
    } else {
      stop("No vcv attached to felm object.")
    }
    se.fit_mat <- sqrt(diag(m.mat %*% vcov_mat %*% t(m.mat)))
  }
  if(interval == "confidence"){
    t_val <- qt((1 - level) / 2 + level, df = object$df.residual)
    fit$lwr <- fit$fit - t_val * se.fit_mat
    fit$upr <- fit$fit + t_val * se.fit_mat
  } else if (interval == "prediction"){
    stop("interval = \"prediction\" not yet implemented")
  }
  if(se.fit){
    return(list(fit=fit, se.fit=se.fit_mat))
  } else {
    return(fit)
  }
}
