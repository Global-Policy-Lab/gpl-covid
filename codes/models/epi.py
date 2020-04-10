"""
Functions to help in infectious disease simulation.
"""

import numpy as np
import pandas as pd
import xarray as xr
import statsmodels.formula.api as smf
from collections import OrderedDict


def init_reg_arrs(n_samples, n_reg, n_policies, *args):
    dims = [n_samples]
    for a in args:
        dims.append(a)
    s_mins = np.empty(dims, dtype=np.float32)
    s_mins_p3 = s_mins.copy()
    dims += [n_reg, n_policies + 1]
    estimates = np.empty(dims, dtype=np.float32)
    estimates.fill(np.nan)

    return estimates, s_mins, s_mins_p3


def init_state_arrays(shp, n_arrays):
    return [np.ones(shp) * np.nan for a in range(n_arrays)]


def adjust_timescales_from_daily(tsteps_per_day, *args):
    return [i / tsteps_per_day for i in args]


def init_policy_dummies(
    effects, starts, ends, daily_lag_vals, n_samples, n_steps, steps_per_day, seed=0
):
    np.random.seed(seed)
    n_effects = len(effects)
    dates = np.empty((n_samples, n_effects), dtype=np.int16)
    for ix, i in enumerate(effects):
        dates[:, ix] = np.random.randint(starts[ix], ends[ix], n_samples)

    # drop any with complete collinearity of policies
    valid = np.apply_along_axis(
        lambda x: len(x) == dates.shape[1], 1, np.unique(dates, axis=1)
    )
    dates = dates[valid]
    n_samples = dates.shape[0]

    # create policy dummy array
    comp = np.repeat(np.arange(n_steps)[:, np.newaxis], dates.shape[1], axis=1)
    out = (comp.T[np.newaxis, ...] >= dates[..., np.newaxis] * steps_per_day).astype(
        float
    )

    # get lags in appropriate timesteps
    lags = []
    for l in daily_lag_vals:
        this_new_lag = []
        for i in l:
            this_new_lag += [i] * steps_per_day
        lags.append(this_new_lag)

    # adjust for lags
    p_on = out.argmax(axis=-1)
    for lx, l in enumerate(lags):
        for sx in range(out.shape[0]):
            this_p_on = p_on[sx, lx]
            out[sx, lx, this_p_on : this_p_on + len(l)] = l

    return out.swapaxes(1, 2)


def get_beta_SEIR(growth_rate_deterministic, gamma_to_test, sigma_to_test):
    """
    In a SEIR model, $\beta$ in a S~=1 setting is a function of the exponential growth 
    rate, sigma, and gamma. This calculates that based on the deterministic gamma and 
    sigmas.
    """
    gammas = np.repeat(
        np.array(gamma_to_test)[:, np.newaxis], len(sigma_to_test), axis=1
    )
    sigmas = np.repeat(
        np.array(sigma_to_test)[np.newaxis, :], len(gamma_to_test), axis=0
    )
    g = growth_rate_deterministic[..., np.newaxis, np.newaxis]
    return (g + gammas) * (g + sigmas) / sigmas


def get_stochastic_params(
    beta_det,
    beta_noise_sd,
    beta_noise_on,
    gamma_to_test,
    gamma_noise_sd,
    gamma_noise_on,
    sigma_to_test=None,
    sigma_noise_sd=None,
    sigma_noise_on=False,
):
    if beta_noise_on:
        beta_noise = np.random.normal(0, beta_noise_sd, beta_det.shape[:2])
    else:
        beta_noise = np.zeros(beta_det.shape[:2])
    # adjust for at least gamma dimension (SIR)
    beta_noise = beta_noise[..., np.newaxis]

    if gamma_noise_on:
        gamma_noise = np.random.normal(0, gamma_noise_sd, beta_det.shape[:2])
    else:
        gamma_noise = np.zeros(beta_det.shape[:2])
    this_gamma = gamma_noise[..., np.newaxis] + np.array(gamma_to_test)

    if sigma_to_test is not None:
        assert len(beta_det.shape) == 4
        beta_noise = beta_noise[..., np.newaxis]
        this_gamma = this_gamma[..., np.newaxis]
        if sigma_noise_on:
            sigma_noise = np.random.normal(0, sigma_noise_sd, beta_det.shape[:2])
        else:
            sigma_noise = np.zeros(beta_det.shape[:2])
        this_sigma = sigma_noise[..., np.newaxis, np.newaxis] + np.array(sigma_to_test)
        sigma_out = [this_sigma]
    else:
        assert len(beta_det.shape) == 3
        sigma_out = []

    this_beta = beta_noise + beta_det
    out_vals = [this_beta, this_gamma] + sigma_out

    # make sure none are non-positive
    out_vals = [np.where(i > 0, i, 0) for i in out_vals]

    return out_vals


def run_SEIR(E0, I0, R0, beta, gamma, sigma, n_samp=1):
    """
    Simulate SEIR model using forward euler integration. All states are defined as 
    fractions of a population.
    
    Parameters
    ----------
    E0, I0, R0 : float
        Initial conditions in fractions (S0 is just 1 minus the sum of these)
    beta, gamma, sigma : :class:`numpy.ndarray`
        Time-dependent parameters of the model. Must each be 4d-arrays. They should
        have the following dimensions: (n_steps, n_gamma, n_sigma, n_samples), except 
        that gamma and beta may have len 1 in the opposite dimension. I.e. gamma could
        have shape (n_steps, n_gamma, 1, n_samples), because it is not changing with 
        sigma.
    
    Returns
    -------
    S, E, I, R : :class:`numpy.ndarray`
        State space of the model at all timesteps
    """

    n_steps = beta.shape[0]

    S, E, I, R = init_state_arrays(beta.shape, 4)
    
    # initial conditions
    R[0] = R0
    I[0] = I0
    E[0] = E0
    S[0] = 1 - I[0] - R[0] - E[0]

    for i in range(1, n_steps):
        new_exposed = beta[i - 1] * S[i - 1] * I[i - 1]
        new_infected = sigma[i - 1] * E[i - 1]
        new_removed = gamma[i - 1] * I[i - 1]

        S[i] = S[i - 1] - new_exposed
        E[i] = E[i - 1] + new_exposed - new_infected
        I[i] = I[i - 1] + new_infected - new_removed
        R[i] = 1 - S[i] - E[i] - I[i]

    return S, E, I, R


def get_case_df(
    mod_type,
    state_arrs,
    policy_arr,
    t,
    steps_per_output,
    pop,
    param_arr_dict=None,
    debug=False,
):
    assert len(mod_type) == len(state_arrs)
    state_dict = {i: state_arrs[ix] for ix, i in enumerate(mod_type)}

    if debug:
        assert param_arr_dict is not None
        state_dict = {**state_dict, **param_arr_dict}
    index = pd.Index(t.astype(int), name="day")
    df = pd.DataFrame(state_dict, index=index).iloc[::steps_per_output, :]
    df.loc[:, list(mod_type)] *= pop
    df["IR"] = df["I"] + df["R"]
    if mod_type == "SEIR":
        df["EI"] = df["E"] + df["I"]
        df["EIR"] = df["EI"] + df["R"]

    policy_df = pd.DataFrame(
        policy_arr,
        index=index,
        columns=[f"p{ix+1}" for ix in range(policy_arr.shape[1])],
    ).iloc[::steps_per_output, :]
    df = pd.concat((df, policy_df), axis=1)
    return df


def run_regressions(cases, LHS_vars, policy_vars, min_cases):
    out = np.empty((len(LHS_vars), len(policy_vars) + 1), dtype=np.float32)
    out.fill(np.nan)
    # get regression estimates
    for ix, case_var in enumerate(LHS_vars):
        # only save if there is a single day without policies, so we have something
        # with which to estimate no-policy growth
        if cases.loc[(cases[case_var]) >= min_cases, policy_vars].iloc[0].max() == 0:
            lhs_name = case_var + "_logdiff"
            cases[lhs_name] = -np.log(cases[case_var]).diff(-1)
            rhs_name = " + ".join(policy_vars)
            res = smf.ols(
                f"{lhs_name} ~ {rhs_name}",
                data=cases,
                subset=cases[case_var] >= min_cases,
            ).fit()
            out[ix, :] = res.params.values
    return out


def res_arr_to_ds(estimates, reg_to_run, policies_to_include, param_kwargs, **attrs):
    ix_samples = len(param_kwargs)
    n_samples = estimates.shape[ix_samples]
    ## Convert array to Dataset
    coords = param_kwargs.copy()
    coords["sample"] = range(n_samples)
    coords["case_type"] = reg_to_run
    coords["reg_param"] = ["Intercept"] + policies_to_include

    out = xr.DataArray(
        estimates, coords=coords, dims=coords.keys(), attrs=attrs
    ).to_dataset(dim="reg_param")
    out["cum_effect"] = (
        out[policies_to_include].to_array().sum(dim="variable", skipna=False)
    )

    return out
