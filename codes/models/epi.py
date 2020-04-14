"""
Functions to help in infectious disease simulation.
"""

import numpy as np
import pandas as pd
import xarray as xr
from collections import OrderedDict
from statsmodels.api import OLS, add_constant


def init_reg_ds(n_samples, LHS_vars, policies, **dim_kwargs):
    """
    Initialize a Dataset to place regression estimates
    """

    coords = {
        "sample": range(n_samples),
    }
    coords = {**coords, **dim_kwargs}

    estimate_coords = {**coords, **{"LHS": LHS_vars, "policy": list(policies)}}

    estimates = xr.DataArray(
        coords=estimate_coords, dims=estimate_coords.keys(), name="coefficient"
    )
    s_mins = xr.DataArray(coords=coords, dims=coords.keys(), name="S_min")
    s_mins_p3 = s_mins.copy()
    s_mins_p3.name = "S_min_p3"

    return xr.merge([estimates, s_mins, s_mins_p3])


def init_state_arrays(shp, n_arrays):
    return [np.ones(shp) * np.nan for a in range(n_arrays)]


def adjust_timescales_from_daily(ds):
    out = ds.copy()
    tstep = ds.t[1] - ds.t[0]
    for k, v in ds.variables.items():
        # only adjust variables, not coordinates
        if len(k.split("_")) > 1 and k.split("_")[0] in [
            "lambda",
            "beta",
            "gamma",
            "sigma",
        ]:
            out[k] = out[k] * tstep
    return out


def init_policy_dummies(policy_ds, n_samples, t, seed=0):
    """
    Initialize dummy variables to define policy effects
    """

    np.random.seed(seed)
    n_effects = policy_ds.policy.shape[0]
    n_steps = len(t)
    steps_per_day = int(np.round(1 / ((t.max() - t.min()) / (t.shape[0] - 1))))

    dates = np.empty((n_samples, n_effects), dtype=np.int16)
    for ix in range(n_effects):
        dates[:, ix] = np.random.randint(
            policy_ds.interval.sel(time="start")[ix],
            policy_ds.interval.sel(time="end")[ix],
            n_samples,
        )

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
    for l in policy_ds.policy:
        this_lag = policy_ds.lag.sel(policy=l.item())
        this_new_lag = []
        for i in this_lag:
            this_new_lag += [i] * steps_per_day
        lags.append(this_new_lag)

    # adjust for lags
    p_on = out.argmax(axis=-1)
    for lx, l in enumerate(lags):
        for sx in range(out.shape[0]):
            this_p_on = p_on[sx, lx]
            out[sx, lx, this_p_on : this_p_on + len(l)] = l

    out = out.swapaxes(1, 2)
    coords = OrderedDict(sample=range(n_samples), t=t, policy=policy_ds.policy,)
    out = xr.DataArray(out, coords=coords, dims=coords.keys(), name="policy_timeseries")
    return out


def get_beta_SEIR(lambdas, gammas, sigmas):
    """
    In a SEIR model, $\beta$ in a S~=1 setting is a function of the exponential growth 
    rate ($\lambda$), $\sigma$, and $\gamma$. This calculates that based on the deterministic gamma and 
    sigmas.
    """
    return (lambdas + gammas) * (lambdas + sigmas) / sigmas


def get_stochastic_params(
    estimates_ds,
    beta_noise_sd,
    beta_noise_on,
    gamma_noise_sd,
    gamma_noise_on,
    sigma_noise_sd=None,
    sigma_noise_on=False,
):

    if "sample" not in estimates_ds:
        estimates_ds = estimates_ds.expand_dims("sample")

    sampXtime = (len(estimates_ds.sample), len(estimates_ds.t))
    out_vars = ["beta_stoch", "gamma_stoch"]
    if beta_noise_on:
        estimates_ds["beta_stoch"] = (
            ("sample", "t"),
            np.random.normal(0, beta_noise_sd, sampXtime),
        )
        estimates_ds["beta_stoch"] = (
            estimates_ds.beta_deterministic + estimates_ds["beta_stoch"]
        )
    else:
        estimates_ds["beta_stoch"] = estimates_ds.beta_deterministic.copy()

    if gamma_noise_on:
        estimates_ds["gamma_stoch"] = (
            ("sample", "t"),
            np.random.normal(0, gamma_noise_sd, sampXtime),
        )
        estimates_ds["gamma_stoch"] = estimates_ds.gamma + estimates_ds["gamma_stoch"]
    else:
        estimates_ds["gamma_stoch"] = estimates_ds.gamma.copy()

    if "sigma" in estimates_ds.dims:
        out_vars.append("sigma_stoch")
        if sigma_noise_on:
            estimates_ds["sigma_stoch"] = (
                ("sample", "t"),
                np.random.normal(0, sigma_noise_sd, sampXtime),
            )
            estimates_ds["sigma_stoch"] = (
                estimates_ds.sigma + estimates_ds["sigma_stoch"]
            )
        else:
            estimates_ds["sigma_stoch"] = estimates_ds.sigma.copy()

    # make sure none are non-positive
    estimates_ds = estimates_ds.drop(out_vars).merge(
        estimates_ds[out_vars].where(estimates_ds[out_vars] > 0, 0)
    )

    return estimates_ds.squeeze()


def run_SIR(I0, R0, ds):
    """
    Simulate SIR model using forward euler integration. All states are defined as 
    fractions of a population.
    """
    n_steps = len(ds.t)

    new_dims = ["t"] + [i for i in ds.beta_stoch.dims if i != "t"]
    beta = ds.beta_stoch.transpose(*new_dims)
    gamma = ds.gamma_stoch.broadcast_like(beta)

    S, I, R = init_state_arrays(beta.shape, 3)

    # initial conditions
    R[0] = R0
    I[0] = I0
    S[0] = 1 - I[0] - R[0]

    for i in range(1, n_steps):
        new_infected_rate = beta[i - 1] * S[i - 1]
        new_removed_rate = gamma[i - 1]

        S[i] = S[i - 1] - new_infected_rate * I[i - 1]
        I[i] = I[i - 1] * np.exp(new_infected_rate - new_removed_rate)
        R[i] = 1 - S[i] - I[i]

    out = ds.copy()
    for ox, o in enumerate([S, E, I, R]):
        name = "SIR"[ox]
        out[name] = (new_dims, o)

    return out


def run_SEIR(E0, I0, R0, ds):
    """
    Simulate SEIR model using forward euler integration. All states are defined as 
    fractions of a population.
    """

    n_steps = len(ds.t)

    new_dims = ["t"] + [i for i in ds.beta_stoch.dims if i != "t"]
    beta = ds.beta_stoch.transpose(*new_dims)
    gamma = ds.gamma_stoch.broadcast_like(beta)
    sigma = ds.sigma_stoch.broadcast_like(beta)

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

    out = ds.copy()
    for ox, o in enumerate([S, E, I, R]):
        name = "SEIR"[ox]
        out[name] = (new_dims, o)

    return out


def simulate_regress_SEIR(
    E0,
    I0,
    R0,
    pop,
    no_policy_growth_rate,
    p_effects,
    p_lags,
    p_start_date,
    p_end_date,
    n_days,
    tsteps_per_day,
    n_samples,
    LHS_vars,
    reg_lag_days,
    sigma_to_test,
    gamma_to_test,
    beta_noise_sd,
    beta_noise_on,
    gamma_noise_sd,
    gamma_noise_on,
    sigma_noise_sd,
    sigma_noise_on,
    min_cases,
    save_dir=None,
):

    attrs = dict(
        E0=E0,
        I0=I0,
        R0=R0,
        pop=pop,
        min_cases=min_cases,
        beta_noise_on=int(beta_noise_on),
        gamma_noise_on=int(gamma_noise_on),
        sigma_noise_on=int(sigma_noise_on),
        beta_noise_sd=beta_noise_sd,
        gamma_noise_sd=gamma_noise_sd,
        sigma_noise_sd=sigma_noise_sd,
        no_policy_growth_rate=no_policy_growth_rate,
        tsteps_per_day=tsteps_per_day,
    )

    E0 = E0 / pop
    I0 = I0 / pop
    R0 = R0 / pop

    # store policy info
    policies = xr.Dataset(
        coords={
            "policy": [f"p{i+1}" for i in range(len(p_effects))],
            "time": ["start", "end"],
            "lag_num": range(len(p_lags[0])),
        },
        data_vars={
            "effect": (("policy",), p_effects),
            "lag": (("policy", "lag_num"), p_lags),
            "interval": (("policy", "time"), np.array([p_start_date, p_end_date]).T),
        },
    )

    # get time vector
    ttotal = n_days * tsteps_per_day + 1
    t = np.linspace(0, 1, ttotal) * n_days

    # initialize results array
    estimates_ds = init_reg_ds(
        n_samples,
        LHS_vars,
        policies.policy.values,
        gamma=gamma_to_test,
        sigma=sigma_to_test,
    )

    # get policy effects
    policy_dummies = init_policy_dummies(policies, n_samples, t, seed=0,)
    policies = xr.merge((policies, policy_dummies))
    policy_effect_timeseries = (policies.policy_timeseries * policies.effect).sum(
        "policy"
    )
    n_samp_valid = len(policies.sample)

    # get deterministic params
    estimates_ds["lambda_deterministic"] = (
        np.ones_like(t) * no_policy_growth_rate + policy_effect_timeseries
    )
    estimates_ds["beta_deterministic"] = get_beta_SEIR(
        estimates_ds.lambda_deterministic, estimates_ds.gamma, estimates_ds.sigma
    )

    # get stochastic params
    estimates_ds = get_stochastic_params(
        estimates_ds,
        beta_noise_sd,
        beta_noise_on,
        gamma_noise_sd,
        gamma_noise_on,
        sigma_noise_sd=sigma_noise_sd,
        sigma_noise_on=sigma_noise_on,
    )

    # adjust rate params to correct timestep
    estimates_ds = adjust_timescales_from_daily(estimates_ds)

    # run simulation
    estimates_ds = run_SEIR(E0, I0, R0, estimates_ds)

    # add on other potentially observable quantities
    estimates_ds["EI"] = estimates_ds["E"] + estimates_ds["I"]
    estimates_ds["IR"] = estimates_ds["R"] + estimates_ds["I"]
    estimates_ds["EIR"] = estimates_ds["EI"] + estimates_ds["R"]

    # get minimum S for each simulation
    # at end and when p3 turns on
    estimates_ds["S_min"] = estimates_ds.S.isel(t=-1)
    p3_on = (policies.policy_timeseries.isel(policy=-1) > 0).argmax(dim="t")
    estimates_ds["S_min_p3"] = estimates_ds.S.isel(t=p3_on)

    # blend in policy dataset
    estimates_ds = estimates_ds.merge(policies)

    # convert to daily observations
    daily_ds = estimates_ds.sel(
        t=slice(0, None, int(np.round(1 / (estimates_ds.t[1] - estimates_ds.t[0]))))
    )

    # prep regression LHS vars (logdiff)
    new = (
        np.log(daily_ds[daily_ds.LHS.values])
        .diff(dim="t", n=1, label="lower")
        .pad(t=(0, 1))
        .to_array(dim="LHS")
    )
    daily_ds["logdiff"] = new

    ## run regressions
    estimates = np.empty(
        (
            len(daily_ds.gamma),
            len(daily_ds.sigma),
            len(daily_ds.sample),
            len(daily_ds.LHS),
            len(daily_ds.policy) * len(reg_lag_days) + 1,
        ),
        dtype=np.float32,
    )
    estimates.fill(np.nan)

    # add on lags
    RHS_old = (daily_ds.policy_timeseries > 0).astype(int)
    RHS_ds = xr.ones_like(RHS_old.isel(policy=0))
    RHS_ds["policy"] = "Intercept"
    for l in reg_lag_days:
        lag_vars = RHS_old.shift(t=l, fill_value=0)
        lag_vars["policy"] = [f"{x}_lag{l}" for x in RHS_old.policy.values]
        RHS_ds = xr.concat((RHS_ds, lag_vars), dim="policy")

    # Apply min cum_cases threshold used in regressions
    valid_reg = daily_ds.I >= min_cases / pop

    # only run regression if we have at least one "no-policy" day
    no_pol_on_regday0 = (RHS_old > 0).max(dim="policy").argmax(
        dim="t"
    ) > valid_reg.argmax(dim="t")

    # loop through regressions
    for cx, case_var in enumerate(daily_ds.LHS.values):
        case_ds = daily_ds.logdiff.sel(LHS=case_var)
        for gx, g in enumerate(daily_ds.gamma.values):
            g_ds = case_ds.sel(gamma=g)
            for sx, s in enumerate(daily_ds.sigma.values):
                s_ds = g_ds.sel(sigma=s)
                for samp in daily_ds.sample.values:
                    if no_pol_on_regday0.isel(sample=samp, gamma=gx, sigma=sx):
                        this_valid = valid_reg.isel(sample=samp, gamma=gx, sigma=sx)
                        LHS = s_ds.isel(sample=samp)[this_valid].values
                        RHS = add_constant(
                            RHS_ds.isel(sample=samp)[{"t": this_valid}].values
                        )
                        res = OLS(LHS, RHS, missing="drop").fit()
                        estimates[gx, sx, samp, cx] = res.params

    coords = OrderedDict(
        gamma=daily_ds.gamma,
        sigma=daily_ds.sigma,
        sample=daily_ds.sample,
        LHS=daily_ds.LHS,
        policy=RHS_ds.policy,
    )
    e = xr.DataArray(estimates, coords=coords, dims=coords.keys()).to_dataset("policy")

    coeffs = []
    for p in daily_ds.policy.values:
        keys = [i for i in e.variables.keys() if f"{p}_" in i]
        coeffs.append(
            e[keys]
            .rename({k: int(k.split("_")[-1][3:]) for k in keys})
            .to_array(dim="reg_lag")
        )
    coef_ds = xr.concat(coeffs, dim="policy")
    coef_ds.name = "coefficient"
    daily_ds = daily_ds.drop("coefficient").merge(coef_ds)
    daily_ds["Intercept"] = e["Intercept"]

    # add model params
    daily_ds.attrs = attrs

    if save_dir is not None:
        fname = f"pop_{int(pop)}_lag_{'-'.join([str(s) for s in reg_lag_days])}.nc"
        daily_ds.to_netcdf(save_dir / fname)

    return daily_ds
